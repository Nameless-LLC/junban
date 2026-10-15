#!/usr/bin/env bash
# junban — whose turn is it? A tmux cockpit for running many AI agents at once.
# Loaded by TPM (set -g @plugin 'namelessjp/junban') or by `run-shell /path/junban.tmux`.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$CURRENT_DIR/scripts"
. "$S/lib.sh"

tmux set -g @junban-dir "$CURRENT_DIR"

cw=$(opt @junban-color-waiting "#e06c75")
cd_=$(opt @junban-color-done "#98c379")
cr=$(opt @junban-color-running "#e5c07b")
bg=$(opt @junban-color-bg "#1e2127")
fg=$(opt @junban-color-fg "#abb2bf")
acc=$(opt @junban-color-accent "#61afef")
mut=$(opt @junban-color-muted "#7f848e")
dim=$(opt @junban-color-dim "#5c6370")
sel=$(opt @junban-color-current-bg "#2c313c")

# The badge, reusable in your own formats as #{E:@junban-badge}
badge="#{?#{==:#{@junban},waiting},#[fg=$cw bold]✋ ,#{?#{==:#{@junban},done},#[fg=$cd_ bold]✓ ,#{?#{==:#{@junban},running},#[fg=$cr]● ,}}}"
tmux set -g @junban-badge "$badge"

if [ "$(opt @junban-theme on)" = on ]; then
  name_w=$(opt @junban-name-width 12)
  tmux set -g status-style "bg=$bg,fg=$fg" \; \
       set -g status-left-length 30 \; \
       set -g status-right-length 60 \; \
       set -g status-left "#[bg=$acc,fg=$bg,bold] #S #[bg=default] " \; \
       set -g status-right "#($S/summary.sh)#[fg=$dim]#{?client_prefix,#[fg=$cr]PREFIX ,}#h · %H:%M " \; \
       setw -g window-status-separator "" \; \
       setw -g window-status-format " #[fg=$dim]#I #{E:@junban-badge}#[fg=$mut nobold]#{=$name_w:window_name} " \; \
       setw -g window-status-current-format "#[bg=$sel] #[fg=$acc bold]#I #{E:@junban-badge}#[fg=#e6e6e6 bold]#{=32:window_name} #[bg=default]" \; \
       set -g pane-border-style "fg=#3e4452" \; \
       set -g pane-active-border-style "fg=$acc" \; \
       set -g message-style "bg=$sel,fg=$cr" \; \
       set -g popup-border-style "fg=$acc" \; \
       set -g popup-border-lines rounded
  pos=$(opt @junban-position top)
  tmux set -g status-position "$pos"
else
  # Keep the user's theme: just splice the badge and the counter in, once.
  for f in window-status-format window-status-current-format; do
    cur=$(tmux show -gv "$f")
    case "$cur" in *junban-badge*) ;; *) tmux setw -g "$f" "#{E:@junban-badge}$cur" ;; esac
  done
  cur=$(tmux show -gv status-right)
  case "$cur" in *summary.sh*) ;; *) tmux set -g status-right "#($S/summary.sh)$cur" ;; esac
fi

# Fast enough that badges feel live; summary.sh is cheap.
[ "$(tmux show -gv status-interval)" -gt 5 ] 2>/dev/null && tmux set -g status-interval 5

if [ "$(opt @junban-guide on)" = on ]; then
  tmux set -g status 2 \; set -g status-format[1] "#[bg=$bg]#[align=left]#($S/hints.sh)"
fi

# Opening a window marks its ✓ as seen.
seen='if -F "#{==:#{@junban},done}" "set -w @junban idle"'
tmux set-hook -g 'session-window-changed[42]' "$seen" \; set-hook -g 'client-session-changed[42]' "$seen"

# Quality of life that agent TUIs need inside tmux.
tmux set -g focus-events on \; set -s extended-keys on \; set -s set-clipboard on \; \
     set -as terminal-features ",xterm*:RGB:clipboard:focus:extkeys"

agent_cmd=$(opt @junban-agent-cmd "claude")
bind_root() { [ -n "$1" ] && tmux bind -n "$1" "${@:2}"; }

kj=$(opt @junban-key-jump M-a); kf=$(opt @junban-key-list M-f); kn=$(opt @junban-key-new M-n)
kg=$(opt @junban-key-scratch M-g); kh=$(opt @junban-key-help M-/)
popup_list=(display-popup -E -w 90% -h 85% "$S/switch.sh")
popup_scratch=(display-popup -E -w 80% -h 75% -d "#{pane_current_path}" "tmux new -A -s scratch")
popup_help=(display-popup -E -w 64 -h 26 "$S/help.sh")
new_agent=(new-window -c "#{pane_current_path}" "$agent_cmd; exec \$SHELL")

bind_root "$kj" run -b "$S/jump.sh"
bind_root "$kf" "${popup_list[@]}"
bind_root "$kn" "${new_agent[@]}"
bind_root "$kg" "${popup_scratch[@]}"
bind_root "$kh" "${popup_help[@]}"

if [ "$(opt @junban-prefix-keys on)" = on ]; then
  tmux bind a run -b "$S/jump.sh"
  tmux bind f "${popup_list[@]}"
  tmux bind C "${new_agent[@]}"
  tmux bind g "${popup_scratch[@]}"
  tmux bind / "${popup_help[@]}"
fi

if [ "$(opt @junban-nav-keys on)" = on ]; then
  for i in 1 2 3 4 5 6 7 8 9; do tmux bind -n "M-$i" select-window -t ":=$i"; done
  tmux bind -n 'M-[' previous-window \; bind -n 'M-]' next-window \; \
       bind -n M-Tab last-window \; bind -n M-z resize-pane -Z
fi
