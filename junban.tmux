#!/usr/bin/env bash
# junban — whose turn is it? A tmux cockpit for running many AI agents at once.
# Loaded by TPM (set -g @plugin 'Nameless-LLC/junban') or by `run-shell /path/junban.tmux`.
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
# ! another agent works in the same git tree; z untouched for @junban-stale-hours
badge="$badge#{?@junban_stale,#[fg=$dim nobold]z ,}"
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
  # While the prefix is pending, the last guide row lists what can follow it. Built
  # here rather than in hints.sh: a #() job would show its old output for a moment,
  # and the hint is only worth anything the instant the prefix goes down.
  load_i18n
  digits=0-9; [ "$(opt @junban-nav-keys on)" = on ] && digits=1-9
  pk="#[fg=$cr]$digits#[fg=$mut] $T_PK_WIN  #[fg=$cr]n/p#[fg=$mut] $T_PK_NP"
  if [ "$(opt @junban-prefix-keys on)" = on ]; then
    for pair in "a|$T_NEXT" "f|$T_LIST" "C|$T_NEW" "g|$T_SHELL" "/|$T_HELP"; do
      pk="$pk  #[fg=$cr]${pair%%|*}#[fg=$mut] ${pair#*|}"
    done
  fi
  pk=${pk//,/#,}   # a comma would end the #{?…} branch early
  # Three rows by default: the banner (or today's wait) on one, the keys below.
  # @junban-guide-lines 2 drops the keys row; the keys then show only after the prefix.
  if [ "$(opt @junban-guide-lines 3)" = 3 ]; then
    # A shade darker, so the keys row sits apart from both the banner and the pane.
    bg2=$(opt @junban-color-bg2 "#17191d")
    tmux set -g status 3 \; \
         set -g status-format[1] "#[bg=$bg]#[align=left]#($S/hints.sh #{client_width} 1)" \; \
         set -g status-format[2] "#[bg=$bg2]#[fill=$bg2]#[align=left]#{?client_prefix,$pk,#($S/hints.sh #{client_width} 2)}"
  else
    tmux set -g status 2 \; set -g status-format[1] "#[bg=$bg]#[align=left]#{?client_prefix,$pk,#($S/hints.sh #{client_width})}"
    # Back from 3 rows: drop our third row, never a user's own.
    case "$(tmux show -gv 'status-format[2]' 2>/dev/null)" in *hints.sh*) tmux set -gu 'status-format[2]' ;; esac
  fi
fi

# Opening a window marks its ✓ as seen (through state.sh, so the wait is logged).
seen="if -F '#{==:#{@junban},done}' \"run -b 'TMUX_PANE=#{window_id} bash $S/state.sh idle'\""
tmux set-hook -g 'session-window-changed[42]' "$seen" \; set-hook -g 'client-session-changed[42]' "$seen"
# Coming back to a terminal counts too: Alt+a may raise another VS Code window
# instead of changing what this one shows.
tmux set-hook -g 'client-focus-in[42]' "$seen"

# Quality of life that agent TUIs need inside tmux.
tmux set -g focus-events on \; set -s extended-keys on \; set -s set-clipboard on \; \
     set -as terminal-features ",xterm*:RGB:clipboard:focus:extkeys"

bind_root() { [ -n "$1" ] && tmux bind -n "$1" "${@:2}"; }

kj=$(opt @junban-key-jump M-a); kf=$(opt @junban-key-list M-f); kn=$(opt @junban-key-new M-n)
kg=$(opt @junban-key-scratch M-g); kh=$(opt @junban-key-help M-/)
# No Alt key by default: Alt+t already toggles thinking in Claude Code.
kt=$(opt @junban-key-timeline "")
popup_list=(display-popup -E -w 90% -h 85% "$S/switch.sh")
popup_scratch=(display-popup -E -w 80% -h 75% -d "#{pane_current_path}" "tmux new -A -s scratch")
popup_help=(display-popup -E -w 80 -h 90% "$S/help.sh")
popup_timeline=(display-popup -E -w 95% -h 60% "$S/timeline.sh | $S/page.sh")
# q: shell-quotes the path; a directory named a'$(cmd)' must stay a name.
new_agent=(run -b "$S/new.sh #{q:pane_current_path}")

bind_root "$kj" run -b "$S/jump.sh"
bind_root "$kf" "${popup_list[@]}"
bind_root "$kn" "${new_agent[@]}"
bind_root "$kg" "${popup_scratch[@]}"
bind_root "$kh" "${popup_help[@]}"
bind_root "$kt" "${popup_timeline[@]}"

if [ "$(opt @junban-prefix-keys on)" = on ]; then
  tmux bind a run -b "$S/jump.sh"
  tmux bind f "${popup_list[@]}"
  tmux bind C "${new_agent[@]}"
  tmux bind g "${popup_scratch[@]}"
  tmux bind / "${popup_help[@]}"
  tmux bind T "${popup_timeline[@]}"
fi

if [ "$(opt @junban-nav-keys on)" = on ]; then
  # Alt+1 should open the first tab: count tabs from 1 and close the gaps,
  # including in sessions that already run with tabs from 0.
  tmux set -g base-index 1 \; setw -g pane-base-index 1 \; set -g renumber-windows on
  for s in $(tmux list-sessions -F '#{session_id}' 2>/dev/null); do tmux move-window -r -t "$s" 2>/dev/null; done
  for i in 1 2 3 4 5 6 7 8 9; do tmux bind -n "M-$i" select-window -t ":=$i"; done
  tmux bind -n 'M-[' previous-window \; bind -n 'M-]' next-window \; \
       bind -n M-Tab last-window \; bind -n M-z resize-pane -Z
fi
