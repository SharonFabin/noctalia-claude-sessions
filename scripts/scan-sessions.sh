#!/bin/bash
# Outputs a single-line JSON summary of AI agent sessions.
# Prefers herdr panes when herdr is running, then falls back to cctop Claude data.
# Requires: jq
shopt -s nullglob

CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}/noctalia-claude-sessions"
HERDR_ACTIVITY_CACHE="$CACHE_DIR/herdr-activity.json"

empty_summary() {
  echo '{"active":0,"idle":0,"done":0,"waiting":0,"error":0,"total":0,"sessions":[]}'
}

herdr_json="$(herdr pane list 2>/dev/null || true)"
if [ -n "$herdr_json" ] && echo "$herdr_json" | jq -e '.result.panes | map(select((.agent // "") != "")) | length > 0' >/dev/null 2>&1; then
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  previous_activity="{}"
  if [ -r "$HERDR_ACTIVITY_CACHE" ]; then
    previous_activity="$(jq -c 'if type == "object" then . else {} end' "$HERDR_ACTIVITY_CACHE" 2>/dev/null || echo '{}')"
  fi
  workspace_json="$(herdr workspace list 2>/dev/null || true)"
  workspaces="$(echo "$workspace_json" | jq -c '.result.workspaces // []' 2>/dev/null || echo '[]')"
  tabs="[]"
  workspace_ids="$(echo "$herdr_json" | jq -r '[.result.panes[].workspace_id // empty] | unique[]' 2>/dev/null || true)"
  for workspace_id in $workspace_ids; do
    tab_json="$(herdr tab list --workspace "$workspace_id" 2>/dev/null || true)"
    [ -n "$tab_json" ] || continue
    tabs="$(printf '%s\n%s\n' "$tabs" "$tab_json" | jq -s -c '.[0] + (.[1].result.tabs // [])' 2>/dev/null || printf '%s' "$tabs")"
  done

  jq_output="$(echo "$herdr_json" | jq -c --argjson tabs "$tabs" --argjson workspaces "$workspaces" --argjson previous "$previous_activity" --arg now "$now" '
    def cache_key:
      ((.agent_session.value // .terminal_id // .pane_id // "") | tostring);
    def update_signature($tabs_by_id):
      ([
        (.agent // ""),
        (.agent_status // ""),
        (.foreground_cwd // .cwd // ""),
        (.title // ""),
        (.display_agent // ""),
        (.workspace_id // ""),
        (.tab_id // ""),
        (.pane_id // ""),
        ($tabs_by_id[.tab_id].label // "")
      ] | @json);

    ($tabs | map({key: .tab_id, value: .}) | from_entries) as $tabs_by_id
    | ($workspaces | map({key: .workspace_id, value: .}) | from_entries) as $workspaces_by_id
    |
    .result.panes
    | map(select((.agent // "") != ""))
    | map(
      . as $pane
      | (cache_key) as $key
      | (update_signature($tabs_by_id)) as $signature
      | {
        source: "herdr",
        agent: ($pane.agent // "agent"),
        status: ($pane.agent_status // "unknown"),
        cwd: ($pane.foreground_cwd // $pane.cwd // ""),
        tool: "",
        id: ((($pane.agent_session.value // $pane.pane_id // "") | tostring)[0:8]),
        name: (
          if ($pane.title // "") != "" then $pane.title
          elif ($pane.display_agent // "") != "" then ($pane.display_agent | sub("^[^:]+: "; ""))
          elif (($tabs_by_id[$pane.tab_id].label // "") != "") then $tabs_by_id[$pane.tab_id].label
          else (($pane.agent // "agent") + " " + ((($pane.agent_session.value // $pane.pane_id // "") | tostring)[0:8]))
          end
        ),
        context: ([
          (if (($tabs_by_id[$pane.tab_id].label // "") != "") then ("tab " + $tabs_by_id[$pane.tab_id].label) else empty end),
          ("pane " + ($pane.pane_id // ""))
        ] | join(" / ")),
        title: ($pane.title // ""),
        display_agent: ($pane.display_agent // ""),
        model: "",
        last_activity: (
          if (($previous[$key].signature // "") == $signature and ($previous[$key].last_activity // "") != "") then
            $previous[$key].last_activity
          else
            $now
          end
        ),
        started_at: "",
        pid: 0,
        tmux_session: "",
        tmux_window: "",
        workspace_name: ($workspaces_by_id[$pane.workspace_id].label // ""),
        workspace_number: ($workspaces_by_id[$pane.workspace_id].number // 0),
        tab_name: ($tabs_by_id[$pane.tab_id].label // ""),
        tab_number: ($tabs_by_id[$pane.tab_id].number // 0),
        workspace_id: ($pane.workspace_id // ""),
        tab_id: ($pane.tab_id // ""),
        pane_id: ($pane.pane_id // ""),
        focused: ($pane.focused // false),
        cache_key: $key,
        update_signature: $signature
      }
    ) as $sessions
    | {
      active: [$sessions[] | select(.status == "working")] | length,
      idle: [$sessions[] | select(.status == "idle" or .status == "unknown")] | length,
      done: [$sessions[] | select(.status == "done")] | length,
      waiting: [$sessions[] | select(.status == "blocked")] | length,
      error: 0,
      total: ($sessions | length),
      sessions: ($sessions | map(del(.cache_key, .update_signature)))
    },
    ($sessions | map({key: .cache_key, value: {signature: .update_signature, last_activity: .last_activity}}) | from_entries)
  ' 2>/dev/null || true)"
  if [ -z "$jq_output" ]; then
    empty_summary
    exit 0
  fi
  IFS= read -r summary_json <<< "$jq_output"
  new_activity="$(printf '%s\n' "$jq_output" | sed -n '2p')"
  if [ -n "$new_activity" ] && [ "$new_activity" != "$previous_activity" ]; then
    mkdir -p "$CACHE_DIR" 2>/dev/null || true
    printf '%s\n' "$new_activity" > "$HERDR_ACTIVITY_CACHE.$$" 2>/dev/null \
      && mv "$HERDR_ACTIVITY_CACHE.$$" "$HERDR_ACTIVITY_CACHE" 2>/dev/null || true
  fi
  printf '%s\n' "$summary_json"
  exit 0
fi

files=()
for f in ~/.cctop/*.json; do
  case "$f" in *.poller.json) continue ;; esac
  files+=("$f")
done

if [ ${#files[@]} -eq 0 ]; then
  empty_summary
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
    done: [.[] | select(.status | test("^done$"))] | length,
    waiting: [.[] | select(.status | test("^(awaiting_|idle:needs_input)"))] | length,
    error: [.[] | select(.status | test("^error:"))] | length,
    total: length,
    sessions: [.[] | {
      source: "cctop",
      agent: "claude",
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
      tmux_window: (.tmux_window // ""),
      workspace_name: "",
      workspace_number: 0,
      tab_name: "",
      tab_number: 0,
      workspace_id: "",
      tab_id: "",
      pane_id: "",
      focused: false
    }]
  }
' 2>/dev/null || empty_summary
