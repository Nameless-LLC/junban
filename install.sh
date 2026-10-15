#!/usr/bin/env bash
# junban installer for people who don't use TPM.
#   curl -fsSL https://raw.githubusercontent.com/Nameless-LLC/junban/main/install.sh | bash
set -eu
REPO=${JUNBAN_REPO:-https://github.com/Nameless-LLC/junban}
DEST=${JUNBAN_DIR:-$HOME/.tmux/plugins/junban}
CONF=${TMUX_CONF:-$HOME/.tmux.conf}
[ -f "$HOME/.config/tmux/tmux.conf" ] && [ ! -f "$HOME/.tmux.conf" ] && CONF="$HOME/.config/tmux/tmux.conf"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "junban needs $1"; exit 1; }; }
need tmux; need git

v=$(tmux -V | sed 's/[^0-9.]//g')
case "$v" in 0.*|1.*|2.*|3.0*|3.1*) echo "junban needs tmux 3.2 or newer (you have $v)"; exit 1 ;; esac

if [ -d "$DEST/.git" ]; then
  say "Updating $DEST"; git -C "$DEST" pull --ff-only -q
else
  say "Installing to $DEST"; git clone -q --depth 1 "$REPO" "$DEST"
fi

line="run-shell $DEST/junban.tmux"
if ! grep -qF "junban.tmux" "$CONF" 2>/dev/null && ! grep -qF "Nameless-LLC/junban" "$CONF" 2>/dev/null; then
  mkdir -p "$(dirname "$CONF")"
  printf '\n# junban — https://github.com/Nameless-LLC/junban\n%s\n' "$line" >> "$CONF"
  say "Added to $CONF"
fi
[ -n "${TMUX:-}" ] && tmux source-file "$CONF" && say "Reloaded tmux"

command -v fzf >/dev/null 2>&1 || echo "Tip: install fzf for the searchable Alt+f list (it falls back to tmux's chooser)."

if command -v claude >/dev/null 2>&1; then
  say "Connecting Claude Code"
  claude plugin marketplace add Nameless-LLC/junban >/dev/null 2>&1 || true
  if claude plugin install junban@junban >/dev/null 2>&1; then
    echo "Claude Code plugin installed. New and running sessions pick it up automatically."
  else
    echo "Run inside Claude Code:  /plugin marketplace add Nameless-LLC/junban  then  /plugin install junban@junban"
  fi
fi
say "Done. Press Alt+/ in tmux for the keys."
