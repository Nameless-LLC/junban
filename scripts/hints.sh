#!/usr/bin/env bash
# The guide line. Tells you the one key that matters right now:
#   someone is waiting → a red banner pointing at the jump key
#   someone finished   → a green banner
#   two agents share a git tree → which windows, and how to split them
#   otherwise          → the five keys worth remembering, plus a quiet count of
#                        agents parked for a day

# The right edge rotates one tip per minute (@junban-tips off to hide).
#
# $1 is the client width (#{client_width}). With it the line is fitted to the
# terminal: the tip goes first, then the recap is cut with "…", so the banner
# itself always shows. Without it nothing is fitted (tmux clips at the edge).
. "$(dirname "$0")/lib.sh"
load_i18n

cols=${1:-0}
case "$cols" in '' | *[!0-9]*) cols=0 ;; esac
# Character counts need a UTF-8 locale; tmux jobs often run under C.
case "$(locale charmap 2>/dev/null)" in
  UTF-8 | utf-8) ;;
  *) for l in C.UTF-8 en_US.UTF-8; do LC_ALL=$l; [ "$(locale charmap 2>/dev/null)" = UTF-8 ] && break; done 2>/dev/null ;;
esac

# Display width of plain text, erring wide: ASCII is 1, a few symbols this line
# uses are 1, anything else (CJK, emoji) counts as 2.
dw() {
  local s=${1//[✓·→…⚠]/.} a
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

w=0; d=0; z=0; shared=""
# The window Alt+a would open (oldest ✋, else oldest ✓), so the banner can say
# what it wants before you go there.
next_rank=9; next_ts=0; next_line=""
# Empty fields print as "-": read collapses runs of tab separators, which would
# shift the fields. (tmux escapes control characters, so no \037 trick.)
while IFS=$'\t' read -r s sh st name ts recap; do
  case "$s" in waiting) w=$((w + 1)); rank=1 ;; done) d=$((d + 1)); rank=2 ;; *) rank=9 ;; esac
  if [ "$rank" -lt 9 ] && { [ "$rank" -lt "$next_rank" ] ||
       { [ "$rank" -eq "$next_rank" ] && [ "${ts:-0}" -lt "$next_ts" ]; }; }; then
    next_rank=$rank; next_ts=${ts:-0}
    next_line="$name"; [ "$recap" != - ] && next_line="$name: $recap"
  fi
  [ "$sh" != - ] && shared="$shared${shared:+ · }$name"
  [ "$st" != - ] && z=$((z + 1))
done < <(tmux list-windows -a -F '#{?@junban,#{@junban},-}	#{?@junban_shared,#{@junban_shared},-}	#{?@junban_stale,#{@junban_stale},-}	#{=12:window_name}	#{?@junban_ts,#{@junban_ts},0}	#{?@junban_recap,#{@junban_recap},-}' 2>/dev/null)

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
if [ "$(opt @junban-tips on)" = on ]; then
  tip=${TIPS[$(($(date +%s) / 60 % ${#TIPS[@]}))]}
  # Tips are written with the default keys; show the user's actual ones.
  tip=${tip//Alt+a/$kj}; tip=${tip//Alt+f/$kf}; tip=${tip//Alt+g/$kg}
  right="#[align=right]#[fg=$cdim]💡 $tip "
fi

# banner COLOR TEXT — the ✋/✓ banner, then as much of the recap as fits.
# The tip only stays when the whole recap fits beside it.
banner() {
  local head="#[fg=$bg,bg=$1,bold] $2 #[default] " room
  # A recap can be a whole sentence; never let it stop mid-word without a mark.
  next_line=$(fit "$next_line" 96)
  if [ "$cols" -gt 0 ]; then
    room=$((cols - $(dws "$head")))
    if [ -n "$right" ] && [ $(($(dw "$next_line") + 2 + $(dws "$right"))) -le "$room" ]; then :
    else right=""; next_line=$(fit "$next_line" "$room"); fi
  fi
  left="$head#[fg=$1]$next_line"
}

# shellcheck disable=SC2059
if [ "$w" -gt 0 ]; then
  banner "$cw" "✋ $(printf "$T_WAITING" "$w") → $(printf "$T_WAITING_GO" "$kj")"
elif [ "$d" -gt 0 ]; then
  banner "$cd_" "✓ $(printf "$T_DONE" "$d") → $(printf "$T_DONE_GO" "$kj")"
elif [ -n "$shared" ]; then
  left="#[fg=$bg,bg=$ck,bold] ⚠ $(printf "$T_SHARED" "$shared") #[default]#[fg=$cm] $T_SHARED_GO"
else
  left=""
  for pair in "$kj|$T_NEXT" "$kf|$T_LIST" "$kn|$T_NEW" "$kg|$T_SHELL" "$kh|$T_HELP"; do
    left="$left#[fg=$ck]${pair%%|*}#[fg=$cm] ${pair#*|}  "
  done
  # How long agents sat on you today. Seeing the number is most of the fix.
  if [ "$(opt @junban-meter on)" = on ]; then
    IFS=$'\t' read -r mt mm mc mtr < <(bash "$JUNBAN_SCRIPTS/stats.sh" --line 2>/dev/null)
    if [ "${mc:-0}" -gt 0 ]; then
      left="$left#[fg=$cm]⏱ $(printf "$T_METER" "$(fmt_dur "$mt")" "$(fmt_dur "$mm")")"
      # Quicker than your own recent days is the one comparison worth making.
      case "$mtr" in
        -*) left="$left · #[fg=$cd_]$(printf "$T_TREND" "$mtr")" ;;
        +*) left="$left · #[fg=$cm]$(printf "$T_TREND" "$mtr")" ;;
      esac
      left="$left  "
    fi
  fi
  # Parked agents can sit for days, so this rides along instead of taking over.
  [ "$z" -gt 0 ] && left="$left#[fg=$cdim]z $(printf "$T_STALE" "$z" "$(opt @junban-stale-hours 24)") → $(printf "$T_STALE_GO" "$kf")"
fi

# Whatever the left says matters more than a tip: drop the tip if they collide.
[ "$cols" -gt 0 ] && [ -n "$right" ] && [ $(($(dws "$left") + 2 + $(dws "$right"))) -gt "$cols" ] && right=""
printf '%s%s' "$left" "$right"
