#!/usr/bin/env bash
# When your agents worked today, a row per window, from the log state.sh keeps.
#
#   timeline.sh        today
#   timeline.sh 1      yesterday (2 = the day before, …)
#
# Yellow is an agent working, red one waiting for your answer, green one that
# finished before you looked. Like the wait meter, a ✋ or ✓ counts for at most
# @junban-meter-cap minutes; after that the agent is just sitting there.
. "$(dirname "$0")/lib.sh"
load_i18n

log="${XDG_STATE_HOME:-$HOME/.local/state}/junban/states.tsv"
day=${1:-0}
case "$day" in '' | *[!0-9]*) day=0 ;; esac
command -v python3 >/dev/null 2>&1 || { echo "junban: the timeline needs python3" >&2; exit 1; }

cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 100)}
cap=$(( $(opt @junban-meter-cap 60) * 60 ))
alive=$(tmux list-windows -a -F '#{pid}:#{window_id}' 2>/dev/null | tr '\n' ' ')
export T_H T_M T_S TL_TITLE TL_EMPTY TL_RUNNING TL_WAITING TL_DONE TL_SPAN TL_RUN TL_WAITED TL_PEAK TL_MORE
python3 "$JUNBAN_SCRIPTS/timeline.py" "$log" "$day" "$cols" "$cap" "$alive"
