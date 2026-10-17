#!/usr/bin/env bash
# Jump to the agent that most needs you: waiting before done, longest-waiting first.
. "$(dirname "$0")/lib.sh"
here=$(tmux display -p '#{session_name}:#{window_index}')
target=$(tmux list-windows -a -F '#{@junban}	#{@junban_ts}	#{session_name}:#{window_index}' |
  awk -F'\t' -v here="$here" '
    $3 == here { next }
    $1 == "waiting" { print 1 "\t" $2 "\t" $3 }
    $1 == "done"    { print 2 "\t" $2 "\t" $3 }' |
  sort -t"$(printf '\t')" -k1,1n -k2,2n | head -n1 | cut -f3)
if [ -z "$target" ]; then
  load_i18n
  tmux display "$T_JUMP_NONE"
  exit 0
fi
[ -n "${JUNBAN_DRY_RUN:-}" ] && { echo "$target"; exit 0; }
go_to "$target"
