#!/usr/bin/env bash
# shellcheck disable=SC2059  # i18n strings are printf formats by design
# restore.sh auto|menu|open N..|all|back ID — reopen Claude Code windows after a
# restart, or one you closed.
#
# auto (junban.tmux, on load): when the tmux server is new, reopen the windows
# worth reopening (restore.py picks them) and say how many; the rest wait in
# Alt+, → Restore windows. menu: that list. open: reopen the chosen ones. back:
# reopen a window closed by hand and go to it.
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
  back)
    w=$(py back "$agent" "$2")
    [ -n "$w" ] || { tmux display "$T_RESTORE_NONE" 2>/dev/null; exit 0; }
    tmux switch-client -t "$w" 2>/dev/null; tmux select-window -t "$w" 2>/dev/null
    tmux display "$T_REOPENED" 2>/dev/null
    ;;
  menu)
    # A menu taller than the terminal is not drawn at all: "Restore all" goes
    # first, and the list stops where the screen does.
    h=$(tmux display -p '#{client_height}' 2>/dev/null); case "$h" in '' | *[!0-9]*) h=24 ;; esac
    room=$((h - 6)); [ "$room" -lt 1 ] && room=1
    rows=() k=1 total=0
    # Newest closed first: the one you just closed is what you came for.
    while IFS=$'\t' read -r _ _ sess name _ id; do
      [ -n "$id" ] && [ "$k" -le "$room" ] || continue
      rows+=("$(esc "$sess: $name · $SET_RESTORE_CLOSED")" "$k" "run -b \"bash $JUNBAN_SCRIPTS/restore.sh back $id\"")
      k=$((k + 1))
    done < <(py closed)
    room=$((room - k + 1))
    while IFS=$'\t' read -r i _ sess name _ _; do
      [ -n "$i" ] || continue
      total=$((total + 1))
      [ "$total" -le "$room" ] || continue
      rows+=("$(esc "$sess: $name")" "$([ $k -le 9 ] && echo $k)" "run -b \"bash $JUNBAN_SCRIPTS/restore.sh open $i\"")
      k=$((k + 1))
    done < <(py list)
    if [ "$total" -eq 0 ] && [ "$k" -eq 1 ]; then
      tmux display "$T_RESTORE_NONE" 2>/dev/null; exit 0
    fi
    # Restore all is for what a restart left behind, never what you closed.
    items=()
    [ "$total" -gt 0 ] && items=("$(esc "$SET_RESTORE_ALL")" a "run -b \"bash $JUNBAN_SCRIPTS/restore.sh open all\"" "")
    items+=("${rows[@]}")
    # A leading "-" makes the row a note, not a choice.
    [ "$total" -gt "$room" ] && items+=("-$(esc "$(printf "$SET_RESTORE_MORE" $((total - room)))")" "" "")
    if [ -n "${JUNBAN_DRY_RUN:-}" ]; then printf '%s\n' "${items[@]}"; exit 0; fi
    tmux display-menu -T "#[align=centre] $(esc "$SET_RESTORE") " -x C -y C "${items[@]}"
    ;;
esac
exit 0
