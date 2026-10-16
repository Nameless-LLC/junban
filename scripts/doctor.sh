#!/usr/bin/env bash
# doctor.sh — check a junban setup and print a report to paste into a bug report.
#
#   ~/.tmux/plugins/junban/scripts/doctor.sh      (or /junban:doctor in Claude Code)
#
# Each check prints ok, warn or FAIL with what to do about it. The report holds
# versions, settings and badge states only: no window names, prompts, paths
# inside your projects, or the values of options that may hold secrets.
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$S")"
. "$S/lib.sh"

n_fail=0; n_warn=0
ok()   { printf '  ok    %s\n' "$1"; }
warn() { n_warn=$((n_warn + 1)); printf '  warn  %s\n' "$1"; [ -n "${2:-}" ] && printf '        → %s\n' "$2"; }
fail() { n_fail=$((n_fail + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        → %s\n' "$2"; }
ver()  { "$@" 2>/dev/null | head -n 1 | tr -d '\r'; }
age()  { local s=$(( $(date +%s) - $1 )); if [ "$s" -lt 120 ]; then echo "${s}s"; elif [ "$s" -lt 7200 ]; then echo "$((s / 60))m"; else echo "$((s / 3600))h"; fi; }

json_get() {  # json_get FILE PYTHON-EXPR-ON-d — prints the result, or nothing
  [ -f "$1" ] && command -v python3 >/dev/null 2>&1 &&
    python3 -c "import json,sys
try:
    d = json.load(open(sys.argv[1]))
    print($2)
except Exception:
    pass" "$1" 2>/dev/null
}

version=$(json_get "$ROOT/.claude-plugin/plugin.json" 'd["version"]')
sha=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null)

echo '```'
echo "junban doctor"
echo
echo "versions"
printf '  junban   %s%s\n' "${version:-?}" "${sha:+ ($sha)}"
printf '  os       %s\n' "$(uname -srm)"
printf '  tmux     %s\n' "$(ver tmux -V || echo missing)"
printf '  bash     %s\n' "$BASH_VERSION"
printf '  python3  %s\n' "$(ver python3 --version || echo missing)"
printf '  term     %s%s\n' "${TERM:-?}" "${TERM_PROGRAM:+ / $TERM_PROGRAM}"
printf '  locale   %s\n' "${LC_ALL:-${LANG:-unset}}"
for a in claude codex gemini; do
  command -v "$a" >/dev/null 2>&1 && printf '  %-8s %s\n' "$a" "$(ver "$a" --version)"
done

echo
echo "tmux"
tv=$(tmux -V 2>/dev/null | sed 's/[^0-9.]//g')
case "$tv" in
  '') fail "tmux not found" "install tmux 3.2 or newer" ;;
  0.* | 1.* | 2.* | 3.0* | 3.1*) fail "tmux $tv is too old" "junban needs tmux 3.2 or newer" ;;
  *) ok "tmux $tv" ;;
esac
if command -v python3 >/dev/null 2>&1; then ok "python3 found"
else warn "python3 missing" "badges work without it; self-healing, window names, recaps and setup.sh need it"; fi
if [ -z "${TMUX:-}" ] && ! tmux list-sessions >/dev/null 2>&1; then
  fail "no tmux server running" "start tmux, then run this again from inside it"
else
  if [ -n "${TMUX:-}" ]; then ok "running inside tmux"; else warn "not inside tmux (checking the default server)"; fi
  if [ -n "$(tmux show -gqv @junban-dir 2>/dev/null)" ]; then ok "junban.tmux loaded"
  else fail "junban.tmux is not loaded in this tmux server" \
    "add  set -g @plugin 'Nameless-LLC/junban'  (TPM) or  run-shell ~/.tmux/plugins/junban/junban.tmux  to tmux.conf, then  tmux source ~/.tmux.conf"
  fi
  case "$(tmux show -gv window-status-format 2>/dev/null)$(tmux show -gv window-status-current-format 2>/dev/null)" in
    *junban-badge*) ok "badges in the window list" ;;
    *) warn "window formats do not include the badge" "with @junban-theme off, put #{E:@junban-badge} in your formats (or reload junban.tmux after your theme)" ;;
  esac
  case "$(tmux show -gv status-right 2>/dev/null)" in
    *summary.sh*) ok "counter on the status line" ;;
    *) warn "status-right does not run summary.sh" "a theme loaded after junban may have replaced it; load junban last" ;;
  esac
fi

echo
echo "agents"
if command -v claude >/dev/null 2>&1; then
  enabled=$(json_get "$HOME/.claude/settings.json" 'd.get("enabledPlugins", {}).get("junban@junban", "")')
  installed=$(json_get "$HOME/.claude/plugins/installed_plugins.json" '" ".join(i.get("version", "?") for i in d.get("plugins", {}).get("junban@junban", []))')
  if [ "$enabled" = True ]; then ok "Claude Code plugin enabled (installed: ${installed:-?})"
  elif [ -n "$installed" ]; then fail "Claude Code plugin installed but not enabled" "run /plugin in Claude Code and enable junban"
  else warn "Claude Code found, but the junban plugin is not installed" "in Claude Code: /plugin marketplace add Nameless-LLC/junban, then /plugin install junban@junban"
  fi
  # A marketplace added from a local folder runs that folder's code, whatever version was recorded.
  msrc=$(json_get "$HOME/.claude/plugins/known_marketplaces.json" 'd.get("junban", {}).get("source", {}).get("source", "")')
  [ "$msrc" = directory ] && ok "Claude plugin runs from a local folder (development setup)"
  if [ "$msrc" != directory ] && [ -n "$installed" ] && [ -n "$version" ] && [ "${installed##* }" != "$version" ]; then
    warn "Claude plugin ${installed##* } differs from the tmux side $version" \
      "claude plugin marketplace update junban && claude plugin update junban@junban, then restart Claude"
  fi
fi
if command -v codex >/dev/null 2>&1; then
  if grep -q 'hook.sh.* codex ' "${CODEX_HOME:-$HOME/.codex}/hooks.json" 2>/dev/null; then ok "Codex hooks installed (trust them once with /hooks)"
  else warn "Codex found but not hooked up" "$S/setup.sh codex"; fi
fi
if command -v gemini >/dev/null 2>&1; then
  if grep -q 'hook.sh.* gemini ' "$HOME/.gemini/settings.json" 2>/dev/null; then ok "Gemini CLI hooks installed"
  else warn "Gemini CLI found but not hooked up" "$S/setup.sh gemini"; fi
fi

if tmux list-sessions >/dev/null 2>&1; then
  echo
  echo "windows (index, badge, age of last change, what runs there)"
  silent=0
  while IFS=$'\t' read -r idx st ts cmd; do
    [ "$st" = - ] && st=""
    case "$cmd" in claude | codex | gemini | node) agent=1 ;; *) agent="" ;; esac
    [ -z "$st" ] && [ -z "$agent" ] && continue
    printf '  %-6s %-8s %-5s %s\n' "$idx" "${st:-none}" "$([ "$ts" -gt 0 ] 2>/dev/null && age "$ts" || echo -)" "$cmd"
    [ -z "$st" ] && [ -n "$agent" ] && [ "$cmd" != node ] && silent=$((silent + 1))
  done < <(tmux list-panes -a -F '#{session_name}:#{window_index}	#{?@junban,#{@junban},-}	#{?@junban_ts,#{@junban_ts},0}	#{pane_current_command}' 2>/dev/null)
  [ "$silent" -gt 0 ] && warn "$silent agent pane(s) show no badge" \
    "an agent started before junban was installed or updated: run /reload-plugins in Claude Code (or restart the agent)"
fi

echo
echo "settings changed from the defaults"
shown=0
while IFS= read -r line; do
  name=${line%% *}; val=${line#* }
  case "$name" in
    @junban-dir | @junban-badge | @junban-scan-at) continue ;;
    @junban-notify-cmd | @junban-namer-url | @junban-namer-key) val="(set)" ;;  # may hold hosts or topics
  esac
  printf '  %s %s\n' "$name" "$val"; shown=1
done < <(tmux show -g 2>/dev/null | grep '^@junban-')
[ "$shown" = 1 ] || echo "  none"

log="${XDG_STATE_HOME:-$HOME/.local/state}/junban/waits.tsv"
echo
echo "logs"
if [ -s "$log" ]; then
  printf '  waits.tsv  %s rows, last %s ago\n' "$(wc -l < "$log" | tr -d ' ')" "$(age "$(tail -n 1 "$log" | cut -f2)")"
else
  echo "  waits.tsv  empty (fills once an agent has waited on you)"
fi

echo
printf 'result: %d problem(s), %d warning(s)\n' "$n_fail" "$n_warn"
echo '```'
echo
echo "Something still wrong? Paste everything above into a bug report:"
echo "https://github.com/Nameless-LLC/junban/issues/new?template=bug.yml"
exit 0
