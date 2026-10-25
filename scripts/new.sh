#!/usr/bin/env bash
# new.sh DIR — open a new agent window in DIR.
# new.sh --run — inside that window: work out the command and start the agent.
#
# If another agent already works in DIR's git working tree and the agent is
# Claude Code, start this one in its own worktree (claude --worktree) so the two
# never edit the same files. @junban-new-worktree off keeps the plain behaviour.
. "$(dirname "$0")/lib.sh"

# agent_cmd DIR — sets cmd to what Alt+n starts in DIR.
agent_cmd() {
  local n
  cmd=$(opt @junban-agent-cmd "claude")
  if [ "$(opt @junban-new-worktree auto)" = auto ] && [ "${cmd%% *}" = claude ] &&
     command -v python3 >/dev/null 2>&1; then
    n=$(python3 "$JUNBAN_SCRIPTS/scan.py" --tree "$1" 2>/dev/null)
    if [ "${n:-0}" -gt 0 ] 2>/dev/null; then
      cmd="$cmd --worktree"
      load_i18n
      # shellcheck disable=SC2059
      note=$(printf "$T_NEW_WORKTREE" "$n")
      # The spinner (starting.sh) redraws the message line; it shows this beside itself.
      [ -n "${in_pane:-}" ] && tmux set -w -t "$TMUX_PANE" @junban_starting_note "$note" 2>/dev/null
      tmux display "$note"
    fi
  fi
}

if [ "${1:-}" = --run ]; then
  in_pane=1
  agent_cmd "$PWD"
  # The shell tmux would have run the command with, so agent-cmd reads the same.
  sh=$(tmux show -gv default-shell 2>/dev/null)
  exec "${sh:-${SHELL:-sh}}" -c "$cmd"
fi

dir=${1:-$PWD}
if [ -n "${JUNBAN_DRY_RUN:-}" ]; then agent_cmd "$dir"; echo "$cmd"; exit 0; fi

# An agent can take several seconds to draw anything (Claude Code connects its
# MCP servers first), and an empty pane reads as a hang. The window opens first
# and the worktree check runs inside it, so the spinner (starting.sh) is up at
# once; ◌ stays on the tab until the agent's first hook reports in.
load_i18n
first=$(opt @junban-agent-cmd "claude")
# shellcheck disable=SC2059
msg=$(printf "$T_STARTING" "${first%% *}"); msg=${msg//\'/}
run="bash '$JUNBAN_SCRIPTS/new.sh' --run"
spin="bash '$JUNBAN_SCRIPTS/starting.sh' '$msg' &"
case "$JUNBAN_SCRIPTS" in *"'"*)
  # A quote in the install path cannot go inside the quotes: no spinner, and
  # the plain command as before.
  agent_cmd "$dir"; run=$cmd; spin="" ;;
esac
# Marked in the same command, so the spinner never sees the window unmarked.
w=$(tmux new-window -P -F '#{window_id}' -c "$dir" "$spin $run; exec \$SHELL" \; \
  set -w @junban_starting 1) || exit 0
# An agent without junban's hooks never reports in: drop ◌ after a minute.
(sleep 60; tmux set -wu -t "$w" @junban_starting) >/dev/null 2>&1 &
