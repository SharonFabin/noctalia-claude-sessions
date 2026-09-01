#!/bin/bash
# Focus an AI agent session.
# For herdr sessions: focuses the terminal window, workspace, and tab containing the pane.
# For tmux sessions: switches client and focuses the terminal.
# For non-tmux sessions: walks up from the Claude PID to find the terminal.
# Usage:
#   focus-session.sh --herdr <workspace_id> <tab_id> <pane_id>
#   focus-session.sh <agent_pid> [tmux_session] [tmux_window]
CLAUDE_PID="$1"
TMUX_SESSION="$2"
TMUX_WINDOW="$3"

get_parent_pid() {
  local PID="$1"
  local STAT
  local REST

  if IFS= read -r STAT < "/proc/$PID/stat" 2>/dev/null; then
    REST="${STAT##*) }"
    set -- $REST
    [ -n "${2:-}" ] && printf '%s\n' "$2"
    return 0
  fi

  ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' '
}

# Find a Hyprland window by walking up the process tree from a starting PID,
# switch to its Hyprland workspace, then focus the exact window.
find_and_focus_terminal() {
  local PID="$1"
  local CLIENTS_JSON
  local CLIENTS_TSV
  local CLIENT_PID
  local CLIENT_ADDR
  local CLIENT_WORKSPACE_ID
  local ADDR
  local WORKSPACE_ID
  local -A CLIENT_ADDR_BY_PID=()
  local -A CLIENT_WORKSPACE_BY_PID=()

  command -v hyprctl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  CLIENTS_JSON=$(hyprctl clients -j 2>/dev/null) || return 1
  CLIENTS_TSV=$(echo "$CLIENTS_JSON" | jq -r '.[] | select(.pid != null and .address != null) | [.pid, .address, (.workspace.id // "")] | @tsv' 2>/dev/null) || return 1
  [ -n "$CLIENTS_TSV" ] || return 1

  while IFS=$'\t' read -r CLIENT_PID CLIENT_ADDR CLIENT_WORKSPACE_ID; do
    [ -n "$CLIENT_PID" ] || continue
    CLIENT_ADDR_BY_PID["$CLIENT_PID"]="$CLIENT_ADDR"
    CLIENT_WORKSPACE_BY_PID["$CLIENT_PID"]="$CLIENT_WORKSPACE_ID"
  done <<< "$CLIENTS_TSV"

  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    [ -n "$PID" ] || return 1

    ADDR="${CLIENT_ADDR_BY_PID[$PID]:-}"
    if [ -n "$ADDR" ]; then
      WORKSPACE_ID="${CLIENT_WORKSPACE_BY_PID[$PID]:-}"
      [ -n "$WORKSPACE_ID" ] && hyprctl dispatch workspace "$WORKSPACE_ID" >/dev/null 2>&1
      hyprctl dispatch focuswindow "address:$ADDR" >/dev/null 2>&1 \
        || hyprctl dispatch focuswindow "pid:$PID" >/dev/null 2>&1
      return 0
    fi

    local PARENT
    PARENT=$(get_parent_pid "$PID")
    [ -z "$PARENT" ] || [ "$PARENT" = "1" ] && return 1
    PID="$PARENT"
  done

  return 1
}

focus_herdr_terminal_for_pane() {
  local PANE_ID="$1"
  local PROCESS_JSON
  local PROCESS_PIDS
  local SHELL_PID
  local FOREGROUND_PID

  [ -n "$PANE_ID" ] || return 1
  command -v herdr >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  PROCESS_JSON=$(herdr pane process-info --pane "$PANE_ID" 2>/dev/null) || return 1
  PROCESS_PIDS=$(echo "$PROCESS_JSON" | jq -r '[.result.process_info.shell_pid // "", .result.process_info.foreground_processes[0].pid // ""] | join("|")' 2>/dev/null) || return 1
  SHELL_PID="${PROCESS_PIDS%%|*}"
  FOREGROUND_PID="${PROCESS_PIDS#*|}"
  [ "$FOREGROUND_PID" = "$PROCESS_PIDS" ] && FOREGROUND_PID=""

  if [ -n "$SHELL_PID" ] && find_and_focus_terminal "$SHELL_PID"; then
    return 0
  fi

  [ -n "$FOREGROUND_PID" ] && find_and_focus_terminal "$FOREGROUND_PID"
}

if [ "$1" = "--herdr" ]; then
  WORKSPACE_ID="$2"
  TAB_ID="$3"
  PANE_ID="$4"

  command -v herdr >/dev/null 2>&1 || exit 1
  [ -n "$PANE_ID" ] && focus_herdr_terminal_for_pane "$PANE_ID"
  [ -n "$WORKSPACE_ID" ] && herdr workspace focus "$WORKSPACE_ID" >/dev/null 2>&1
  [ -n "$TAB_ID" ] && herdr tab focus "$TAB_ID" >/dev/null 2>&1
  exit 0
fi

[ -z "$CLAUDE_PID" ] && exit 1

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
