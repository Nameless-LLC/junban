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
# say MS OPENED LEFT — how many came back, and where the rest are when any are left.
say() {
  if [ "$3" -gt 0 ]; then m=$(printf "$T_RESTORED" "$2" "$3"); else m=$(printf "$T_RESTORED_ALL" "$2"); fi
  tmux display -d "$1" "$m" 2>/dev/null
}

case "${1:-}" in
  auto)
    # Off: still drop the old list, or it would block saving the new one.
    [ "$(opt @junban-restore on)" = on ] || { py rotate >/dev/null; exit 0; }
    [ "$(py rotate)" = rotated ] || exit 0
    n=$(py open "$agent" auto); rest=$(py list | grep -c .)
    [ "${n:-0}" -gt 0 ] || [ "${rest:-0}" -gt 0 ] || exit 0
    say 8000 "${n:-0}" "${rest:-0}"
    ;;
  open)
    shift; n=$(py open "$agent" "$@")
    say 3000 "${n:-0}" "$(py list | grep -c .)"
    ;;
  menu)
    items=() k=1
    while IFS=$'\t' read -r i _ sess name _ _; do
      [ -n "$i" ] || continue
      items+=("$(esc "$sess: $name")" "$([ $k -le 9 ] && echo $k)" "run -b \"bash $JUNBAN_SCRIPTS/restore.sh open $i\"")
      k=$((k + 1))
    done < <(py list)
    if [ ${#items[@]} -eq 0 ]; then
      tmux display "$T_RESTORE_NONE" 2>/dev/null; exit 0
    fi
    items+=("" "$(esc "$SET_RESTORE_ALL")" a "run -b \"bash $JUNBAN_SCRIPTS/restore.sh open all\"")
    if [ -n "${JUNBAN_DRY_RUN:-}" ]; then printf '%s\n' "${items[@]}"; exit 0; fi
    tmux display-menu -T "#[align=centre] $(esc "$SET_RESTORE") " -x C -y C "${items[@]}"
    ;;
esac
exit 0
