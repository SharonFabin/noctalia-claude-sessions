#!/bin/bash
# Focus a tmux session+window in Hyprland.
# If the session is detached, switches the current tmux client to it.
# Usage: focus-session.sh <tmux_session> <tmux_window>
TMUX_SESSION="$1"
TMUX_WINDOW="$2"

[ -z "$TMUX_SESSION" ] && exit 1

# Find any tmux client (prefer one attached to this session, else use any client)
CLIENT_PID=$(tmux list-clients -t "$TMUX_SESSION" -F "#{client_pid}" 2>/dev/null | head -1)

if [ -z "$CLIENT_PID" ]; then
  # Session is detached — switch the first available tmux client to this session
  CLIENT_PID=$(tmux list-clients -F "#{client_pid}" 2>/dev/null | head -1)
  [ -z "$CLIENT_PID" ] && exit 1
  tmux switch-client -t "$TMUX_SESSION" 2>/dev/null
fi

# Select the target window
[ -n "$TMUX_WINDOW" ] && tmux select-window -t "$TMUX_SESSION:$TMUX_WINDOW" 2>/dev/null

# Walk up the process tree to find the terminal PID that Hyprland knows about
PID="$CLIENT_PID"
CLIENTS_JSON=$(hyprctl clients -j)
for _ in 1 2 3 4 5; do
  PARENT=$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')
  [ -z "$PARENT" ] || [ "$PARENT" = "1" ] && break
  ADDR=$(echo "$CLIENTS_JSON" | jq -r --arg p "$PARENT" '.[] | select(.pid == ($p | tonumber)) | .address // empty' | head -1)
  if [ -n "$ADDR" ]; then
    hyprctl dispatch focuswindow "pid:$PARENT"
    exit 0
  fi
  PID="$PARENT"
done

exit 1
