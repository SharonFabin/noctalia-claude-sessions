# AI Agents

A Noctalia v5 plugin that lists every [herdr](https://herdr.dev/) agent pane (Claude, Codex, or anything else herdr detects), with its status and how long ago that status last changed. Click an agent to jump to it.

## Features

- **Bar widget**: a sparkles glyph tinted by the most urgent status, plus per-status counts (needs input, working, done, idle).
- **Panel**: agents sorted by urgency, then most recently changed. Type to filter by name, agent, status, workspace, tab, pane id or cwd. Use Up/Down or Ctrl+N/P and Enter, or click.
- **Focus**: runs `herdr workspace focus`, `herdr tab focus` and `herdr agent focus` (attached clients only follow workspace/tab focus), then raises the Hyprland window of the terminal running herdr (which also switches Hyprland workspace).

## Requirements

- `herdr` with a running server whose protocol matches the CLI (`herdr status server`)
- Hyprland (`hyprctl`)
- `jq`

## Installation

```sh
git clone https://github.com/SharonFabin/noctalia-claude-sessions.git \
  ~/.local/share/noctalia/plugins/claude-sessions
noctalia msg plugins enable SharonFabin/claude-sessions
```

Add the widget to a bar in `~/.config/noctalia/config.toml`:

```toml
[bar.default]
end = [ "ai_agents", "tray", ... ]

[widget.ai_agents]
type = "SharonFabin/claude-sessions:bar"
```

## Keybind

```lua
-- Hyprland
bind = SUPER, I, exec, noctalia msg panel-toggle SharonFabin/claude-sessions:panel
```

## Settings

| Key | Default | |
| --- | --- | --- |
| `poll_interval_ms` | `2000` | How often `herdr api snapshot` is read |
| `socket_path` | empty | herdr socket for a non-default server (`HERDR_SOCKET_PATH`) |

## How it works

The service polls `herdr api snapshot` and publishes one row per agent pane through `noctalia.state`, and the bar and panel render from that. herdr does not report timestamps, so "last update" is the time the service first saw an agent's current `(agent_status, state_change_seq)`. That is persisted in the plugin data dir, so reloading the shell does not reset it.

IPC on the service entry:

```sh
noctalia msg plugin SharonFabin/claude-sessions:service all focus <pane_id>
noctalia msg plugin SharonFabin/claude-sessions:service all refresh
```
