--!nonstrict
-- Bar widget: sparkles glyph tinted by the most urgent status, plus per-status counts.

local shared = require("./shared.luau")

local agents = noctalia.state.get(shared.STATE_AGENTS) or {}
local err = noctalia.state.get(shared.STATE_ERROR)
local vertical = barWidget.isVertical()

local function render()
  local counts = shared.counts(agents)
  local children = {
    ui.glyph({ name = "sparkles", color = err and "error" or shared.summaryColor(counts) }),
  }
  local tooltip = {}

  for _, status in ipairs(shared.BAR_ORDER) do
    local n = counts[status]
    if n > 0 then
      table.insert(tooltip, { key = noctalia.tr("status." .. status), value = tostring(n) })
      if not vertical then
        table.insert(children, ui.row({ gap = 2, align = "center" }, {
          ui.glyph({ name = shared.glyph(status), color = shared.color(status), size = 12 }),
          ui.label({ text = tostring(n) }),
        }))
      end
    end
  end

  barWidget.render(ui.row({ gap = 6, align = "center" }, children))
  if err then
    barWidget.setTooltip(err)
  elseif #tooltip == 0 then
    barWidget.setTooltip(noctalia.tr("panel.empty"))
  else
    barWidget.setTooltip(tooltip)
  end
end

noctalia.state.watch(shared.STATE_AGENTS, function(value)
  agents = type(value) == "table" and value or {}
  render()
end)

noctalia.state.watch(shared.STATE_ERROR, function(value)
  err = value
  render()
end)

function onClick()
  noctalia.togglePanel(shared.PANEL_ID)
end

render()
