#!/usr/bin/env bash
# shellcheck disable=SC2059  # i18n strings are printf formats by design
# update.sh [now] — keep junban current without anyone running a command.
#
# hints.sh starts it in the background once a day; Alt+, → Update runs it with
# "now" and says what happened. @junban-update picks what it follows:
#   stable (default)  the newest release tag (CI passed, version bumped)
#   main              every commit on the branch you installed from
#   off               nothing
#
# It only ever fast-forwards a clean git checkout on a branch: local changes, a
# pinned (detached) checkout or a branch ahead of the release are left alone.
# Then it reloads junban and updates the Claude Code plugin (its hooks), which
# new Claude sessions pick up. Any failure leaves things as they were.
. "$(dirname "$0")/lib.sh"
load_i18n
now=${1:-}
# The test suite sets this so nothing it runs touches the checkout it runs from.
[ -n "${JUNBAN_NO_UPDATE:-}" ] && [ -z "${JUNBAN_UPDATE_DIR:-}" ] && exit 0
mode=$(opt @junban-update stable)
dir=${JUNBAN_UPDATE_DIR:-$JUNBAN_ROOT}
say() { [ -n "$now" ] && tmux display -d 5000 "$1" 2>/dev/null; return 0; }
# A hung network must not leave a git process behind for ever.
t() { if command -v timeout >/dev/null 2>&1; then timeout 60 "$@"; else "$@"; fi; }
g() { git -C "$dir" "$@" 2>/dev/null; }
version() { sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$dir/.claude-plugin/plugin.json" 2>/dev/null | head -n 1; }

# Asking for it (Alt+, → Update now) updates even with automatic updates off.
case "$mode" in stable | main) ;; *) [ -n "$now" ] || exit 0; mode=stable ;; esac

# One at a time; a lock left by a killed run is taken over after ten minutes.
lock="${XDG_STATE_HOME:-$HOME/.local/state}/junban/update.lock"
mkdir -p "${lock%/*}" 2>/dev/null
find "$lock" -maxdepth 0 -mmin +10 -exec rmdir {} \; 2>/dev/null
mkdir "$lock" 2>/dev/null || exit 0
trap 'rmdir "$lock" 2>/dev/null' EXIT

# The Claude side, for the copy tmux runs: harmless when the plugin is not installed.
plugin() { [ "$dir" = "$JUNBAN_ROOT" ] && command -v claude >/dev/null 2>&1 && t claude plugin update junban@junban >/dev/null 2>&1; return 0; }

old_v=$(version)
if [ "$(g rev-parse --show-toplevel)" != "$(cd "$dir" 2>/dev/null && pwd -P)" ] ||
   ! g symbolic-ref -q HEAD >/dev/null || [ -n "$(g status --porcelain --untracked-files=no)" ]; then
  plugin; say "$(printf "$T_UPDATE_MANUAL" "${old_v:-?}")"; exit 0
fi
t git -C "$dir" fetch -q --tags origin 2>/dev/null || { say "$T_UPDATE_FAILED"; exit 0; }
if [ "$mode" = stable ]; then
  target=$(g tag -l 'v[0-9]*' --sort=-v:refname | head -n 1)
else
  target=$(g rev-parse -q --verify '@{u}')
fi
old=$(g rev-parse HEAD)
new=$(g rev-parse -q --verify "${target:-none}^{commit}")
if [ -z "$new" ] || [ "$old" = "$new" ] || ! g merge-base --is-ancestor "$old" "$new" ||
   ! g merge -q --ff-only "$new"; then
  plugin; say "$(printf "$T_UPDATE_CURRENT" "${old_v:-?}")"; exit 0
fi

new_v=$(version)
log="${XDG_STATE_HOME:-$HOME/.local/state}/junban/update.log"
printf '%s\t%s\t%s\n' "$(date +%s)" "${old_v:-?}" "${new_v:-?}" >> "$log" 2>/dev/null
# Reload only the copy tmux runs; a test or a second checkout stays quiet.
[ "$dir" = "$JUNBAN_ROOT" ] && bash "$JUNBAN_ROOT/junban.tmux" >/dev/null 2>&1
load_i18n
plugin
# Asked for: say it now. Otherwise the status line says it once (hints.sh), so
# whoever comes back to the terminal later still sees it.
if [ -n "$now" ] && [ "$dir" = "$JUNBAN_ROOT" ] && [ -n "$new_v" ]; then
  echo "$new_v" > "${log%/*}/version" 2>/dev/null
  tmux set -g @junban_version_seen "$new_v" 2>/dev/null
fi
say "$(printf "$T_UPDATED" "${new_v:-?}")"
exit 0
