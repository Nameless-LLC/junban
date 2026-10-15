#!/usr/bin/env bash
# Status-right counter: ✋ waiting / ✓ done / ● running across all sessions.
# Also the heartbeat that runs heal.py (stale-state repair) every status-interval.
. "$(dirname "$0")/lib.sh"
if command -v python3 >/dev/null 2>&1; then
  python3 "$JUNBAN_SCRIPTS/heal.py" >/dev/null 2>&1
fi
cw=$(opt @junban-color-waiting "#e06c75")
cd_=$(opt @junban-color-done "#98c379")
cr=$(opt @junban-color-running "#e5c07b")
bg=$(opt @junban-color-bg "#1e2127")
tmux list-windows -a -F '#{@junban}' 2>/dev/null | awk -v cw="$cw" -v cd="$cd_" -v cr="$cr" -v bg="$bg" '
  $0 == "waiting" { w++ } $0 == "done" { d++ } $0 == "running" { r++ }
  END {
    if (w) printf "#[fg=%s,bg=%s,bold] ✋%d #[default] ", bg, cw, w
    if (d) printf "#[fg=%s]✓%d ", cd, d
    if (r) printf "#[fg=%s]●%d ", cr, r
  }'
