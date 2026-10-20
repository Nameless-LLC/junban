#!/usr/bin/env bash
# new.sh DIR — open a new agent window in DIR.
#
# If another agent already works in DIR's git working tree and the agent is
# Claude Code, start this one in its own worktree (claude --worktree) so the two
# never edit the same files. @junban-new-worktree off keeps the plain behaviour.
. "$(dirname "$0")/lib.sh"
dir=${1:-$PWD}
cmd=$(opt @junban-agent-cmd "claude")

if [ "$(opt @junban-new-worktree auto)" = auto ] && [ "${cmd%% *}" = claude ] &&
   command -v python3 >/dev/null 2>&1; then
  n=$(python3 "$JUNBAN_SCRIPTS/scan.py" --tree "$dir" 2>/dev/null)
  if [ "${n:-0}" -gt 0 ] 2>/dev/null; then
    cmd="$cmd --worktree"
    load_i18n
    # shellcheck disable=SC2059
    tmux display "$(printf "$T_NEW_WORKTREE" "$n")"
  fi
fi

[ -n "${JUNBAN_DRY_RUN:-}" ] && { echo "$cmd"; exit 0; }
# An agent can take several seconds to draw anything (Claude Code connects its
# MCP servers first), and an empty pane reads as a hang. Spin in the pane (see
# starting.sh) and put ◌ on the tab until the agent's first hook reports in.
load_i18n
# shellcheck disable=SC2059
msg=$(printf "$T_STARTING" "${cmd%% *}"); msg=${msg//\'/}
spin="bash '$JUNBAN_SCRIPTS/starting.sh' '$msg' &"
case "$JUNBAN_SCRIPTS" in *"'"*) spin="printf '  %s\\n' '$msg';" ;; esac
# Marked in the same command, so the spinner never sees the window unmarked.
w=$(tmux new-window -P -F '#{window_id}' -c "$dir" "$spin $cmd; exec \$SHELL" \; \
  set -w @junban_starting 1) || exit 0
# An agent without junban's hooks never reports in: drop ◌ after a minute.
(sleep 60; tmux set -wu -t "$w" @junban_starting) >/dev/null 2>&1 &
