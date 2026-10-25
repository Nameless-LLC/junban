#!/usr/bin/env bash
# starting.sh MESSAGE — a spinner for the window Alt+n just opened, until the agent is up.
#
# It never writes into the pane: the agent owns that screen, and anything drawn
# there races the agent's first frame (Claude Code's trust prompt comes before
# any hook, and a spinner frame landing on it looked like a hang). The spinner
# goes to the message line of each client looking at the window instead.
#
# It stops at the agent's first hook, as soon as anything is on the pane's
# screen, when the agent exits, or after a minute.
p=${TMUX_PANE:-}
[ -n "$p" ] && [ -n "${1:-}" ] || exit 0
f=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
w=$(tmux display -p -t "$p" '#{window_id}' 2>/dev/null) || exit 0
i=0
while [ $i -lt 600 ]; do
  s=$(tmux display -p -t "$p" '#{@junban_starting}|#{@junban}' 2>/dev/null) || break
  [ "$s" = "1|" ] || break
  [ -z "$(tmux capture-pane -p -t "$p" 2>/dev/null | tr -d ' \n')" ] || break
  # The agent is our sibling: both are children of the pane's sh -c.
  [ $i -lt 5 ] || pgrep -P "$PPID" 2>/dev/null | grep -qvx "$$" || break
  m="${f[i % 10]} $1"
  n=$(tmux show -wv -t "$w" @junban_starting_note 2>/dev/null) && [ -n "$n" ] && m="$m  ·  $n"
  # Kept on the window too, so a status format (or a test) can show it.
  tmux set -w -t "$w" @junban_starting_msg "$m" 2>/dev/null
  for c in $(tmux list-clients -F '#{client_name}|#{window_id}' 2>/dev/null | awk -F'|' -v w="$w" '$2 == w { print $1 }'); do
    tmux display -c "$c" -d 300 "$m" 2>/dev/null
  done
  i=$((i + 1))
  sleep 0.1
done
tmux set -wu -t "$w" @junban_starting_msg \; set -wu -t "$w" @junban_starting_note 2>/dev/null
exit 0
