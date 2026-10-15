#!/usr/bin/env bash
# Every agent in one searchable list, neediest first, with a live preview.
# Uses fzf when available; falls back to tmux's own tree chooser.
. "$(dirname "$0")/lib.sh"
load_i18n

if ! command -v fzf >/dev/null 2>&1; then
  tmux choose-tree -Zw -O name \
    -F "#{?#{==:#{@junban},waiting},✋ ,#{?#{==:#{@junban},done},✓ ,#{?#{==:#{@junban},running},● ,  }}}#{window_name}  #[dim]#{@junban_prompt}"
  exit 0
fi

now=$(date +%s)
list=$(tmux list-windows -a -F "#{@junban}	#{@junban_ts}	#{session_name}:#{window_index}	#{window_name}	#{@junban_prompt}" |
  awk -F'\t' -v now="$now" '
    { rank = 4; icon = "  "
      if ($1 == "waiting")      { rank = 1; icon = "\033[31m✋\033[0m" }
      else if ($1 == "done")    { rank = 2; icon = "\033[32m✓\033[0m " }
      else if ($1 == "running") { rank = 3; icon = "\033[33m●\033[0m " }
      age = ""
      if ($2 != "") { d = now - $2; age = (d < 60 ? d "s" : d < 3600 ? int(d / 60) "m" : int(d / 3600) "h") }
      # waiting/done: oldest first. Others keep window order.
      key = (rank <= 2 ? $2 : 0)
      printf "%d\t%012d\t%s\t%s %-5s \033[1m%s\033[0m  \033[2m%s\033[0m\n", rank, key, $3, icon, age, $4, $5 }' |
  sort -t"$(printf '\t')" -k1,1n -k2,2n -s | cut -f3-)

# shellcheck disable=SC2016  # $FZF_PREVIEW_LINES is expanded by fzf
sel=$(printf '%s\n' "$list" | fzf --ansi --delimiter='\t' --with-nth=2 --no-sort \
  --layout=reverse --border=none --prompt='› ' --pointer='▌' --info=inline-right \
  --header="$T_SWITCH_HEADER" \
  --preview='tmux capture-pane -ep -t {1} | grep -v "^[[:space:]]*$" | tail -n "$FZF_PREVIEW_LINES"' \
  --preview-window='down,55%,border-top' \
  --bind='ctrl-x:execute-silent(tmux kill-window -t {1})+abort' \
  --color='bg+:#2a2f3a,hl:#e5c07b,hl+:#e5c07b,pointer:#61afef,prompt:#61afef,header:#5c6370')
[ -n "$sel" ] && tmux switch-client -t "$(printf '%s' "$sel" | cut -f1)"
exit 0
