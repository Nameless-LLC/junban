#!/usr/bin/env bash
# starting.sh MESSAGE — a spinner in the pane Alt+n just opened, until the agent is up.
#
# It runs beside the agent, so it has to be gone before the agent draws: it stops
# at the agent's first hook (Claude Code's SessionStart comes ~0.3 s before its
# first frame), as soon as anything else moves the cursor, when the agent exits
# (its shell takes over the screen), or after a minute.
p=${TMUX_PANE:-}
[ -n "$p" ] && [ -n "${1:-}" ] || exit 0
f=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
i=0
while [ $i -lt 600 ]; do
  s=$(tmux display -p -t "$p" '#{@junban_starting}|#{@junban}|#{alternate_on}#{cursor_y}' 2>/dev/null) || exit 0
  [ "$s" = "1||00" ] || break
  # The agent is our sibling: both are children of the pane's sh -c.
  [ $i -lt 5 ] || pgrep -P "$PPID" 2>/dev/null | grep -qvx "$$" || break
  printf '\r\033[2m  %s %s\033[0m' "${f[i % 10]}" "$1"
  i=$((i + 1))
  sleep 0.1
done
# Still alone on the screen: leave it blank for the agent.
[ "${s##*|}" = 00 ] && printf '\r\033[2K'
exit 0
