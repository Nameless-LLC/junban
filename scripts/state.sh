#!/usr/bin/env bash
# state.sh running|waiting|done|idle|clear|tool
#
# tool is "running" for hooks that fire after every tool call (PostToolUse):
# it ignores the payload, which carries the tool's whole output, and costs
# one tmux query when the agent is already running.
#
# Called from agent hooks (Claude Code, or anything else that can run a command).
# Records the agent's state on the tmux *window* that owns $TMUX_PANE:
#   @junban        running | waiting | done | idle
#   @junban_ts     epoch seconds of the last change (used to order Alt+a)
#   @junban_prompt the last thing you asked it (shown in the Alt+f list)
#
# Leaving "waiting" or "done" ends a stretch where the agent sat on you. Each one
# is appended to $XDG_STATE_HOME/junban/waits.tsv (start, end, kind, window) for
# the meter on the guide line and for stats.sh. Every change of state is also
# appended to states.tsv (time, state, window key, window) for timeline.sh.
#
# A hook must never break the agent, so every path exits 0.

pane=${TMUX_PANE:-}
st=${1:-}
[ -n "$pane" ] && [ -n "$st" ] && command -v tmux >/dev/null 2>&1 || exit 0

# PostToolUse fires on every tool call with megabytes of output on stdin, and
# only the first one after a wait changes anything. Decide before reading it.
if [ "$st" = tool ]; then
  [ "$(tmux display -p -t "$pane" '#{@junban}' 2>/dev/null)" = running ] && exit 0
  st=running; exec </dev/null
fi

# Only "running" needs the hook payload (for the prompt). Never block on stdin:
# callers other than Claude Code may leave it open.
input=""
if [ "$st" = running ] && [ ! -t 0 ]; then
  if command -v timeout >/dev/null 2>&1; then input=$(timeout 1 cat 2>/dev/null)
  else IFS= read -r -t 1 -d '' input 2>/dev/null; fi
fi

. "$(dirname "$0")/lib.sh"
t() { tmux "$@" 2>/dev/null; }
cur=$(t display -p -t "$pane" '#{@junban}')
# Any hook means the agent is up: Alt+n's ◌ has done its job.
t set -wu -t "$pane" @junban_starting

# Where the agent really works, for Alt+n's "is this tree taken" check. tmux's
# pane_current_path reads the foreground process group's leader, and a pane
# started as `bash -c "claude --worktree; …"` (Alt+n) never gives claude its own
# group, so tmux keeps reporting the repo root the worktree was made from. The
# hook runs in the agent's directory; the payload's cwd also follows EnterWorktree.
dir=$PWD; prompt=""
if [ -n "$input" ] && command -v python3 >/dev/null 2>&1; then
  { IFS= read -r c; IFS= read -r prompt; } < <(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
d = d if isinstance(d, dict) else {}
c = d.get("cwd")
print(c if isinstance(c, str) and "\n" not in c else "")
p = (d.get("prompt") or "").strip() if isinstance(d.get("prompt"), str) else ""
print(" ".join(p.split())[:120] if p and not p.startswith("<") else "")' 2>/dev/null)
  [ -n "$c" ] && dir=$c
fi
case "$st" in running|waiting|done|idle) [ -n "$dir" ] && t set -p -t "$pane" @junban_cwd "$dir" ;; esac

# timeline STATE — one row per change. The key (server pid + window id) stays put
# when the window is renamed; the name is what the timeline prints.
timeline() {
  local log="${XDG_STATE_HOME:-$HOME/.local/state}/junban/states.tsv" w
  w=$(t display -p -t "$pane" '#{pid}:#{window_id}	#{session_name}:#{window_name}' | tr -d '\n')
  [ -n "$w" ] || return 0
  (umask 077; mkdir -p "${log%/*}" 2>/dev/null &&
    printf '%s\t%s\t%s\n' "$(date +%s)" "$1" "$w" >> "$log" 2>/dev/null &&
    chmod go-rwx "${log%/*}" "$log" 2>/dev/null)
  trim_log "$log"; trim_log "${log%/*}/waits.tsv"; trim_log "${log%/*}/done.tsv"
}

case "$st" in
  clear)
    # Closing the agent is not answering it, so no wait is logged.
    [ -n "$cur" ] && timeline clear
    for o in @junban @junban_ts @junban_prompt @junban_shared @junban_stale @junban_recap @junban_review @junban_pr @junban_base; do t set -wu -t "$pane" "$o"; done
    t set -pu -t "$pane" @junban_cwd
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
      # A ✓ held by @junban-done-batch only starts waiting on you once it shows;
      # opening it before then is no wait at all.
      if [ "$cur" = "done" ] && [ -n "$since" ]; then
        e=$(slot_end "$since"); [ "$e" -gt 0 ] && since=$e
        [ "$since" -gt "$(date +%s)" ] && since=""
      fi
      if [ -n "$since" ]; then
        log="${XDG_STATE_HOME:-$HOME/.local/state}/junban/waits.tsv"
        name=$(t display -p -t "$pane" '#{session_name}:#{window_name}' | tr '\t' ' ')
        # Window names can say what you work on: keep the log to yourself.
        (umask 077; mkdir -p "${log%/*}" 2>/dev/null &&
          printf '%s\t%s\t%s\t%s\n' "$since" "$(date +%s)" "$cur" "$name" >> "$log" 2>/dev/null &&
          chmod go-rwx "${log%/*}" "$log" 2>/dev/null)
      fi ;;
  esac
  timeline "$st"
  t set -w -t "$pane" @junban "$st"
  t set -w -t "$pane" @junban_ts "$(date +%s)"
fi

if [ "$st" = running ] && [ -n "$prompt" ]; then
  t set -w -t "$pane" @junban_prompt "$prompt" && t set -wu -t "$pane" @junban_recap \; set -wu -t "$pane" @junban_review \; set -wu -t "$pane" @junban_pr
fi

# Optional desktop/phone notification, e.g.
#   set -g @junban-notify-cmd 'notify-send junban'      (Linux)
#   set -g @junban-notify-cmd 'curl -s -d @- ntfy.sh/my-topic'
# With recaps on, recap.py sends the ✓ one itself once it knows what came of the turn.
# With @junban-done-batch, digest.sh sends the ✓ together when the slot ends.
if [ "$st" = "done" ] && [ "$(t show -gqv @junban-recap)" != off ] && command -v python3 >/dev/null 2>&1; then ncmd=""
elif [ "$st" = "done" ] && [ "$(slot_start)" -gt 0 ]; then ncmd=""
else ncmd=$(t show -gqv @junban-notify-cmd); fi
if [ "$st" != "$cur" ] && { [ "$st" = waiting ] || [ "$st" = "done" ]; }; then
  if [ -n "$ncmd" ]; then
    name=$(t display -p -t "$pane" '#{window_name}')
    icon="✋"; [ "$st" = "done" ] && icon="✓"
    printf '%s %s\n' "$icon" "$name" | sh -c "$ncmd" >/dev/null 2>&1 &
  fi
fi

(bash "$JUNBAN_SCRIPTS/digest.sh" >/dev/null 2>&1 &)

# Redraw now instead of waiting for status-interval.
for c in $(t list-clients -F '#{client_name}'); do t refresh-client -S -t "$c"; done
exit 0
