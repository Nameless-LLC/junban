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
tmux new-window -c "$dir" "$cmd; exec \$SHELL"
