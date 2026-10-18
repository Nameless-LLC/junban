#!/usr/bin/env bash
# The guide line. Tells you the one key that matters right now:
#   someone is waiting → a red banner pointing at the jump key
#   someone finished   → a green banner
#   otherwise          → today's wait and a quiet count of agents parked for a
#                        day, and (on its own row) the keys worth remembering

# $1 is the client width (#{client_width}). With it the line is fitted to the
# terminal: today's wait beside a banner goes first, then the recap is cut with
# "…", so the banner itself always shows. Without it nothing is fitted (tmux clips at the edge).
. "$(dirname "$0")/lib.sh"
load_i18n

cols=${1:-0}
row=${2:-}
case "$cols" in '' | *[!0-9]*) cols=0 ;; esac
# Character counts need a UTF-8 locale; tmux jobs often run under C.
case "$(locale charmap 2>/dev/null)" in
  UTF-8 | utf-8) ;;
  *) for l in C.UTF-8 en_US.UTF-8; do LC_ALL=$l; [ "$(locale charmap 2>/dev/null)" = UTF-8 ] && break; done 2>/dev/null ;;
esac

# Display width of plain text, erring wide: ASCII is 1, a few symbols this line
# uses are 1, anything else (CJK, emoji) counts as 2.
dw() {
  local s=${1//[✓·→…]/.} a
  a=${s//[^ -~]/}
  echo $((${#a} + 2 * (${#s} - ${#a})))
}
# Width with tmux #[…] styles removed.
dws() { dw "$(printf '%s' "$1" | sed 's/#\[[^]]*\]//g')"; }
# fit TEXT MAX — TEXT cut to MAX columns, ending in "…" when cut.
fit() {
  local s=$1 max=$2 out="" i ch
  [ "$(dw "$s")" -le "$max" ] && { printf '%s' "$s"; return; }
  [ "$max" -lt 2 ] && return
  for ((i = 0; i < ${#s}; i++)); do
    ch=${s:i:1}
    [ "$(dw "$out$ch")" -gt $((max - 1)) ] && break
    out=$out$ch
  done
  printf '%s…' "${out% }"
}

w=0; d=0; z=0
# The window Alt+a would open (oldest ✋, else oldest ✓), so the banner can say
# what it wants before you go there.
next_rank=9; next_ts=0; next_line=""
# Empty fields print as "-": read collapses runs of tab separators, which would
# shift the fields. (tmux escapes control characters, so no \037 trick.)
while IFS=$'\t' read -r s st name ts recap; do
  case "$s" in waiting) w=$((w + 1)); rank=1 ;; done) d=$((d + 1)); rank=2 ;; *) rank=9 ;; esac
  if [ "$rank" -lt 9 ] && { [ "$rank" -lt "$next_rank" ] ||
       { [ "$rank" -eq "$next_rank" ] && [ "${ts:-0}" -lt "$next_ts" ]; }; }; then
    next_rank=$rank; next_ts=${ts:-0}
    next_line="$name"; [ "$recap" != - ] && next_line="$name: $recap"
  fi
  [ "$st" != - ] && z=$((z + 1))
done < <(tmux list-windows -a -F '#{?@junban,#{@junban},-}	#{?@junban_stale,#{@junban_stale},-}	#{=12:window_name}	#{?@junban_ts,#{@junban_ts},0}	#{?@junban_recap,#{@junban_recap},-}' 2>/dev/null)

bg=$(opt @junban-color-bg "#1e2127")
cw=$(opt @junban-color-waiting "#e06c75")
cd_=$(opt @junban-color-done "#98c379")
ck=$(opt @junban-color-key "#e5c07b")
cm=$(opt @junban-color-muted "#7f848e")
cdim=$(opt @junban-color-dim "#5c6370")

kj=$(key_for jump M-a a)
kf=$(key_for list M-f f)
kn=$(key_for new M-n C)
kg=$(key_for scratch M-g g)
kh=$(key_for help M-/ /)

right=""

# mix COLOR [PCT] — COLOR laid faintly over the line's background, PCT % of it
# (default @junban-tint, 20; 0 turns the tint off). Only #rrggbb colors mix.
mix() {
  local a=${1#\#} b=${bg#\#} p i out=""
  p=${2:-$(opt @junban-tint 20)}
  case "$a$b$p" in *[!0-9a-fA-F]* | '') echo "$bg"; return ;; esac
  if [ ${#a} -ne 6 ] || [ ${#b} -ne 6 ] || [ "$p" -le 0 ]; then echo "$bg"; return; fi
  for i in 0 2 4; do
    out=$out$(printf '%02x' $(( 16#${b:i:2} + (16#${a:i:2} - 16#${b:i:2}) * p / 100 )))
  done
  echo "#$out"
}

# banner COLOR TEXT [PCT] — the ✋/✓ banner, then as much of the recap as fits.
# The whole row takes a faint wash of COLOR, so the state shows at a glance.
banner() {
  local tint head room
  tint=$(mix "$1" "${3:-}")
  head="#[fill=$tint]#[fg=$bg,bg=$1,bold] $2 #[bg=$tint,nobold] "
  # A recap can be a whole sentence; never let it stop mid-word without a mark.
  next_line=$(fit "$next_line" 96)
  if [ "$cols" -gt 0 ]; then
    room=$((cols - $(dws "$head")))
    if [ -n "$right" ] && [ $(($(dw "$next_line") + 2 + $(dws "$right"))) -le "$room" ]; then :
    else right=""; next_line=$(fit "$next_line" "$room"); fi
  fi
  left="$head#[fg=$1]$next_line"
  # Today's wait, if it stays, sits on the same wash.
  [ -n "$right" ] && right="#[bg=$tint]$right"
}

# The calm line: the keys worth remembering, then today's wait and parked agents.
keys=""
# Alt+[ ] (@junban-nav-keys) moves to the window beside; tmux clips the end of the row,
# so it goes right after the two keys that matter most.
nav=""; [ "$(opt @junban-nav-keys on)" = on ] && nav="Alt+[ ]|$HELP_K_PREVNEXT"
for pair in "$kj|$T_NEXT" "$kf|$T_LIST" ${nav:+"$nav"} "$kn|$T_NEW" "$kg|$T_SHELL" "$kh|$T_HELP"; do
  keys="$keys#[fg=$ck]${pair%%|*}#[fg=$cm] ${pair#*|}  "
done
info=""
# How long agents sat on you today. Seeing the number is most of the fix.
if [ "$(opt @junban-meter on)" = on ]; then
  IFS=$'\t' read -r mt mm mc mtr < <(bash "$JUNBAN_SCRIPTS/stats.sh" --line 2>/dev/null)
  if [ "${mc:-0}" -gt 0 ]; then
    # shellcheck disable=SC2059
    info="#[fg=$cm]$(printf "$T_METER" "$(fmt_dur "$mt")" "$(fmt_dur "$mm")")"
    # Quicker than your own recent days is the one comparison worth making.
    # shellcheck disable=SC2059
    case "$mtr" in
      -*) info="$info · #[fg=$cd_]$(printf "$T_TREND" "$mtr")" ;;
      +*) info="$info · #[fg=$cm]$(printf "$T_TREND" "$mtr")" ;;
    esac
    info="$info  "
  fi
fi
# Parked agents can sit for days, so this rides along instead of taking over.
# shellcheck disable=SC2059
[ "$z" -gt 0 ] && info="$info#[fg=$cdim]z $(printf "$T_STALE" "$z" "$(opt @junban-stale-hours 24)") → $(printf "$T_STALE_GO" "$kf")"

# With @junban-guide-lines 3 (the default) there are two guide rows ($2 = 1 or 2):
#   row 1: the banner and its recap, today's wait on the right when it fits;
#          without a banner, today's wait and parked agents
#   row 2: the keys
# With @junban-guide-lines 2 there is one, with no keys on it: the keys and the
# wait together ran past ~110 columns in Japanese and clipped the wait off. The
# keys show there while the prefix is pending instead (junban.tmux).
[ "$row" = 1 ] && right="${info:+#[align=right]$info}"
left=""
# shellcheck disable=SC2059
if [ "$w" -gt 0 ]; then
  # An agent stopped on you is the one thing worth a stronger wash.
  banner "$cw" "✋ $(printf "$T_WAITING" "$w") → $(printf "$T_WAITING_GO" "$kj")" "$(opt @junban-tint-waiting "$([ "$(opt @junban-tint 20)" = 0 ] && echo 0 || echo 35)")"
elif [ "$d" -gt 0 ]; then
  banner "$cd_" "✓ $(printf "$T_DONE" "$d") → $(printf "$T_DONE_GO" "$kj")"
fi
case "$row" in
  1) [ -z "$left" ] && { left=$info; right=""; } ;;
  2) left=$keys; right="" ;;
  *) [ -z "$left" ] && left=$info ;;
esac

# Whatever the left says matters more than what sits right of it.
[ "$cols" -gt 0 ] && [ -n "$right" ] && [ $(($(dws "$left") + 2 + $(dws "$right"))) -gt "$cols" ] && right=""
printf '%s%s' "$left" "$right"
