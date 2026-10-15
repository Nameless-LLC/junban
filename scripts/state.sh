#!/usr/bin/env bash
# state.sh running|waiting|done|idle|clear
#
# Called from agent hooks (Claude Code, or anything else that can run a command).
# Records the agent's state on the tmux *window* that owns $TMUX_PANE:
#   @junban        running | waiting | done | idle
#   @junban_ts     epoch seconds of the last change (used to order Alt+a)
#   @junban_prompt the last thing you asked it (shown in the Alt+f list)
#
# A hook must never break the agent, so every path exits 0.

pane=${TMUX_PANE:-}
st=${1:-}
[ -n "$pane" ] && [ -n "$st" ] && command -v tmux >/dev/null 2>&1 || exit 0

# Only "running" needs the hook payload (for the prompt). Never block on stdin:
# callers other than Claude Code may leave it open.
input=""
if [ "$st" = running ] && [ ! -t 0 ]; then
  if command -v timeout >/dev/null 2>&1; then input=$(timeout 1 cat 2>/dev/null)
  else IFS= read -r -t 1 -d '' input 2>/dev/null; fi
fi

t() { tmux "$@" 2>/dev/null; }
cur=$(t display -p -t "$pane" '#{@junban}')

case "$st" in
  clear)
    for o in @junban @junban_ts @junban_prompt; do t set -wu -t "$pane" "$o"; done
    exit 0 ;;
  done)
    # You are looking at it right now: nothing to catch up on.
    [ "$(t display -p -t "$pane" '#{&&:#{window_active},#{session_attached}}')" = 1 ] && st=idle ;;
  running)
    # PostToolUse fires constantly; only the first transition matters.
    [ "$cur" = running ] && { [ -z "$input" ] || [ "$input" = "{}" ]; } && exit 0 ;;
  waiting|idle) ;;
  *) exit 0 ;;
esac

if [ "$st" != "$cur" ]; then
  t set -w -t "$pane" @junban "$st"
  t set -w -t "$pane" @junban_ts "$(date +%s)"
fi

if [ "$st" = running ] && [ -n "$input" ] && command -v python3 >/dev/null 2>&1; then
  prompt=$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    p = (json.load(sys.stdin).get("prompt") or "").strip()
except Exception:
    p = ""
if p and not p.startswith("<"):
    print(" ".join(p.split())[:120])' 2>/dev/null)
  [ -n "$prompt" ] && t set -w -t "$pane" @junban_prompt "$prompt"
fi

# Optional desktop/phone notification, e.g.
#   set -g @junban-notify-cmd 'notify-send junban'      (Linux)
#   set -g @junban-notify-cmd 'curl -s -d @- ntfy.sh/my-topic'
if [ "$st" != "$cur" ] && { [ "$st" = waiting ] || [ "$st" = "done" ]; }; then
  ncmd=$(t show -gqv @junban-notify-cmd)
  if [ -n "$ncmd" ]; then
    name=$(t display -p -t "$pane" '#{window_name}')
    icon="✋"; [ "$st" = "done" ] && icon="✓"
    printf '%s %s\n' "$icon" "$name" | sh -c "$ncmd" >/dev/null 2>&1 &
  fi
fi

# Redraw now instead of waiting for status-interval.
for c in $(t list-clients -F '#{client_name}'); do t refresh-client -S -t "$c"; done
exit 0
