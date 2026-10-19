#!/usr/bin/env bash
# shellcheck disable=SC2059  # i18n strings are printf formats by design
# The settings menu on Alt+, — the options people change, without opening tmux.conf.
#
#   settings.sh               the menu (a tmux menu over the current pane)
#   settings.sh menu OPTION   the choices for one option
#   settings.sh set OPTION V  save V, apply it now and reload junban
#   settings.sh ask-agent     type a command for Alt+n (runs in a popup)
#
# Choices are saved to $XDG_CONFIG_HOME/junban/settings.conf, which junban.tmux
# reads on every load, so tmux.conf stays yours. A choice made here wins over
# the same option set in tmux.conf before the plugin line.
# JUNBAN_DRY_RUN=1 prints the menu instead of showing it (the tests use it).
. "$(dirname "$0")/lib.sh"
load_i18n

file=${XDG_CONFIG_HOME:-$HOME/.config}/junban/settings.conf
me="bash $JUNBAN_SCRIPTS/settings.sh"

# The options on the menu, each "option|default|label|choice=label …".
# Kept to what people actually change; the rest stays in tmux.conf.
options() {
  printf '%s\n' \
    "@junban-agent-cmd|claude|$SET_AGENT|" \
    "@junban-lang|$(junban_lang)|$SET_LANG|en=English ja=日本語 th=ไทย" \
    "@junban-position|top|$SET_POSITION|top=$SET_TOP bottom=$SET_BOTTOM" \
    "@junban-guide-lines|3|$SET_LINES|3=$SET_LINES_3 2=$SET_LINES_2" \
    "@junban-meter|on|$SET_METER|on=$SET_ON off=$SET_OFF" \
    "@junban-done-batch|off|$SET_BATCH|off=$SET_OFF 30=$(printf "$SET_EVERY" 30) 60=$(printf "$SET_EVERY" 60)" \
    "@junban-mascot|on|$SET_MASCOT|on=$SET_ON off=$SET_OFF"
}

field() { options | awk -F'|' -v o="$1" -v n="$2" '$1 == o { print $n }'; }

# shown OPTION — the current value as the menu says it.
shown() {
  local v c
  v=$(opt "$1" "$(field "$1" 2)")
  for c in $(field "$1" 4); do
    [ "${c%%=*}" = "$v" ] && { printf '%s' "${c#*=}"; return; }
  done
  printf '%s' "$v"
}

# Labels are tmux formats: a # in a value would be read as one.
esc() { printf '%s' "${1//#/##}"; }

menu() {
  local args=(-T "#[align=centre] $(esc "$1") " -x C -y C)
  shift
  args+=("$@")
  if [ -n "${JUNBAN_DRY_RUN:-}" ]; then printf '%s\n' "${args[@]}"; return; fi
  tmux display-menu "${args[@]}"
}

# The agent command gets its own choices: the bypass ones ask first, since
# they skip every permission check in each agent Alt+n starts.
agent_menu() {
  local cur c items=() k=1 cmd
  cur=$(opt @junban-agent-cmd claude)
  for c in "claude" "claude --allow-dangerously-skip-permissions" "claude --dangerously-skip-permissions" "codex" "gemini"; do
    cmd="run -b \"$me set @junban-agent-cmd '$c'\""
    case "$c" in *dangerously*)
      cmd="confirm-before -p \"$(esc "$SET_BYPASS_ASK")\" \"run -b \\\"$me set @junban-agent-cmd '$c'\\\"\"" ;;
    esac
    items+=("$([ "$c" = "$cur" ] && printf '✓ ' || printf '  ')$c" "$k" "$cmd")
    k=$((k + 1))
  done
  items+=("" "  $SET_TYPE" t "display-popup -E -w 80 -h 7 \"$me ask-agent\"")
  menu "$SET_AGENT" "${items[@]}"
}

case "${1:-}" in
  set)
    o=$2 v=$3
    # Only options this menu offers, so a crafted call cannot rebind keys.
    [ -n "$(field "$o" 1)" ] || exit 1
    mkdir -p "${file%/*}"
    tmp=$(mktemp "${file%/*}/.settings.XXXXXX")
    { [ -f "$file" ] && grep -v "^set -g $o " "$file"
      # Single quotes keep " as typed; a ' closes, goes in "'" and reopens.
      printf "set -g %s '%s'\n" "$o" "${v//\'/\'\"\'\"\'}"; } > "$tmp"
    mv "$tmp" "$file"
    tmux set -g "$o" "$v"
    # Most options are read when junban loads (keys, rows, language).
    bash "$JUNBAN_ROOT/junban.tmux"
    load_i18n
    tmux display "$(esc "$(printf "$SET_SAVED" "$(field "$o" 3)" "$(shown "$o")")")"
    ;;
  ask-agent)
    cur=$(opt @junban-agent-cmd claude)
    printf '\n  %s\n\n' "$SET_TYPE_HINT"
    IFS= read -r -e -i "$cur" -p "  > " v || exit 0
    [ -n "$v" ] && [ "$v" != "$cur" ] && $me set @junban-agent-cmd "$v"
    ;;
  menu)
    if [ "$2" = @junban-agent-cmd ]; then agent_menu; exit 0; fi
    cur=$(opt "$2" "$(field "$2" 2)") items=() k=1
    for c in $(field "$2" 4); do
      items+=("$([ "${c%%=*}" = "$cur" ] && printf '✓ ' || printf '  ')$(esc "${c#*=}")" "$k" \
              "run -b \"$me set $2 '${c%%=*}'\"")
      k=$((k + 1))
    done
    menu "$(field "$2" 3)" "${items[@]}"
    ;;
  *)
    items=() k=1
    while IFS='|' read -r o _ label _; do
      items+=("$(esc "$label")  #[fg=colour244]$(esc "$(shown "$o")")" "$k" "run -b \"$me menu $o\"")
      k=$((k + 1))
    done < <(options)
    # A leading "-" makes the row a note, not a choice.
    items+=("" "-#[fg=colour244]$(esc "$(printf "$SET_FILE" "${file/#$HOME/\~}")")" "" "")
    menu "$SET_TITLE" "${items[@]}"
    ;;
esac
