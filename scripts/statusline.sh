#!/usr/bin/env bash
# Claude Code status line command (usage.py install puts it in settings.json).
# Keeps the plan's usage and the conversation size for the guide line, then
# hands the same input to your own status line command, if you had one.
input=$(cat)
dir="$(cd "$(dirname "$0")" && pwd)"
printf '%s' "$input" | python3 "$dir/usage.py" record >/dev/null 2>&1
next="${XDG_STATE_HOME:-$HOME/.local/state}/junban/usage/statusline-next"
if [ -s "$next" ]; then
  printf '%s' "$input" | sh -c "$(cat "$next")"
fi
exit 0
