# noctalia-claude-sessions

- `herdr agent focus` only moves server-side focus; attached TUI clients follow `workspace focus` + `tab focus`, so always focus workspace, then tab, then the pane, and verify focus changes on a real attached client, not a headless test server.
- Never discard `hyprctl dispatch` output: Lua-config Hyprland rejects classic syntax (`focuswindow address:X`) with a printed error, so check for `ok` and test window focus from a different Hyprland workspace, not on the already-focused window.
- Locate the Hyprland window from the herdr client process, not the pane's shell: the server can be reparented to systemd (e.g. after live handoff).
- A pid does not identify a window: ghostty owns every window from one process, so disambiguate by herdr's window title ("{hostname}: {workspace}") and test with a second window of the same terminal open.
