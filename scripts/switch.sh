#!/usr/bin/env bash
# Every agent in one searchable list, neediest first, with a live preview.
# Uses fzf when available; falls back to tmux's own tree chooser.
#   switch.sh --open WIN   open the PR that window's agent reported (Ctrl+o in the list)
. "$(dirname "$0")/lib.sh"
load_i18n

if [ "${1:-}" = --open ]; then
  url=$(tmux display -p -t "$2" '#{@junban_pr}' 2>/dev/null)
  [ -n "$url" ] || exit 0
  # The popup runs with the server's environment; the browser is the client's.
  # VS Code's terminal sets BROWSER to a helper that opens it on your machine.
  cpid=$(tmux display -p '#{client_pid}' 2>/dev/null)
  b=$(client_env "$cpid" BROWSER 2>/dev/null)
  [ -n "$b" ] || b=${BROWSER:-}
  if [ -n "$b" ]; then "$b" "$url"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$url"
  elif command -v open >/dev/null 2>&1; then open "$url"
  fi >/dev/null 2>&1 &
  exit 0
fi

if ! command -v fzf >/dev/null 2>&1; then
  tmux choose-tree -Zw -O name \
    -F "#{?#{==:#{@junban},waiting},✋ ,#{?#{==:#{@junban},done},✓ ,#{?#{==:#{@junban},running},● ,  }}}#{window_name}  #[dim]#{@junban_prompt}"
  exit 0
fi

now=$(date +%s)
list=$(tmux list-windows -a -F "#{@junban}	#{@junban_ts}	#{session_name}:#{window_index}	#{window_name}	#{?@junban_recap,→ #{@junban_recap},#{@junban_prompt}}	#{@junban_stale}	#{@junban_review}" |
  awk -F'\t' -v now="$now" '
    { rank = 4; icon = "  "
      if ($1 == "waiting")      { rank = 1; icon = "\033[31m✋\033[0m" }
      else if ($1 == "done")    { rank = 2; icon = "\033[32m✓\033[0m " }
      else if ($1 == "running") { rank = 3; icon = "\033[33m●\033[0m " }
      age = ""
      if ($2 != "") { d = now - $2; age = (d < 60 ? d "s" : d < 3600 ? int(d / 60) "m" : d < 172800 ? int(d / 3600) "h" : int(d / 86400) "d") }
      # Parked for a day or more: sink to the bottom, dimmed, so they read as "tidy me".
      if ($6 != "") { rank = 5; icon = "\033[2mz\033[0m " }
      # A finished turn says what it changed, so you can pick what to review first.
      if (rank == 2 && $7 != "") $5 = $5 "  · " $7
      # waiting/done: oldest first. Parked: oldest last. Others keep window order.
      key = (rank <= 2 ? $2 : rank == 5 ? 9999999999 - $2 : 0)
      printf "%d\t%012d\t%s\t%s %-5s \033[1m%s\033[0m  \033[2m%s\033[0m\n", rank, key, $3, icon, age, $4, $5 }' |
  sort -t"$(printf '\t')" -k1,1n -k2,2n -s | cut -f3-)

sel=$(printf '%s\n' "$list" | fzf --ansi --delimiter='\t' --with-nth=2 --no-sort \
  --layout=reverse --border=none --prompt='› ' --pointer='▌' --info=inline-right \
  --header="$T_SWITCH_HEADER" \
  --preview="python3 '$JUNBAN_SCRIPTS/review.py' preview {1} 2>/dev/null || tmux capture-pane -ep -t {1}" \
  --bind="ctrl-o:execute-silent(bash '$JUNBAN_SCRIPTS/switch.sh' --open {1})" \
  --preview-window='down,55%,border-top' \
  --color='bg+:#2a2f3a,hl:#e5c07b,hl+:#e5c07b,pointer:#61afef,prompt:#61afef,header:#5c6370')
[ -n "$sel" ] && go_to "$(printf '%s' "$sel" | cut -f1)"
exit 0
