#!/usr/bin/env bash
# shellcheck disable=SC2059  # i18n strings are printf formats by design
# The settings menu on Alt+, — the options people change, without opening tmux.conf.
#
#   settings.sh               the menu (a tmux menu over the current pane)
#   settings.sh menu OPTION   the choices for one option
#   settings.sh set OPTION V  save V, apply it now and reload junban
#   settings.sh ask-agent     type a command for Alt+n (runs in a popup)
#   settings.sh disable F N O comment out line N of tmux.conf F, if it still sets O
#
# Choices are saved to $XDG_CONFIG_HOME/junban/settings.conf, which junban.tmux
# reads on every load, so tmux.conf stays yours. A choice made here wins over
# the same option set in tmux.conf before the plugin line; a line after it
# would quietly undo the choice on the next start, so the menu points it out.
# JUNBAN_DRY_RUN=1 prints the menu instead of showing it (the tests use it).
. "$(dirname "$0")/lib.sh"
load_i18n

file=${XDG_CONFIG_HOME:-$HOME/.config}/junban/settings.conf
me="bash $JUNBAN_SCRIPTS/settings.sh"
warn=$(opt @junban-color-slower "#d19a66")

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

# confs — the tmux.conf files tmux reads by default.
confs() {
  local f
  for f in "$HOME/.tmux.conf" "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}

# override OPTION — "FILE<TAB>LINE" of the last line in tmux.conf that sets
# OPTION after junban loads, or nothing.
override() {
  local f
  while IFS= read -r f; do
    awk -v o="$1" -v f="$f" '
      /^[[:space:]]*#/ { next }
      /run/ && /junban\.tmux|tpm\/tpm/ { loaded = 1; next }
      loaded && $0 ~ ("^[[:space:]]*set(-option)?[[:space:]].*" o "([[:space:]]|$)") { hit = NR }
      END { if (hit) print f "\t" hit }' "$f" 2>/dev/null
  done < <(confs)
}

# tilde PATH — PATH with $HOME shown as ~.
tilde() { printf '%s' "${1/#$HOME/\~}"; }

# override_items OPTION — adds a note and a way out to the items array when a
# tmux.conf line overrides OPTION.
override_items() {
  local f n
  IFS=$'\t' read -r f n < <(override "$1"; echo)
  [ -n "$n" ] || return 0
  items+=("" "-#[fg=$warn]$(esc "$(printf "$SET_OVERRIDE_NOTE" "$(tilde "$f")" "$n")")" "" ""
    "  $(esc "$SET_OVERRIDE_OFF")" d
    "confirm-before -p \"$(esc "$(printf "$SET_OVERRIDE_ASK" "$(tilde "$f")" "$n")")\" \"run -b \\\"$me disable '$f' $n $1\\\"\"")
}

# Labels are tmux formats: a # in a value would be read as one.
esc() { printf '%s' "${1//#/##}"; }

menu() {
  local args=(-T "#[align=centre] $(esc "$1") " -x C -y C)
  shift
  # Esc and q close any tmux menu, but nothing on screen says so.
  args+=("$@" "" "  $(esc "$SET_CLOSE")" q "")
  [ -n "${note:-}" ] && args+=("-#[fg=colour244]$(esc "$note")" "" "")
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
  override_items @junban-agent-cmd
  menu "$SET_AGENT" "${items[@]}"
}

case "${1:-}" in
  set)
    o=$2 v=$3
    # Only options this menu offers, so a crafted call cannot rebind keys.
    [ -n "$(field "$o" 1)" ] || exit 1
    mkdir -p "${file%/*}"
    # Two saves at once (two clients, a quick double pick) would each rewrite the
    # file from the same old copy, and one choice would vanish. mkdir is the lock
    # that works on macOS too. One left by a killed save is taken over after 3 s.
    lock="${file%/*}/.settings.lock"
    for _ in $(seq 30); do mkdir "$lock" 2>/dev/null && break; sleep 0.1; done
    mkdir -p "$lock"; trap 'rmdir "$lock" 2>/dev/null' EXIT
    tmp=$(mktemp "${file%/*}/.settings.XXXXXX")
    { [ -f "$file" ] && grep -v "^set -g $o " "$file"
      # Single quotes keep " as typed; a ' closes, goes in "'" and reopens.
      printf "set -g %s '%s'\n" "$o" "${v//\'/\'\"\'\"\'}"; } > "$tmp"
    mv "$tmp" "$file"
    tmux set -g "$o" "$v"
    # Most options are read when junban loads (keys, rows, language).
    bash "$JUNBAN_ROOT/junban.tmux"
    load_i18n
    IFS=$'\t' read -r f n < <(override "$o"; echo)
    if [ -n "$n" ]; then
      tmux display -d 8000 "$(esc "$(printf "$SET_SAVED_OVERRIDE" "$(field "$o" 3)" "$(shown "$o")" "$(tilde "$f")" "$n")")"
    else
      tmux display "$(esc "$(printf "$SET_SAVED" "$(field "$o" 3)" "$(shown "$o")")")"
    fi
    ;;
  disable)
    f=$2 n=$3 o=$4
    [ -n "$(field "$o" 1)" ] || exit 1
    # Only the line the menu showed, and only if it still sets that option:
    # tmux.conf may have changed since.
    [ "$(override "$o" | grep -F "$f")" = "$f"$'\t'"$n" ] || exit 1
    real=$(readlink -f "$f") || exit 1          # a dotfiles symlink stays a symlink
    tmp=$(mktemp "${real%/*}/.tmux.conf.XXXXXX") || exit 1
    # Any step failing leaves tmux.conf exactly as it was.
    if ! awk -v n="$n" -v tag="$SET_DISABLED_TAG" 'NR == n { print "# " $0 "  # " tag; next } { print }' "$real" > "$tmp" ||
       [ "$(awk 'END { print NR }' "$tmp")" != "$(awk 'END { print NR }' "$real")" ] ||
       ! cp -p "$real" "$real.junban.bak"; then
      rm -f "$tmp"; exit 1
    fi
    chmod --reference="$real" "$tmp" 2>/dev/null || chmod 644 "$tmp"
    mv "$tmp" "$real" || { rm -f "$tmp"; exit 1; }
    # What a fresh start would now give: the menu's choice, or the default.
    saved=$(grep "^set -g $o " "$file" 2>/dev/null)
    if [ -n "$saved" ]; then tmux source-file "$file"; else tmux set -gu "$o"; fi
    bash "$JUNBAN_ROOT/junban.tmux"
    load_i18n
    tmux display -d 8000 "$(esc "$(printf "$SET_DISABLED" "$(tilde "$f")" "$n" "$(tilde "$real.junban.bak")")")"
    ;;
  ask-agent)
    cur=$(opt @junban-agent-cmd claude)
    printf '\n  %s\n\n' "$SET_TYPE_HINT"
    # read -i (the current value, ready to edit) is bash 4; macOS ships 3.2.
    if [ "${BASH_VERSINFO[0]:-3}" -ge 4 ]; then IFS= read -r -e -i "$cur" -p "  > " v || exit 0
    else printf '  (%s)\n' "$cur"; IFS= read -r -e -p "  > " v || exit 0; fi
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
    override_items "$2"
    menu "$(field "$2" 3)" "${items[@]}"
    ;;
  *)
    items=() k=1
    while IFS='|' read -r o _ label _; do
      mark=""; [ -n "$(override "$o")" ] && mark="  #[fg=$warn]$(esc "$SET_OVERRIDE_MARK")"
      items+=("$(esc "$label")  #[fg=colour244]$(esc "$(shown "$o")")$mark" "$k" "run -b \"$me menu $o\"")
      k=$((k + 1))
    done < <(options)
    # A leading "-" makes the row a note, not a choice.
    note=$(printf "$SET_FILE" "${file/#$HOME/\~}")
    menu "$SET_TITLE" "${items[@]}"
    ;;
esac
