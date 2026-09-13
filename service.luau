--!nonstrict
-- Polls `herdr api snapshot`, publishes one row per agent pane, and runs focus
-- commands. herdr reports no timestamps, so "last update" is when this service
-- first saw the agent's current (status, state_change_seq); it is persisted so a
-- shell reload does not reset every agent to "just now".

local shared = require("./shared.luau")

local seen = {} -- terminal_id -> { sig = string, at = unix seconds }
local inFlight = false

local function str(v)
  if type(v) == "string" and v ~= "" then
    return v
  end
  return nil
end

local function herdrArgv(...)
  local argv = {}
  local socket = str(noctalia.getConfig("socket_path"))
  if socket then
    table.insert(argv, "env")
    table.insert(argv, "HERDR_SOCKET_PATH=" .. noctalia.expandPath(socket))
  end
  for _, arg in ipairs({ ... }) do
    table.insert(argv, arg)
  end
  return argv
end

local function cachePath()
  local dir = noctalia.pluginDataDir()
  return dir and (dir .. "/last-change.json")
end

local function loadCache()
  local path = cachePath()
  local raw = path and noctalia.readFile(path)
  local decoded = raw and noctalia.json.decode(raw)
  if type(decoded) == "table" then
    seen = decoded
  end
end

local function saveCache()
  local path = cachePath()
  local encoded = path and noctalia.json.encode(seen)
  if encoded then
    noctalia.writeFile(path, encoded)
  end
end

local function indexBy(list, key)
  local out = {}
  for _, item in ipairs(list or {}) do
    out[item[key]] = item
  end
  return out
end

local function basename(path)
  return path:match("([^/]+)/?$") or path
end

-- Two agents split across panes of the same tab otherwise get an identical label
-- (both fall back to the tab's own title). Disambiguate with the cwd basename when
-- that differs between them, or a plain ordinal when it doesn't.
local function disambiguateLabels(rows)
  local groups = {}
  for _, r in ipairs(rows) do
    local gkey = tostring(r.tab_id) .. "\0" .. r.label
    groups[gkey] = groups[gkey] or {}
    table.insert(groups[gkey], r)
  end
  for _, group in pairs(groups) do
    if #group > 1 then
      local seenCwd, distinctCwd = {}, true
      for _, r in ipairs(group) do
        local b = r.cwd ~= "" and basename(r.cwd) or nil
        if not b or seenCwd[b] then
          distinctCwd = false
          break
        end
        seenCwd[b] = true
      end
      for i, r in ipairs(group) do
        r.label = r.label .. (distinctCwd and ("  ·  " .. basename(r.cwd)) or ("  #" .. i))
      end
    end
  end
end

local function publishSnapshot(snap)
  local workspaces = indexBy(snap.workspaces, "workspace_id")
  local tabs = indexBy(snap.tabs, "tab_id")
  local now = os.time()
  local rows, live, dirty = {}, {}, false

  for _, a in ipairs(snap.agents or {}) do
    local agent = str(a.agent)
    if agent then
      local key = a.terminal_id or a.pane_id
      local sig = tostring(a.agent_status) .. ":" .. tostring(a.state_change_seq or 0)
      local entry = seen[key]
      if entry == nil or entry.sig ~= sig then
        entry = { sig = sig, at = now }
        seen[key] = entry
        dirty = true
      end
      live[key] = true

      local ws = workspaces[a.workspace_id] or {}
      local tab = tabs[a.tab_id] or {}
      local display = str(a.display_agent)
      table.insert(rows, {
        pane_id = a.pane_id,
        tab_id = a.tab_id,
        agent = agent,
        status = str(a.agent_status) or "unknown",
        label = str(a.name) or str(a.title) or (display and display:gsub("^[^:]+: ", "")) or str(tab.label) or agent,
        cwd = str(a.foreground_cwd) or str(a.cwd) or "",
        workspace = str(ws.label) or a.workspace_id or "",
        tab = str(tab.label) or a.tab_id or "",
        changed_at = entry.at,
      })
    end
  end

  for key in pairs(seen) do
    if not live[key] then
      seen[key] = nil
      dirty = true
    end
  end
  if dirty then
    saveCache()
  end

  disambiguateLabels(rows)
  noctalia.state.set(shared.STATE_ERROR, nil)
  noctalia.state.set(shared.STATE_AGENTS, shared.sort(rows))
end

local function fail(message)
  noctalia.state.set(shared.STATE_ERROR, message)
  noctalia.state.set(shared.STATE_AGENTS, {})
end

local function poll()
  if inFlight then
    return
  end
  if not noctalia.commandExists("herdr") then
    fail(noctalia.tr("error.herdr_missing"))
    return
  end
  inFlight = true
  noctalia.runAsync(herdrArgv("herdr", "api", "snapshot"), function(res)
    inFlight = false
    local ok, err = pcall(function()
      -- herdr prints its JSON error envelope to stderr on failure.
      local decoded = noctalia.json.decode(res.stdout or "")
      if type(decoded) ~= "table" then
        decoded = noctalia.json.decode(res.stderr or "")
      end
      if type(decoded) ~= "table" then
        fail(str(noctalia.string.trim(res.stderr or "")) or noctalia.tr("error.herdr_unavailable"))
        return
      end
      if type(decoded.error) == "table" then
        fail(decoded.error.message or decoded.error.code or noctalia.tr("error.herdr_unavailable"))
        return
      end
      local result = decoded.result or decoded
      publishSnapshot(result.snapshot or result)
    end)
    if not ok then
      noctalia.log("[claude-sessions] snapshot error: " .. tostring(err))
      fail(tostring(err))
    end
  end, 5000)
end

local function focus(paneId)
  if not str(paneId) then
    return
  end
  local script = noctalia.pluginDir() .. "/scripts/focus-agent.sh"
  noctalia.runAsync(herdrArgv("bash", script, paneId), function(res)
    if res.exitCode ~= 0 then
      local detail = noctalia.string.trim(res.stderr or "")
      noctalia.notifyError(noctalia.tr("title"), noctalia.tr("error.focus_failed", { detail = detail }))
    end
    poll()
  end, 10000)
end

noctalia.state.watch(shared.STATE_CMD, function(cmd)
  if type(cmd) ~= "table" then
    return
  end
  noctalia.state.set(shared.STATE_CMD, nil)
  if cmd.op == "focus" then
    focus(cmd.pane_id)
  elseif cmd.op == "refresh" then
    poll()
  end
end)

-- noctalia msg plugin SharonFabin/claude-sessions:service all focus <pane_id>
function onIpc(event, payload)
  if event == "focus" then
    focus(payload)
  elseif event == "refresh" then
    poll()
  elseif event == "toggle" then
    noctalia.togglePanel(shared.PANEL_ID)
  end
end

local function applyInterval()
  noctalia.setUpdateInterval(tonumber(noctalia.getConfig("poll_interval_ms")) or 2000)
end

function onConfigChanged()
  applyInterval()
  poll()
end

function update()
  poll()
end

loadCache()
applyInterval()
poll()
