#!/usr/bin/env bash
# record.sh [en|ja] — film the demo video's scenes from a real junban session.
#
#   out: tools/video/build/<lang>/NN.svg, one per scene, and timeline.json
#        (seconds and the key shown for each). render.sh turns them into video.
#
# A second tmux server attaches to the demo, so its pane holds exactly what a
# terminal would show, status lines and popups included. HOME and the state
# directory are throwaway: your settings and wait log stay out of the picture.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LANG_=${1:-en}
D="tmux -L junban-demo"
O="tmux -L junban-outer"
OUT="$ROOT/tools/video/build/$LANG_"
SCREENS="$ROOT/tools/screens/$LANG_"
rm -rf "$OUT"; mkdir -p "$OUT"
HOME=$(mktemp -d); export HOME XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.state"
trap '$O kill-server 2>/dev/null || true; $D kill-server 2>/dev/null || true; rm -rf "$HOME"' EXIT

# Outside any git tree, so no window counts as sharing one.
cd "$HOME"
bash "$ROOT/tools/demo.sh" "$LANG_" >/dev/null
$D set -g @junban-tips off           # the tips on the right would pull the eye
$D set -g status-interval 1
$O kill-server 2>/dev/null || true
$O -f /dev/null new -d -s o -x 150 -y 34 "TMUX= tmux -L junban-demo attach -t work"
$O set -g status off
sleep 1.5
SOCK=$($D display -p '#{socket_path}'); export TMUX="$SOCK,0,0"
client() { $D list-clients -F '#{client_name}' | head -1; }
setst() { $D set -w -t "work:$1" @junban "$2"; $D set -w -t "work:$1" @junban_ts "$3"; }
screen() { $D respawn-pane -k -t "work:$1" "clear; cat '$2'; sleep 86400"; }
jump() { $D switch-client -c "$(client)" -t "$(JUNBAN_DRY_RUN=1 bash "$ROOT/scripts/jump.sh")"; }
now=$(date +%s)

n=0; TL="["
shot() {  # shot SECONDS [KEY]
  sleep 1.2; $D refresh-client -S; sleep 0.6
  n=$((n + 1)); f=$(printf '%02d' $n)
  $O capture-pane -ep -t o > "$OUT/$f.ans"
  python3 "$ROOT/tools/ansi2svg.py" "$OUT/$f.svg" "$OUT/$f.ans" --rows 34 >/dev/null
  TL="$TL{\"file\":\"$f.svg\",\"sec\":$1,\"key\":\"${2:-}\"},"
}

# 0. five agents at work; the guide line shows the keys
for w in 1 2 3 4 5; do setst $w running $((now - 600)); done
$D set -w -t work:6 -u @junban
shot 3.0
# 1. the db migration asks for permission
setst 4 waiting $((now - 240)); shot 2.2
# 2. so does CI
setst 2 waiting $((now - 120)); shot 2.2
# 3. Alt+a → the one that has waited longest
jump; shot 2.6 "Alt+a"
# 4. approve → back to work, one left
screen 4 "$SCREENS/db_run.txt"; setst 4 running "$now"; shot 2.2 "1"
# 5. Alt+a → the CI question
jump; shot 2.2 "Alt+a"
# 6. answer → nobody waiting; the pricing page finished meanwhile
screen 2 "$SCREENS/ci_run.txt"; setst 2 running "$now"; setst 3 "done" "$now"; shot 2.6 "1"
# 7. Alt+f → every agent; typing narrows the list
for q in "" k k8 k8s; do
  $D display-popup -c "$(client)" -E -w 90% -h 85% "FZF_DEFAULT_OPTS='--query=$q' $ROOT/scripts/switch.sh" &
  sleep 1.6
  if [ -z "$q" ]; then shot 1.8 "Alt+f"; else shot 0.5 "$q"; fi
  $D display-popup -c "$(client)" -C 2>/dev/null || true
  sleep 0.4
done
# 8. Enter → the k8s window
$D switch-client -c "$(client)" -t work:5; shot 2.4 "Enter"

echo "${TL%,}]" > "$OUT/timeline.json"
echo "$LANG_: $n scenes in ${OUT#"$ROOT"/}"
