#!/usr/bin/env bash
# The guide line. Tells you the one key that matters right now:
#   someone is waiting → a red banner pointing at the jump key
#   someone finished   → a green banner
#   two agents share a git tree → which windows, and how to split them
#   otherwise          → the five keys worth remembering, plus a quiet count of
#                        agents parked for a day

# The right edge rotates one tip per minute (@junban-tips off to hide).
. "$(dirname "$0")/lib.sh"
load_i18n

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
done < <(tmux list-windows -a -F '#{?@junban,#{@junban},-}	#{?@junban_shared,#{@junban_shared},-}	#{?@junban_stale,#{@junban_stale},-}	#{=12:window_name}	#{?@junban_ts,#{@junban_ts},0}	#{?@junban_recap,#{=48:@junban_recap},-}' 2>/dev/null)

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

# shellcheck disable=SC2059
if [ "$w" -gt 0 ]; then
  left="#[fg=$bg,bg=$cw,bold] ✋ $(printf "$T_WAITING" "$w") → $(printf "$T_WAITING_GO" "$kj") #[default] #[fg=$cw]$next_line"
elif [ "$d" -gt 0 ]; then
  left="#[fg=$bg,bg=$cd_,bold] ✓ $(printf "$T_DONE" "$d") → $(printf "$T_DONE_GO" "$kj") #[default] #[fg=$cd_]$next_line"
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

right=""
if [ "$(opt @junban-tips on)" = on ]; then
  tip=${TIPS[$(($(date +%s) / 60 % ${#TIPS[@]}))]}
  # Tips are written with the default keys; show the user's actual ones.
  tip=${tip//Alt+a/$kj}; tip=${tip//Alt+f/$kf}; tip=${tip//Alt+g/$kg}
  right="#[align=right]#[fg=$cdim]💡 $tip "
fi
printf '%s%s' "$left" "$right"
