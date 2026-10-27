#!/usr/bin/env bash
# shellcheck disable=SC2059  # i18n strings are printf formats by design
# restore.sh auto|menu|open N..|all — reopen Claude Code windows after a restart.
#
# auto (junban.tmux, on load): when the tmux server is new, reopen the windows
# worth reopening (restore.py picks them) and say how many; the rest wait in
# Alt+, → Restore windows. menu: that list. open: reopen the chosen ones.
. "$(dirname "$0")/lib.sh"
load_i18n
command -v python3 >/dev/null 2>&1 || exit 0
py() { python3 "$JUNBAN_SCRIPTS/restore.py" "$@"; }
# Reopen with what Alt+n starts (its flags too) when that is Claude Code.
agent=$(opt @junban-agent-cmd claude)
case "${agent%% *}" in claude) ;; *) agent=claude ;; esac
esc() { printf '%s' "${1//#/##}"; }
# say MS OPENED LEFT — how many came back, and where the rest are; no zero counts.
say() {
  if [ "$2" -eq 0 ] && [ "$3" -eq 0 ]; then m=$T_RESTORE_NONE
  elif [ "$2" -eq 0 ]; then m=$(printf "$T_RESTORE_LEFT" "$3")
  elif [ "$3" -gt 0 ]; then m=$(printf "$T_RESTORED" "$2" "$3")
  else m=$(printf "$T_RESTORED_ALL" "$2"); fi
  tmux display -d "$1" "$m" 2>/dev/null
}

case "${1:-}" in
  auto)
    # Off: still drop the old list, or it would block saving the new one.
    [ "$(opt @junban-restore on)" = on ] || { py rotate >/dev/null; exit 0; }
    [ "$(py rotate)" = rotated ] || exit 0
    IFS=$'\t' read -r n rest <<<"$(py open "$agent" auto)"
    [ "${n:-0}" -gt 0 ] || [ "${rest:-0}" -gt 0 ] || exit 0
    # Run while the config loads: the first client may not be attached yet.
    for _ in $(seq 100); do [ -n "$(tmux list-clients 2>/dev/null)" ] && break; sleep 0.1; done
    say 8000 "${n:-0}" "${rest:-0}"
    ;;
  open)
    shift; IFS=$'\t' read -r n rest <<<"$(py open "$agent" "$@")"
    say 3000 "${n:-0}" "${rest:-0}"
    ;;
  menu)
    # A menu taller than the terminal is not drawn at all: "Restore all" goes
    # first, and the list stops where the screen does.
    h=$(tmux display -p '#{client_height}' 2>/dev/null); case "$h" in '' | *[!0-9]*) h=24 ;; esac
    room=$((h - 6)); [ "$room" -lt 1 ] && room=1
    rows=() k=1 total=0
    while IFS=$'\t' read -r i _ sess name _ _; do
      [ -n "$i" ] || continue
      total=$((total + 1))
      [ "$total" -le "$room" ] || continue
      rows+=("$(esc "$sess: $name")" "$([ $k -le 9 ] && echo $k)" "run -b \"bash $JUNBAN_SCRIPTS/restore.sh open $i\"")
      k=$((k + 1))
    done < <(py list)
    if [ "$total" -eq 0 ]; then
      tmux display "$T_RESTORE_NONE" 2>/dev/null; exit 0
    fi
    items=("$(esc "$SET_RESTORE_ALL")" a "run -b \"bash $JUNBAN_SCRIPTS/restore.sh open all\"" "" "${rows[@]}")
    # A leading "-" makes the row a note, not a choice.
    [ "$total" -gt "$room" ] && items+=("-$(esc "$(printf "$SET_RESTORE_MORE" $((total - room)))")" "" "")
    if [ -n "${JUNBAN_DRY_RUN:-}" ]; then printf '%s\n' "${items[@]}"; exit 0; fi
    tmux display-menu -T "#[align=centre] $(esc "$SET_RESTORE") " -x C -y C "${items[@]}"
    ;;
esac
exit 0
