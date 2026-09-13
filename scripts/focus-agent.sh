#!/usr/bin/env bash
# Focus a herdr agent pane: select it inside herdr, then raise the Hyprland
# window of the terminal running the herdr client that owns it.
# Usage: focus-agent.sh <pane_id>   (honors HERDR_SOCKET_PATH)
set -uo pipefail

pane_id="${1:?usage: focus-agent.sh <pane_id>}"

parent_pid() {
  local stat
  stat=$(<"/proc/$1/stat") 2>/dev/null || return 1
  stat=${stat##*) }
  set -- $stat
  echo "$2"
}

# Focusing a window also switches to its workspace. Lua configs (Hyprland 0.55+)
# only accept Lua dispatch expressions; classic configs only accept the old syntax.
focus_address() {
  local out
  out=$(hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" 2>&1)
  [[ $out == ok ]] && return 0
  out=$(hyprctl dispatch focuswindow "address:$1" 2>&1)
  [[ $out == ok ]] && return 0
  echo "hyprctl could not focus window $1: $out" >&2
  return 1
}

# Walk up from a pid until it is a Hyprland client, then focus that window.
# One terminal process can own several windows (ghostty does), so prefer the one
# herdr titled with its default "{hostname}: {workspace}" window_title.
focus_window_from() {
  local pid=$1 clients=$2 addr host
  host=$(</proc/sys/kernel/hostname)
  for _ in $(seq 32); do
    [[ -n $pid && $pid -gt 1 ]] || return 1
    addr=$(jq -r --argjson pid "$pid" --arg prefix "$host: " '
      [.[] | select(.pid == $pid)] as $w
      | (first($w[] | select(.title | startswith($prefix))) // first($w[]) | .address) // empty
    ' <<<"$clients")
    if [[ -n $addr ]]; then
      focus_address "$addr"
      return
    fi
    pid=$(parent_pid "$pid") || return 1
  done
  return 1
}

herdr_ok() {
  local out
  if ! out=$(herdr "$@" 2>&1) || grep -q '"error"' <<<"$out"; then
    echo "herdr $*: $out" >&2
    return 1
  fi
}

pane=$(herdr pane get "$pane_id" 2>&1)
workspace_id=$(jq -r '.result.pane.workspace_id // empty' <<<"$pane" 2>/dev/null)
tab_id=$(jq -r '.result.pane.tab_id // empty' <<<"$pane" 2>/dev/null)
if [[ -z $workspace_id || -z $tab_id ]]; then
  echo "herdr pane get $pane_id: $pane" >&2
  exit 1
fi

# Attached TUI clients follow workspace/tab focus but not agent focus alone,
# so select the workspace and tab first, then the pane (which also marks it seen).
herdr_ok workspace focus "$workspace_id" || exit 1
herdr_ok tab focus "$tab_id" || exit 1
herdr_ok agent focus "$pane_id" || exit 1

clients=$(hyprctl clients -j) || { echo "hyprctl clients failed" >&2; exit 1; }

# The window belongs to the terminal running an attached herdr *client* (`herdr`,
# `herdr --session x`, `herdr session attach x`). The server is not reliably under
# it (after `herdr server live-handoff` it is parented to systemd), and one-off CLI
# calls like `herdr api snapshot` are not clients.
# ponytail: with several attached clients the first one found wins; correlate by
# client id if herdr ever exposes which client shows which workspace.
for pid in $(pgrep -x herdr); do
  mapfile -d '' -t argv <"/proc/$pid/cmdline" 2>/dev/null || continue
  [[ ${#argv[@]} -eq 1 || ${argv[1]} == -* || "${argv[1]} ${argv[2]:-}" == "session attach" ]] || continue
  focus_window_from "$pid" "$clients" && exit 0
done

echo "no Hyprland window found for herdr pane $pane_id" >&2
exit 1
