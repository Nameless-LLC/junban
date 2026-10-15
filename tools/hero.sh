#!/usr/bin/env bash
# hero.sh — regenerate docs/hero-<lang>.svg from a live junban session.
# A second tmux server attaches to the demo, so its pane holds exactly what a
# real terminal would show, status lines and popups included.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LANG_=${1:-en}
D="tmux -L junban-demo"
O="tmux -L junban-outer"
OUT=$(mktemp -d)
trap '$O kill-server 2>/dev/null; $D kill-server 2>/dev/null; rm -rf "$OUT"' EXIT

bash "$ROOT/tools/demo.sh" "$LANG_" >/dev/null
$O kill-server 2>/dev/null || true
$O -f /dev/null new -d -s o -x 150 -y 34 "TMUX= tmux -L junban-demo attach -t work"
$O set -g status off
sleep 1.2
cap() { sleep "${2:-0.8}"; $O capture-pane -ep -t o > "$OUT/$1.ans"; }
client() { $D list-clients -F '#{client_name}' | head -1; }

# 1. two agents need you: the guide line says so, and which key to press
$D refresh-client -S; cap 1 1.5
# 2. Alt+a → straight to the one that has waited longest (a permission prompt)
TMUX="$($D display -p '#{socket_path}'),0,0"; export TMUX
target=$(JUNBAN_DRY_RUN=1 bash "$ROOT/scripts/jump.sh")
$D switch-client -c "$(client)" -t "$target"
$D set -w -t "$target" @junban idle
cap 2
# 3. Alt+f → every agent, neediest first, with a live preview
$D display-popup -c "$(client)" -E -w 90% -h 85% "$ROOT/scripts/switch.sh" &
sleep 1.5; cap 3 0.2
$D send-keys -t "$(client)" Escape 2>/dev/null || true
python3 "$ROOT/tools/ansi2svg.py" "$ROOT/docs/hero-$LANG_.svg" "$OUT/1.ans" "$OUT/2.ans" "$OUT/3.ans" --hold 3
echo "wrote docs/hero-$LANG_.svg"
