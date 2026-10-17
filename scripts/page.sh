#!/usr/bin/env bash
# page.sh — show stdin in a popup until you are done with it.
#
#   help.sh | page.sh
#
# Arrows, PgUp/PgDn, Space and the mouse wheel scroll when the text is taller
# than the popup. Anything else closes it: q, Esc, Enter, Alt+/ again, or a
# click. (tmux keeps clicks outside a popup to itself, so those cannot close it;
# a right-click there opens tmux's own menu, which has Close.)
. "$(dirname "$0")/lib.sh"
load_i18n

lines=()
while IFS= read -r l || [ -n "$l" ]; do lines+=("$l"); done
# Not on a terminal (a test, a pipe): just pass the text on.
if [ ! -t 1 ] || ! exec </dev/tty 2>/dev/null; then
  [ "${#lines[@]}" -gt 0 ] && printf '%s\n' "${lines[@]}"
  exit 0
fi
n=${#lines[@]}
# stty asks the terminal itself; tput can fall back to 24 when terminfo lacks
# tmux's TERM (macOS has no tmux-256color).
rows=$(stty size 2>/dev/null | cut -d' ' -f1)
case "$rows" in '' | *[!0-9]* | 0) rows=$(tput lines 2>/dev/null || echo 24) ;; esac
view=$(( rows > 2 ? rows - 1 : 1 ))   # the last row says how to leave
top=0
max=$(( n > view ? n - view : 0 ))
hint=$PAGE_CLOSE; [ "$max" -gt 0 ] && hint=$PAGE_SCROLL
# Telling Esc from the start of an arrow key needs a short wait; bash 3.2 only
# takes whole seconds.
wait=0.05; [ "${BASH_VERSINFO[0]}" -lt 4 ] && wait=1

draw() {
  local i out=$'\033[H\033[2J'
  for ((i = top; i < top + view && i < n; i++)); do out+="${lines[i]}"$'\033[0m\n'; done
  printf '%s\033[%d;1H\033[2m%s\033[0m' "$out" "$rows" "$hint"
}
scroll() { top=$(( top + $1 )); [ "$top" -lt 0 ] && top=0; [ "$top" -gt "$max" ] && top=$max; }

# Own screen, no cursor, cut long lines instead of wrapping, report clicks and the wheel.
printf '\033[?1049h\033[?25l\033[?7l\033[?1000h\033[?1006h'
trap "printf '\033[?1000l\033[?1006l\033[?7h\033[?25h\033[?1049l'" EXIT
while draw; do
  IFS= read -rsn1 k || break
  if [ "$k" = $'\033' ]; then
    IFS= read -rsn1 -t "$wait" k || break          # Esc on its own
    seq=$k
    if [ "$k" = "[" ] || [ "$k" = O ]; then
      while IFS= read -rsn1 -t "$wait" k; do seq+=$k; case "$k" in [A-Za-z~]) break ;; esac; done
    fi
    case "$seq" in
      '[A' | OA) scroll -1 ;;
      '[B' | OB) scroll 1 ;;
      '[5~') scroll $(( -view + 1 )) ;;
      '[6~') scroll $(( view - 1 )) ;;
      '[H' | OH | '[1~') top=0 ;;
      '[F' | OF | '[4~') top=$max ;;
      '[<64;'*) scroll -3 ;;                         # wheel up
      '[<65;'*) scroll 3 ;;                          # wheel down
      '[<'*m) ;;                                     # a button let go
      *) break ;;                                    # a click, Alt+/, anything else
    esac
  elif [ "$k" = " " ] && [ "$top" -lt "$max" ]; then
    scroll $(( view - 1 ))
  else
    break
  fi
done
exit 0
