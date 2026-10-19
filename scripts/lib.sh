#!/usr/bin/env bash
# Shared helpers. Sourced by every script; never exits on its own.

JUNBAN_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JUNBAN_ROOT="$(dirname "$JUNBAN_SCRIPTS")"

# opt NAME DEFAULT — read a global tmux user option, falling back to DEFAULT.
opt() {
  local v
  v=$(tmux show-option -gqv "$1" 2>/dev/null)
  printf '%s' "${v:-$2}"
}

# num OPTION DEFAULT [MAX] — a whole-number option. Anything else (60m, -1,
# 08, a[$(cmd)]) is the default: options go into $(( )), which would run them.
num() {
  local v
  v=$(opt "$1" "$2")
  case "$v" in '' | *[!0-9]*) v=$2 ;; esac
  v=$((10#$v))
  [ -n "${3:-}" ] && [ "$v" -gt "$3" ] && v=$3
  printf '%s' "$v"
}

# junban_lang — @junban-lang if set, otherwise guessed from the locale.
junban_lang() {
  local l
  l=$(opt @junban-lang "")
  if [ -z "$l" ]; then
    case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
      ja*) l=ja ;;
      th*) l=th ;;
      *)   l=en ;;
    esac
  fi
  # A name, never a path: the file is sourced.
  case "$l" in en | ja | th) ;; *) l=en ;; esac
  printf '%s' "$l"
}

load_i18n() {
  # shellcheck source=/dev/null
  . "$JUNBAN_ROOT/i18n/en.sh"
  local l
  l=$(junban_lang)
  # shellcheck source=/dev/null
  [ "$l" = en ] || . "$JUNBAN_ROOT/i18n/$l.sh"
}

# keylabel M-a → "Alt+a", C-x → "Ctrl+x"
keylabel() {
  local k=$1
  case "$k" in
    M-*) printf 'Alt+%s' "${k#M-}" ;;
    C-*) printf 'Ctrl+%s' "${k#C-}" ;;
    *)   printf '%s' "$k" ;;
  esac
}

# Keys for the guide line: the Alt key if bound, else "prefix x".
key_for() {
  local k
  k=$(opt "@junban-key-$1" "$2")
  if [ -n "$k" ]; then keylabel "$k"; return; fi
  printf 'prefix %s' "$3"
}

# change NEW OLD FLOOR — how NEW compares with OLD, as one token:
#   "="      too small to mean anything: under FLOOR seconds apart or under 10%
#   "-32%"   less; "+32%" more, up to double
#   "x2.3"   double or more, where a percentage ("+233%") reads as noise
# Small samples swing wildly, and a calm line beats a dramatic one that is wrong.
change() {
  LC_ALL=C awk -v n="${1:-0}" -v o="${2:-0}" -v f="${3:-0}" 'BEGIN {
    n += 0; o += 0; f += 0; d = n - o
    if (o <= 0 || (d < 0 ? -d : d) < f) { print "="; exit }
    p = d * 100 / o; r = int(p + (p < 0 ? -0.5 : 0.5))
    if (r > -10 && r < 10) { print "="; exit }
    if (n >= 2 * o) { x = n / o; if (x >= 10) printf "x%d\n", x; else printf "x%.1f\n", x; exit }
    printf "%+d%%\n", r }'
}

# amount TOKEN — a change token as people read it: "32%" or "2.3×" (T_TIMES).
amount() {
  case "$1" in
    x*) printf "$T_TIMES" "${1#x}" ;;
    *) local a=${1#[+-]}; printf '%s' "$a" ;;
  esac
}

# fmt_dur SECONDS → "42s", "3m10s", "1h20m" in the user's language (T_H/T_M/T_S).
fmt_dur() {
  local s=${1:-0}
  if [ "$s" -lt 60 ]; then printf '%d%s' "$s" "$T_S"
  elif [ "$s" -lt 600 ]; then printf '%d%s%02d%s' $((s / 60)) "$T_M" $((s % 60)) "$T_S"
  elif [ "$s" -lt 3600 ]; then printf '%d%s' $((s / 60)) "$T_M"
  else printf '%d%s%02d%s' $((s / 3600)) "$T_H" $((s % 3600 / 60)) "$T_M"
  fi
}

# client_env PID NAME — one variable from a tmux client's environment (Linux /proc only).
client_env() {
  local f="${JUNBAN_PROC:-/proc}/$1/environ"
  [ -r "$f" ] || return 1
  tr '\0' '\n' < "$f" | sed -n "s/^$2=//p" | head -n1
}

# client_fmt TTY FORMAT — FORMAT for that client, or for the client running us.
client_fmt() {
  if [ -n "$1" ]; then
    tmux list-clients -F "#{client_tty}	$2" 2>/dev/null | awk -F'\t' -v t="$1" '$1 == t { print $2; exit }'
  else
    tmux display -p "$2" 2>/dev/null
  fi
}

# go_to SESSION:WINDOW — show that window to the client that asked.
# VS Code users often keep one window per project, each terminal attached to its
# own session. Swapping what this terminal shows would put project B's agent under
# project A's tab, so when another VS Code window already shows the target session,
# raise that window instead (via VS Code's remote `code` CLI and this terminal's IPC
# socket). Anything else — plain terminals, Web terminals, no window for the target —
# switches in place as before. @junban-vscode-raise off restores the old behaviour.
go_to() {
  local target=$1 sess=${1%%:*} c here cpid ipc cli folder p
  # JUNBAN_CLIENT (a client tty) lets tests act as a given client; display -c alone
  # would still expand formats against the most recent session.
  c=${JUNBAN_CLIENT:-}
  here=$(client_fmt "$c" '#{session_name}')
  if [ "$sess" != "$here" ] && [ "$(opt @junban-vscode-raise on)" = on ]; then
    cpid=$(client_fmt "$c" '#{client_pid}')
    if [ -n "$cpid" ] && [ "$(client_env "$cpid" TERM_PROGRAM)" = vscode ]; then
      ipc=$(client_env "$cpid" VSCODE_IPC_HOOK_CLI)
      cli=$(client_env "$cpid" PATH | tr ':' '\n' | grep '/remote-cli$' | head -n1)
      folder=""
      for p in $(tmux list-clients -t "=$sess" -F '#{client_pid}' 2>/dev/null); do
        [ "$(client_env "$p" TERM_PROGRAM)" = vscode ] || continue
        # PWD is the folder that window opened, symlinks kept. VS Code matches windows
        # by that exact path: the resolved path would open a second window.
        folder=$(client_env "$p" PWD) && [ -n "$folder" ] && break
      done
      if [ -n "$ipc" ] && [ -x "$cli/code" ] && [ -n "$folder" ]; then
        tmux select-window -t "$target"
        if [ -n "${JUNBAN_DRY_RUN:-}" ]; then echo "raise $folder"; return 0; fi
        VSCODE_IPC_HOOK_CLI=$ipc "$cli/code" "$folder" >/dev/null 2>&1 && return 0
      fi
    fi
  fi
  if [ -n "${JUNBAN_DRY_RUN:-}" ]; then echo "switch $target"; return 0; fi
  tmux switch-client ${c:+-c "$c"} -t "$target"
}

# batch_minutes — @junban-done-batch as minutes, 0 when off (or not a number).
batch_minutes() {
  local n
  n=$(opt @junban-done-batch off)
  case "$n" in '' | *[!0-9]*) echo 0; return ;; esac
  n=$((10#$n)); [ "$n" -gt 1440 ] && n=1440
  echo "$n"
}

# slot_start [EPOCH] — with @junban-done-batch N (minutes), the start of the N-minute
# slot of local time that EPOCH (default now) falls in; 0 when batching is off.
# ✓ that finish inside the current slot are held until the next one starts, so
# finished work arrives a few times an hour instead of whenever an agent stops.
slot_start() {
  local n now z off
  n=$(batch_minutes)
  [ "$n" -gt 0 ] || { echo 0; return; }
  now=${1:-$(date +%s)}
  # Slots line up with the wall clock (:00, :30), not with the Unix epoch.
  z=$(date +%z)
  off=$(( (10#${z:1:2} * 3600 + 10#${z:3:2} * 60) * (${z:0:1}1) ))
  echo $(( now - (now + off) % (n * 60) ))
}

# slot_end EPOCH — when a ✓ that finished at EPOCH is shown (0 when batching is off).
slot_end() {
  local s
  s=$(slot_start "$1")
  [ "$s" -gt 0 ] && echo $(( s + $(batch_minutes) * 60 )) || echo 0
}

# hhmm EPOCH — local "15:30".
hhmm() { date -d "@$1" +%H:%M 2>/dev/null || date -r "$1" +%H:%M; }

# trim_log FILE — past 4 MB, keep the last 90 days (rows start with an epoch).
# The status line reads these logs every few seconds; they must not grow forever.
trim_log() {
  local f=$1 tmp cut
  [ -f "$f" ] || return 0
  [ "$(wc -c < "$f" 2>/dev/null || echo 0)" -gt 4000000 ] || return 0
  cut=$(( $(date +%s) - 90 * 86400 ))
  tmp=$(mktemp "$f.XXXXXX" 2>/dev/null) || return 0
  if awk -F'\t' -v c="$cut" '$1 ~ /^[0-9]+$/ && $1 >= c' "$f" > "$tmp" 2>/dev/null; then
    chmod 600 "$tmp" 2>/dev/null; mv "$tmp" "$f" 2>/dev/null || rm -f "$tmp"
  else
    rm -f "$tmp"
  fi
}
