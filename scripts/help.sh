#!/usr/bin/env bash
# The cheat sheet shown by Alt+/ — generated from the keys actually bound.
. "$(dirname "$0")/lib.sh"
load_i18n
cw=$'\033[31m'; cd_=$'\033[32m'; cr=$'\033[33m'; b=$'\033[1m'; dim=$'\033[2m'; r=$'\033[0m'

row() { [ -n "$1" ] && printf '   %s%-12s%s %s\n' "$b" "$1" "$r" "$2"; }
k() { local v; v=$(opt "@junban-key-$1" "$2"); [ -n "$v" ] && keylabel "$v"; }
nav=$(opt @junban-nav-keys on)

{
  printf '\n  %s%s%s\n\n' "$b" "$HELP_TITLE" "$r"
  printf '  %s── %s%s\n' "$dim" "$HELP_BADGES" "$r"
  printf '   %s✋%s  %s\n' "$cw" "$r" "$HELP_B_WAITING"
  printf '   %s✓%s   %s\n' "$cd_" "$r" "$HELP_B_DONE"
  printf '   %s●%s   %s\n\n' "$cr" "$r" "$HELP_B_RUNNING"
  printf '  %s── %s%s\n' "$dim" "$HELP_KEYS" "$r"
  row "$(k jump M-a)" "$HELP_K_JUMP"
  row "$(k list M-f)" "$HELP_K_LIST"
  if [ "$nav" = on ]; then
    row "Alt+1..9" "$HELP_K_NUM"
    row "Alt+[ / ]" "$HELP_K_PREVNEXT"
    row "Alt+Tab" "$HELP_K_LAST"
    row "Alt+z" "$HELP_K_ZOOM"
  fi
  row "$(k new M-n)" "$HELP_K_NEW"
  row "$(k scratch M-g)" "$HELP_K_SHELL"
  row "$(k help M-/)" "$HELP_K_HELP"
  if [ "$(opt @junban-prefix-keys on)" = on ]; then
    printf '\n  %s── %s%s\n' "$dim" "$HELP_PREFIX" "$r"
    printf '   prefix a · f · C · g · /\n'
  fi
  printf '\n  %s%s%s\n' "$dim" "$HELP_CLOSE" "$r"
} | less -R
