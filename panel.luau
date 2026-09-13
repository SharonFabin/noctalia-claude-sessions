--!nonstrict
-- Panel: searchable agent list. Click, or arrows/Ctrl+N/P + Enter, focuses the
-- agent's Hyprland window and herdr pane (the service runs the command).

local shared = require("./shared.luau")

local agents = noctalia.state.get(shared.STATE_AGENTS) or {}
local err = noctalia.state.get(shared.STATE_ERROR)
local query = ""
local selected = 1
local inputRev = 0
local open = false
local tick = 0
local frameAcc = 0
local spinIntervalMs = 100

local function applySpinInterval()
  spinIntervalMs = tonumber(noctalia.getConfig("spinner_interval_ms")) or 100
end
applySpinInterval()

local function matches(a, q)
  if q == "" then
    return true
  end
  for _, field in ipairs({ a.label, a.agent, a.status, a.workspace, a.tab, a.pane_id, a.cwd }) do
    if field and field:lower():find(q, 1, true) then
      return true
    end
  end
  return false
end

local function visible()
  local q = query:lower()
  local list = {}
  for _, a in ipairs(agents) do
    if matches(a, q) then
      table.insert(list, a)
    end
  end
  return list
end

-- ui.scroll has no scroll-into-view API, so instead of scrolling we window the
-- list around the selected row. WINDOW has to fit inside the panel's declared
-- height (plugin.toml) with room to spare, or the tail of the window itself
-- needs scrolling and we're back to the same bug.
local WINDOW = 6
local ONE_DAY = 24 * 60 * 60

local function windowRange(total, sel)
  if total <= WINDOW then
    return 1, total
  end
  local start = math.max(1, math.min(sel - WINDOW // 2, total - WINDOW + 1))
  return start, start + WINDOW - 1
end

local function isRecent(a)
  return (os.time() - (a.changed_at or 0)) < ONE_DAY
end

local function divider(key, labeled)
  local children = { ui.box({ height = 1, flexGrow = 1, fill = "outline/0.5" }) }
  if labeled then
    table.insert(children, ui.label({ text = noctalia.tr("panel.older"), fontSize = 10, color = "on_surface_variant" }))
    table.insert(children, ui.box({ height = 1, flexGrow = 1, fill = "outline/0.5" }))
  end
  return ui.row({ key = key, gap = 8, align = "center" }, children)
end

local function fold(key, count, trKey)
  return ui.label({ key = key, text = noctalia.tr(trKey, { n = count }), color = "on_surface_variant", fontSize = 11 })
end

local function shortCwd(cwd)
  local home = noctalia.getenv("HOME")
  if home and cwd:sub(1, #home) == home then
    return "~" .. cwd:sub(#home + 1)
  end
  return cwd
end

local function focusAgent(a)
  if not open or a == nil then
    return
  end
  open = false
  noctalia.state.set(shared.STATE_CMD, { op = "focus", pane_id = a.pane_id })
  panel.close()
end

local function statusBadge(status)
  local col = shared.color(status)
  return ui.column({ width = 26, height = 26, radius = 8, align = "center", justify = "center", fill = shared.tint(col, 0.14) }, {
    ui.glyph({ name = shared.glyph(status), color = col, size = 15 }),
  })
end

-- No animation API, so a working agent's spinner is a braille frame cycled on a
-- fast frame tick (see onFrameTick). The panel's default font has no braille
-- glyphs, so it's loaded explicitly here.
local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local SPINNER_COLOR = "#5b9bf0"
local SPINNER_FONT = select(1, noctalia.loadFont("/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf"))

local function spinner()
  return ui.label({
    text = SPINNER_FRAMES[(tick % #SPINNER_FRAMES) + 1],
    color = SPINNER_COLOR,
    fontSize = 15,
    fontFamily = SPINNER_FONT,
  })
end

local function row(a, index)
  local isSelected = index == selected
  local wsColor = shared.workspaceColor(a.workspace)
  local location = a.tab
  if a.cwd ~= "" then
    location = location .. "  ·  " .. shortCwd(a.cwd)
  end

  local main = { gap = 2, flexGrow = 1 }
  local mainChildren = {}
  if a.workspace ~= "" then
    table.insert(mainChildren, ui.row({ gap = 5, align = "center" }, {
      ui.box({ width = 5, height = 5, radius = 3, fill = wsColor }),
      ui.label({ text = a.workspace, color = wsColor, fontSize = 10, fontWeight = "semibold", maxLines = 1 }),
    }))
  end
  table.insert(mainChildren, ui.row({ gap = 8, align = "center" }, {
    ui.label({ text = a.label, fontWeight = "semibold", maxLines = 1 }),
    ui.label({ text = noctalia.tr("status." .. a.status), color = shared.color(a.status), fontSize = 11 }),
  }))
  table.insert(mainChildren, ui.label({ text = a.agent .. "  ·  " .. location, color = "on_surface_variant", fontSize = 11, maxLines = 1 }))

  local trailing = {}
  if a.status == "working" then
    table.insert(trailing, spinner())
  end
  table.insert(trailing, ui.label({ text = shared.ago(a.changed_at), color = "on_surface_variant", fontSize = 11 }))

  -- Selection is part of the key so a moved cursor rebuilds the rows whose fill changed.
  return ui.row({
    key = a.pane_id .. (isSelected and "|sel" or ""),
    gap = 10,
    align = "center",
    paddingH = 10,
    paddingV = 6,
    radius = 8,
    fill = isSelected and "primary/0.15" or "surface_variant/0.35",
    border = isSelected and "primary/0.4" or nil,
    borderWidth = isSelected and 1 or 0,
    onClick = function()
      focusAgent(a)
    end,
  }, {
    ui.box({ width = 3, height = 34, radius = 2, fill = wsColor }),
    statusBadge(a.status),
    ui.column(main, mainChildren),
    ui.column({ gap = 4, align = "end" }, trailing),
  })
end

function render()
  local list = visible()
  selected = math.max(1, math.min(selected, #list))

  local rows = {}
  if err then
    table.insert(rows, ui.label({ text = err, color = "error", fontSize = 12 }))
  elseif #list == 0 then
    local key = #agents == 0 and "panel.empty" or "panel.no_match"
    table.insert(rows, ui.label({ text = noctalia.tr(key), color = "on_surface_variant" }))
  else
    local startI, endI = windowRange(#list, selected)
    if startI > 1 then
      table.insert(rows, fold("fold-above", startI - 1, "panel.more_above"))
    end
    local labeledDivider = false
    for i = startI, endI do
      local a = list[i]
      if i > 1 and isRecent(list[i - 1]) and not isRecent(a) then
        table.insert(rows, divider("divider-" .. i, not labeledDivider))
        labeledDivider = true
      end
      table.insert(rows, row(a, i))
    end
    if endI < #list then
      table.insert(rows, fold("fold-below", #list - endI, "panel.more_below"))
    end
  end

  panel.render(ui.column({ gap = 10, padding = 12, flexGrow = 1 }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "sparkles", color = "primary" }),
      ui.label({ text = noctalia.tr("title"), fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
      ui.label({ text = tostring(#agents), color = "on_surface_variant" }),
    }),
    ui.input({
      key = "search-" .. inputRev,
      value = query,
      placeholder = noctalia.tr("panel.search"),
      focus = true,
      onChange = function(value)
        query = value
        selected = 1
        render()
      end,
      onSubmit = function()
        focusAgent(visible()[selected])
      end,
    }),
    ui.scroll({ key = "agents", flexGrow = 1, gap = 6 }, rows),
  }))
end

function onKey(chord, pressed)
  if not pressed then
    return
  end
  if chord == "enter" then
    focusAgent(visible()[selected])
    return
  end
  if chord == "down" or chord == "ctrl+n" then
    selected += 1
  elseif chord == "up" or chord == "ctrl+p" then
    selected -= 1
  end
  render()
end

local function hasWorking()
  for _, a in ipairs(agents) do
    if a.status == "working" then
      return true
    end
  end
  return false
end

function onOpen(_context)
  open = true
  query = ""
  selected = 1
  inputRev += 1
  panel.setWantsSecondTicks(true)
  panel.setNeedsFrameTick(hasWorking())
  noctalia.state.set(shared.STATE_CMD, { op = "refresh" })
  render()
end

function onClose()
  open = false
  panel.setNeedsFrameTick(false)
end

function update()
  if open then
    render()
  end
end

-- Drives the spinner: only running while a working agent is on screen.
function onFrameTick(deltaMs)
  frameAcc += deltaMs
  if frameAcc < spinIntervalMs then
    return
  end
  frameAcc %= spinIntervalMs
  tick += 1
  render()
end

function onConfigChanged()
  applySpinInterval()
end

noctalia.state.watch(shared.STATE_AGENTS, function(value)
  agents = type(value) == "table" and value or {}
  if open then
    panel.setNeedsFrameTick(hasWorking())
    render()
  end
end)

noctalia.state.watch(shared.STATE_ERROR, function(value)
  err = value
  if open then
    render()
  end
end)
