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
  [ -f "$JUNBAN_ROOT/i18n/$l.sh" ] || l=en
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

# fmt_dur SECONDS → "42s", "3m10s", "1h20m" in the user's language (T_H/T_M/T_S).
fmt_dur() {
  local s=${1:-0}
  if [ "$s" -lt 60 ]; then printf '%d%s' "$s" "$T_S"
  elif [ "$s" -lt 600 ]; then printf '%d%s%02d%s' $((s / 60)) "$T_M" $((s % 60)) "$T_S"
  elif [ "$s" -lt 3600 ]; then printf '%d%s' $((s / 60)) "$T_M"
  else printf '%d%s%02d%s' $((s / 3600)) "$T_H" $((s % 3600 / 60)) "$T_M"
  fi
}
