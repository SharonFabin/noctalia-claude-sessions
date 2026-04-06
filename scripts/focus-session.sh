#!/bin/bash
# Focus a Claude Code session in Hyprland.
# For tmux sessions: switches client and focuses the terminal.
# For non-tmux sessions: walks up from the Claude PID to find the terminal.
# Usage: focus-session.sh <claude_pid> [tmux_session] [tmux_window]
CLAUDE_PID="$1"
TMUX_SESSION="$2"
TMUX_WINDOW="$3"

[ -z "$CLAUDE_PID" ] && exit 1

# Find terminal window by walking up the process tree from a starting PID
find_and_focus_terminal() {
  local PID="$1"
  local CLIENTS_JSON
  CLIENTS_JSON=$(hyprctl clients -j)
  for _ in 1 2 3 4 5 6 7 8; do
    local PARENT
    PARENT=$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')
    [ -z "$PARENT" ] || [ "$PARENT" = "1" ] && return 1
    local ADDR
    ADDR=$(echo "$CLIENTS_JSON" | jq -r --arg p "$PARENT" '.[] | select(.pid == ($p | tonumber)) | .address // empty' | head -1)
    if [ -n "$ADDR" ]; then
      hyprctl dispatch focuswindow "pid:$PARENT"
      return 0
    fi
    PID="$PARENT"
  done
  return 1
}

if [ -n "$TMUX_SESSION" ]; then
  # Tmux path: switch client to session, select window, then focus terminal
  CLIENT_PID=$(tmux list-clients -t "$TMUX_SESSION" -F "#{client_pid}" 2>/dev/null | head -1)

  if [ -z "$CLIENT_PID" ]; then
    CLIENT_PID=$(tmux list-clients -F "#{client_pid}" 2>/dev/null | head -1)
    [ -z "$CLIENT_PID" ] && exit 1
    tmux switch-client -t "$TMUX_SESSION" 2>/dev/null
  fi

  [ -n "$TMUX_WINDOW" ] && tmux select-window -t "$TMUX_SESSION:$TMUX_WINDOW" 2>/dev/null

  find_and_focus_terminal "$CLIENT_PID"
else
  # Non-tmux: walk up from the Claude process PID
  find_and_focus_terminal "$CLAUDE_PID"
fi
