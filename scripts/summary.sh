#!/usr/bin/env bash
# Status-right counter: ✋ waiting / ✓ done / ● running across all sessions.
# Also the heartbeat that runs heal.py (stale-state repair) and scan.py
# (parked agents) every status-interval.
. "$(dirname "$0")/lib.sh"
if command -v python3 >/dev/null 2>&1; then
  python3 "$JUNBAN_SCRIPTS/heal.py" >/dev/null 2>&1
  python3 "$JUNBAN_SCRIPTS/scan.py" >/dev/null 2>&1
fi
cw=$(opt @junban-color-waiting "#e06c75")
cd_=$(opt @junban-color-done "#98c379")
cr=$(opt @junban-color-running "#e5c07b")
bg=$(opt @junban-color-bg "#1e2127")
# @junban-mascot (on by default; off hides it): the call board's face, eyes only. It calls when someone
# waits [▮ ▮]!, smiles when work is done [◠ ◠], looks around while agents run,
# blinks now and then while they idle, and dozes when there is nothing [▬ ▬]z.
# Two frames, switching each refresh. ▮ ▬ ◠ are one cell wide in every locale.
mascot=$(opt @junban-mascot on)
cdim=$(opt @junban-color-dim "#5c6370")
cfg=$(opt @junban-color-fg "#abb2bf")
tmux list-windows -a -F '#{@junban}' 2>/dev/null | awk -v cw="$cw" -v cd="$cd_" -v cr="$cr" -v bg="$bg" \
    -v m="$mascot" -v dim="$cdim" -v fg="$cfg" -v t="$(( $(date +%s) / 5 ))" '
  $0 == "waiting" { w++ } $0 == "done" { d++ } $0 == "running" { r++ } $0 == "idle" { i++ }
  END {
    f = t % 2
    if (m == "on") {
      if (w)      printf "#[fg=%s,bold]%s#[default] ", cw, (f ? "[▮ ▮]!" : "[▮ ▮] ")
      else if (d) printf "#[fg=%s,bold]%s#[default] ", cd, "[◠ ◠]"
      else if (r) printf "#[fg=%s]%s ", cr, (f ? "[▮▮ ]" : "[ ▮▮]")
      else if (i) printf "#[fg=%s]%s ", fg, (t % 4 == 3 ? "[▬ ▬]" : "[▮ ▮]")
      else        printf "#[fg=%s]%s ", dim, (f ? "[▬ ▬]z" : "[▬ ▬]Z")
    }
    if (w) printf "#[fg=%s,bg=%s,bold] ✋%d #[default] ", bg, cw, w
    if (d) printf "#[fg=%s]✓%d ", cd, d
    if (r) printf "#[fg=%s]●%d ", cr, r
  }'
