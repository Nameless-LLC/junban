#!/usr/bin/env bash
# demo.sh [en|ja] — start a throwaway tmux server that looks like a busy morning:
# six agents, two waiting on you, one done. Used for the README images, and handy
# for recording your own GIF:  bash tools/demo.sh && tmux -L junban-demo attach
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LANG_=${1:-en}
T="tmux -L junban-demo"
$T kill-server 2>/dev/null || true
CONF=$(mktemp)
cat > "$CONF" <<CONF
set -g base-index 1
set -g default-terminal tmux-256color
set -g @junban-lang $LANG_
run-shell "$ROOT/junban.tmux"
CONF
SCREENS="$ROOT/tools/screens/$LANG_"
mapfile -t ROWS < "$SCREENS/windows.tsv"
first=1
for row in "${ROWS[@]}"; do
  IFS=$'\t' read -r name state screen <<<"$row"
  cmd="clear; cat '$SCREENS/$screen'; sleep 86400"
  if [ $first = 1 ]; then
    $T -f "$CONF" new -d -s work -n "$name" -x 150 -y 34 "$cmd"; first=0
  else
    $T new-window -d -t work -n "$name" "$cmd"
  fi
  idx=$($T list-windows -t work -F '#{window_index}' | tail -1)
  $T set -w -t "work:$idx" automatic-rename off
  [ "$state" != "-" ] && $T set -w -t "work:$idx" @junban "$state"
  $T set -w -t "work:$idx" @junban_ts "$(( $(date +%s) - idx * 60 ))"
done
# keep the screenshot free of the real hostname
$T set -g status-right "$($T show -gv status-right | sed 's/#h/macbook/')"
$T select-window -t work:1
echo "demo ready:  tmux -L junban-demo attach -t work"
