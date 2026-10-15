#!/usr/bin/env bash
# Status-right counter: ✋ waiting / ✓ done / ● running across all sessions.
# Also the heartbeat that runs heal.py (stale-state repair) and scan.py
# (shared trees, parked agents) every status-interval.
. "$(dirname "$0")/lib.sh"
if command -v python3 >/dev/null 2>&1; then
  python3 "$JUNBAN_SCRIPTS/heal.py" >/dev/null 2>&1
  python3 "$JUNBAN_SCRIPTS/scan.py" >/dev/null 2>&1
fi
cw=$(opt @junban-color-waiting "#e06c75")
cd_=$(opt @junban-color-done "#98c379")
cr=$(opt @junban-color-running "#e5c07b")
bg=$(opt @junban-color-bg "#1e2127")
# @junban-mascot on: a small face that reacts to the whole board — calls out
# when someone waits, cheers when work is done, looks around while agents run,
# dozes when there is nothing to do. Two frames, switching each refresh.
mascot=$(opt @junban-mascot off)
cdim=$(opt @junban-color-dim "#5c6370")
tmux list-windows -a -F '#{@junban}' 2>/dev/null | awk -v cw="$cw" -v cd="$cd_" -v cr="$cr" -v bg="$bg" \
    -v m="$mascot" -v dim="$cdim" -v f="$(( $(date +%s) / 5 % 2 ))" '
  $0 == "waiting" { w++ } $0 == "done" { d++ } $0 == "running" { r++ }
  END {
    if (m == "on") {
      if (w)      printf "#[fg=%s,bold]%s#[default] ", cw, (f ? "(O_O)/" : "(O_O)|")
      else if (d) printf "#[fg=%s,bold]%s#[default] ", cd, (f ? "(^_^)b" : "(^o^)b")
      else if (r) printf "#[fg=%s]%s ", cr, (f ? "(._. )" : "( ._.)")
      else        printf "#[fg=%s]%s ", dim, (f ? "(-_-)zZ" : "(-_-)z ")
    }
    if (w) printf "#[fg=%s,bg=%s,bold] ✋%d #[default] ", bg, cw, w
    if (d) printf "#[fg=%s]✓%d ", cd, d
    if (r) printf "#[fg=%s]●%d ", cr, r
  }'
