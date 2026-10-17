#!/usr/bin/env bash
# state.sh running|waiting|done|idle|clear
#
# Called from agent hooks (Claude Code, or anything else that can run a command).
# Records the agent's state on the tmux *window* that owns $TMUX_PANE:
#   @junban        running | waiting | done | idle
#   @junban_ts     epoch seconds of the last change (used to order Alt+a)
#   @junban_prompt the last thing you asked it (shown in the Alt+f list)
#
# Leaving "waiting" or "done" ends a stretch where the agent sat on you. Each one
# is appended to $XDG_STATE_HOME/junban/waits.tsv (start, end, kind, window) for
# the meter on the guide line and for stats.sh.
#
# A hook must never break the agent, so every path exits 0.

pane=${TMUX_PANE:-}
st=${1:-}
[ -n "$pane" ] && [ -n "$st" ] && command -v tmux >/dev/null 2>&1 || exit 0

# Only "running" needs the hook payload (for the prompt). Never block on stdin:
# callers other than Claude Code may leave it open.
input=""
if [ "$st" = running ] && [ ! -t 0 ]; then
  if command -v timeout >/dev/null 2>&1; then input=$(timeout 1 cat 2>/dev/null)
  else IFS= read -r -t 1 -d '' input 2>/dev/null; fi
fi

t() { tmux "$@" 2>/dev/null; }
cur=$(t display -p -t "$pane" '#{@junban}')

case "$st" in
  clear)
    # Closing the agent is not answering it, so no wait is logged.
    for o in @junban @junban_ts @junban_prompt @junban_shared @junban_stale @junban_recap; do t set -wu -t "$pane" "$o"; done
    exit 0 ;;
  done)
    # You are looking at it right now: nothing to catch up on. Attached is not enough:
    # with one session per project (one VS Code window each) every session has a client,
    # most of them in windows behind the one you use. tmux knows which terminal has focus
    # (focus-events); terminals that never report focus stay "focused", as before.
    if [ "$(t display -p -t "$pane" '#{window_active}')" = 1 ]; then
      sess=$(t display -p -t "$pane" '#{session_name}')
      t list-clients -t "=$sess" -F '#{client_flags}' 2>/dev/null | grep -q focused && st=idle
    fi ;;
  running)
    # PostToolUse fires constantly; only the first transition matters.
    [ "$cur" = running ] && { [ -z "$input" ] || [ "$input" = "{}" ]; } && exit 0 ;;
  waiting|idle) ;;
  *) exit 0 ;;
esac

if [ "$st" != "$cur" ]; then
  case "$cur" in
    waiting|done)
      since=$(t display -p -t "$pane" '#{@junban_ts}')
      if [ -n "$since" ]; then
        log="${XDG_STATE_HOME:-$HOME/.local/state}/junban/waits.tsv"
        name=$(t display -p -t "$pane" '#{session_name}:#{window_name}' | tr '\t' ' ')
        # Window names can say what you work on: keep the log to yourself.
        (umask 077; mkdir -p "${log%/*}" 2>/dev/null &&
          printf '%s\t%s\t%s\t%s\n' "$since" "$(date +%s)" "$cur" "$name" >> "$log" 2>/dev/null &&
          chmod go-rwx "${log%/*}" "$log" 2>/dev/null)
      fi ;;
  esac
  t set -w -t "$pane" @junban "$st"
  t set -w -t "$pane" @junban_ts "$(date +%s)"
fi

if [ "$st" = running ] && [ -n "$input" ] && command -v python3 >/dev/null 2>&1; then
  prompt=$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    p = (json.load(sys.stdin).get("prompt") or "").strip()
except Exception:
    p = ""
if p and not p.startswith("<"):
    print(" ".join(p.split())[:120])' 2>/dev/null)
  [ -n "$prompt" ] && t set -w -t "$pane" @junban_prompt "$prompt" && t set -wu -t "$pane" @junban_recap
fi

# Optional desktop/phone notification, e.g.
#   set -g @junban-notify-cmd 'notify-send junban'      (Linux)
#   set -g @junban-notify-cmd 'curl -s -d @- ntfy.sh/my-topic'
# With recaps on, recap.py sends the ✓ one itself once it knows what came of the turn.
if [ "$st" = "done" ] && [ "$(t show -gqv @junban-recap)" != off ] && command -v python3 >/dev/null 2>&1; then ncmd=""
else ncmd=$(t show -gqv @junban-notify-cmd); fi
if [ "$st" != "$cur" ] && { [ "$st" = waiting ] || [ "$st" = "done" ]; }; then
  if [ -n "$ncmd" ]; then
    name=$(t display -p -t "$pane" '#{window_name}')
    icon="✋"; [ "$st" = "done" ] && icon="✓"
    printf '%s %s\n' "$icon" "$name" | sh -c "$ncmd" >/dev/null 2>&1 &
  fi
fi

# Redraw now instead of waiting for status-interval.
for c in $(t list-clients -F '#{client_name}'); do t refresh-client -S -t "$c"; done
exit 0
