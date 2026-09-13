--!nonstrict
-- Status presentation and state keys shared by the service, bar and panel.

local shared = {}

shared.STATE_AGENTS = "claude_sessions.agents"
shared.STATE_ERROR = "claude_sessions.error"
shared.STATE_CMD = "claude_sessions.cmd"
shared.PANEL_ID = "SharonFabin/claude-sessions:panel"

-- herdr AgentStatus: idle | working | blocked | done | unknown. Order = panel sort order.
local STATUS = {
  blocked = { rank = 1, glyph = "bell", color = "error" },
  done = { rank = 2, glyph = "circle-check", color = "#4caf50" },
  working = { rank = 3, glyph = "brain", color = "primary" },
  idle = { rank = 4, glyph = "clock", color = "on_surface_variant" },
  unknown = { rank = 5, glyph = "circle", color = "on_surface_variant" },
}
shared.BAR_ORDER = { "blocked", "working", "done", "idle" }

-- Cycled by a hash of the workspace label so each project gets a stable color
-- without any configuration. Kept off red/green (reserved for blocked/done).
local WORKSPACE_PALETTE = { "#7fb0e0", "#c29bea", "#e0a25f", "#64b5c9", "#d68fb0", "#a8b876" }

function shared.workspaceColor(label)
  if not label or label == "" then
    return "on_surface_variant"
  end
  local sum = 0
  for i = 1, #label do
    sum += string.byte(label, i)
  end
  return WORKSPACE_PALETTE[(sum % #WORKSPACE_PALETTE) + 1]
end

-- Applies alpha (0-1) to a theme token ("primary" -> "primary/0.15") or a
-- "#rrggbb" hex color ("#4caf50" -> "#4caf5026").
function shared.tint(color, alpha)
  if color:sub(1, 1) == "#" then
    return color .. string.format("%02x", math.floor(alpha * 255 + 0.5))
  end
  return color .. "/" .. tostring(alpha)
end

function shared.workspaceChipFill(label)
  return shared.tint(shared.workspaceColor(label), 0.15)
end

local function info(status)
  return STATUS[status] or STATUS.unknown
end

function shared.glyph(status)
  return info(status).glyph
end

function shared.color(status)
  return info(status).color
end

-- unknown is folded into idle: both mean "not doing anything we can see".
function shared.counts(agents)
  local counts = { blocked = 0, working = 0, done = 0, idle = 0 }
  for _, a in ipairs(agents) do
    local key = counts[a.status] ~= nil and a.status or "idle"
    counts[key] += 1
  end
  return counts
end

function shared.summaryColor(counts)
  if counts.blocked > 0 then
    return "error"
  elseif counts.working > 0 then
    return "primary"
  elseif counts.done > 0 then
    return STATUS.done.color
  end
  return "on_surface_variant"
end

function shared.sort(agents)
  table.sort(agents, function(a, b)
    local ra, rb = info(a.status).rank, info(b.status).rank
    if ra ~= rb then
      return ra < rb
    end
    if a.changed_at ~= b.changed_at then
      return a.changed_at > b.changed_at
    end
    return a.pane_id < b.pane_id
  end)
  return agents
end

function shared.ago(unixSeconds)
  local d = math.max(0, os.time() - (unixSeconds or 0))
  if d < 60 then
    return noctalia.tr("time.seconds", { n = d })
  elseif d < 3600 then
    return noctalia.tr("time.minutes", { n = d // 60 })
  elseif d < 86400 then
    return noctalia.tr("time.hours", { n = d // 3600 })
  end
  return noctalia.tr("time.days", { n = d // 86400 })
end

return shared
