#!/usr/bin/env bash
# With @junban-done-batch, send one notification when a slot ends, listing the ✓
# that finished during it, instead of one per agent as it stops.
#
# Runs from summary.sh (every status refresh) and from state.sh (every state
# change), so it fires while nobody is attached too, as long as agents work.
. "$(dirname "$0")/lib.sh"
slot=$(slot_start)
[ "$slot" -gt 0 ] || exit 0
last=$(opt @junban-digest-at 0)
case "$last" in '' | *[!0-9]*) last=0 ;; esac
[ "$last" -lt "$slot" ] || exit 0
# Both callers can arrive in the same second: only one may send.
dir="${XDG_STATE_HOME:-$HOME/.local/state}/junban"
(umask 077; mkdir -p "$dir") 2>/dev/null
mkdir "$dir/digest.$slot" 2>/dev/null || exit 0
tmux set -g @junban-digest-at "$slot"
for d in "$dir"/digest.*; do [ "$d" = "$dir/digest.$slot" ] || rmdir "$d" 2>/dev/null; done
# The first slot after a start has nothing it held back.
[ "$last" -gt 0 ] || exit 0
ncmd=$(opt @junban-notify-cmd "")
[ -n "$ncmd" ] || exit 0
rows=$(tmux list-windows -a -F '#{@junban}	#{@junban_ts}	#{window_name}	#{@junban_recap}' 2>/dev/null |
  awk -F'\t' -v a="$last" -v b="$slot" '$1 == "done" && $2 >= a && $2 < b {
    print "- " $3 ($4 != "" ? ": " $4 : "") }')
[ -n "$rows" ] || exit 0
load_i18n
# shellcheck disable=SC2059
printf '✓ %s\n%s\n' "$(printf "$T_DIGEST" "$(grep -c . <<<"$rows")")" "$rows" | sh -c "$ncmd" >/dev/null 2>&1
exit 0
