#!/usr/bin/env bash
# The guide line. Tells you the one key that matters right now:
#   someone is waiting → a red banner pointing at the jump key
#   someone finished   → a green banner
#   otherwise          → the five keys worth remembering
# The right edge rotates one tip per minute (@junban-tips off to hide).
. "$(dirname "$0")/lib.sh"
load_i18n

w=0; d=0
while read -r s; do
  case "$s" in waiting) w=$((w + 1)) ;; done) d=$((d + 1)) ;; esac
done < <(tmux list-windows -a -F '#{@junban}' 2>/dev/null)

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
  left="#[fg=$bg,bg=$cw,bold] ✋ $(printf "$T_WAITING" "$w") → $(printf "$T_WAITING_GO" "$kj") #[default]"
elif [ "$d" -gt 0 ]; then
  left="#[fg=$bg,bg=$cd_,bold] ✓ $(printf "$T_DONE" "$d") → $(printf "$T_DONE_GO" "$kj") #[default]"
else
  left=""
  for pair in "$kj|$T_NEXT" "$kf|$T_LIST" "$kn|$T_NEW" "$kg|$T_SHELL" "$kh|$T_HELP"; do
    left="$left#[fg=$ck]${pair%%|*}#[fg=$cm] ${pair#*|}  "
  done
fi

right=""
if [ "$(opt @junban-tips on)" = on ]; then
  tip=${TIPS[$(($(date +%s) / 60 % ${#TIPS[@]}))]}
  # Tips are written with the default keys; show the user's actual ones.
  tip=${tip//Alt+a/$kj}; tip=${tip//Alt+f/$kf}; tip=${tip//Alt+g/$kg}
  right="#[align=right]#[fg=$cdim]💡 $tip "
fi
printf '%s%s' "$left" "$right"
