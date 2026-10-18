#!/usr/bin/env bash
# hook.sh AGENT EVENT — one entry point for agents other than Claude Code.
#
# Codex CLI and Gemini CLI call this from their hooks (scripts/setup.sh writes
# the config). It maps each agent's event onto a junban state and, where the
# payload allows, the window name and the one-line recap:
#
#   Codex CLI            Gemini CLI          junban
#   SessionStart         SessionStart        idle
#   UserPromptSubmit     BeforeAgent         running  (+ window name, turn start for review.py)
#   PostToolUse          AfterTool           running
#   PermissionRequest    Notification        waiting  (+ recap: what it wants to run)
#   Stop                 AfterAgent          done     (+ recap: what came of it, review: what changed)
#   Interrupt            —                   idle     (Esc mid-turn)
#   SessionEnd           SessionEnd          clear
#
# Stdout matters: Codex adds plain text from some hooks to the model's context,
# and Gemini parses stdout as JSON. So Codex gets nothing and Gemini gets {}.
# Like state.sh, it never fails the agent.
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
agent=${1:-}; event=${2:-}

input=""
if [ ! -t 0 ]; then
  if command -v timeout >/dev/null 2>&1; then input=$(timeout 2 cat 2>/dev/null)
  else IFS= read -r -t 2 -d '' input 2>/dev/null; fi
fi

state() { printf '%s' "$input" | bash "$S/state.sh" "$1" >/dev/null 2>&1; }
# Naming and recaps may ask a model; never make the agent wait for that.
later() { command -v python3 >/dev/null 2>&1 || return 0
  (printf '%s' "$input" | python3 "$S/$1" "${@:2}" >/dev/null 2>&1 &) ; }

case "$agent:$event" in
  codex:SessionStart | gemini:SessionStart) state idle ;;
  codex:UserPromptSubmit | gemini:BeforeAgent) state running; later name.py; later review.py start ;;
  codex:PostToolUse | gemini:AfterTool) state running ;;
  codex:PermissionRequest) state waiting; later recap.py notify ;;
  gemini:Notification)
    case "$input" in *'"ToolPermission"'*) state waiting; later recap.py notify ;; esac ;;
  codex:Stop | gemini:AfterAgent) state "done"; later recap.py "done"; later review.py "done" ;;
  codex:Interrupt) state idle ;;
  codex:SessionEnd | gemini:SessionEnd) state clear ;;
esac

[ "$agent" = gemini ] && printf '{}\n'
exit 0
