#!/bin/bash
# Reads cctop session JSON files and outputs a single-line JSON summary.
# Requires: jq
shopt -s nullglob

files=()
for f in ~/.cctop/*.json; do
  case "$f" in *.poller.json) continue ;; esac
  files+=("$f")
done

if [ ${#files[@]} -eq 0 ]; then
  echo '{"active":0,"idle":0,"waiting":0,"error":0,"total":0,"sessions":[]}'
  exit 0
fi

# Merge hook data with poller names (single jq per session)
merged='['
first=true
for f in "${files[@]}"; do
  poller="${f%.json}.poller.json"
  $first || merged+=','
  first=false
  if [ -f "$poller" ]; then
    merged+=$(jq -c --slurpfile p "$poller" '. + {session_name: (($p[0].custom_title // $p[0].slug // null) // .session_id[0:8])}' "$f" 2>/dev/null)
  else
    merged+=$(jq -c '. + {session_name: .session_id[0:8]}' "$f" 2>/dev/null)
  fi
done
merged+=']'

echo "$merged" | jq -c '
  map(select(.status != null and .status != "")) |
  {
    active: [.[] | select(.status | test("^(thinking|tool:|started)"))] | length,
    idle: [.[] | select(.status | test("^(idle($|:awaiting_plan$)|resumed)"))] | length,
    waiting: [.[] | select(.status | test("^(awaiting_|idle:needs_input)"))] | length,
    error: [.[] | select(.status | test("^error:"))] | length,
    total: length,
    sessions: [.[] | {
      status: .status,
      cwd: (.cwd // ""),
      tool: (.current_tool // ""),
      id: (.session_id // "")[0:8],
      name: .session_name,
      context: (.status_context // ""),
      model: (.model // ""),
      last_activity: (.last_activity // ""),
      started_at: (.started_at // ""),
      pid: (.pid // 0),
      tmux_session: (.tmux_session // ""),
      tmux_window: (.tmux_window // "")
    }]
  }
' 2>/dev/null || echo '{"active":0,"idle":0,"waiting":0,"error":0,"total":0,"sessions":[]}'
