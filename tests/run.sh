#!/usr/bin/env bash
# Runs against a throwaway tmux server; never touches yours.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/scripts"
WORK=$(mktemp -d)
trap 'tmux kill-server 2>/dev/null; rm -rf "$WORK"' EXIT
unset TMUX TMUX_PANE
export TMUX_TMPDIR="$WORK" HOME="$WORK/home" LANG=C.UTF-8
mkdir -p "$HOME/.claude/sessions"
cd "$WORK" || exit 1   # not inside a git repo, or every test window would share one tree

pass=0; fail=0
ok()   { pass=$((pass + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  \033[31m✗\033[0m %s\n      got: %s\n' "$1" "$2"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "'$2' (want '$3')"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "$2" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "$2" ;; *) ok "$1" ;; esac; }

printf "set -g base-index 1\n" > "$WORK/tmux.conf"
tmux -f "$WORK/tmux.conf" new -d -s s -n one -x 160 -y 40
tmux new-window -d -t s:2 -n two
tmux new-window -d -t s:3 -n three
p1=$(tmux display -p -t s:1 '#{pane_id}'); p2=$(tmux display -p -t s:2 '#{pane_id}'); p3=$(tmux display -p -t s:3 '#{pane_id}')
st()  { TMUX_PANE=$1 bash "$S/state.sh" "$2" <<<"${3:-}"; }
get() { tmux display -p -t "$1" "#{$2}"; }

echo "plugin"
bash "$ROOT/junban.tmux"
eq  "guide line enabled"            "$(tmux show -gv status)" "2"
# list-keys with a key argument prints nothing on tmux 3.7, so search the table
has "Alt+a bound"                   "$(tmux list-keys -T root | grep -F ' M-a ')" "jump.sh"
has "prefix a bound"                "$(tmux list-keys -T prefix | grep -E ' a +run-shell')" "jump.sh"
has "badge in window format"        "$(tmux show -gv window-status-format)" "@junban-badge"

echo "state"
st "$p1" running '{"prompt":"Refactor the billing\n  module please"}'
eq  "running recorded"              "$(get s:1 @junban)" "running"
eq  "prompt recorded, whitespace folded" "$(get s:1 @junban_prompt)" "Refactor the billing module please"
st "$p2" waiting '{}'
eq  "waiting recorded"              "$(get s:2 @junban)" "waiting"
st "$p3" "done" '{}'
eq  "done stays when nobody watches" "$(get s:3 @junban)" "done"
st "$p1" clear
eq  "clear removes state"           "$(get s:1 @junban)" ""
TMUX_PANE="" bash "$S/state.sh" "done" </dev/null; eq "no pane → exit 0" "$?" "0"
TMUX_PANE=$p1 bash "$S/state.sh" bogus </dev/null; eq "unknown state → exit 0" "$?" "0"
eq  "unknown state ignored"         "$(get s:1 @junban)" ""

echo "jump order"
tmux set -w -t s:2 @junban waiting \; set -w -t s:2 @junban_ts 200
tmux set -w -t s:3 @junban waiting \; set -w -t s:3 @junban_ts 100
tmux set -w -t s:1 @junban "done"    \; set -w -t s:1 @junban_ts 50
tmux select-window -t s:1
eq  "longest-waiting first"         "$(JUNBAN_DRY_RUN=1 bash "$S/jump.sh")" "s:3"
tmux set -w -t s:3 @junban idle \; set -w -t s:2 @junban idle
tmux select-window -t s:2
eq  "done when nobody waits"        "$(JUNBAN_DRY_RUN=1 bash "$S/jump.sh")" "s:1"

echo "status"
tmux set -w -t s:2 @junban waiting \; set -w -t s:3 @junban running \; set -w -t s:3 @junban_ts "$(date +%s)"
sum=$(bash "$S/summary.sh")
has "summary counts waiting"        "$sum" "✋1"
has "summary counts done"           "$sum" "✓1"
has "summary counts running"        "$sum" "●1"
has "guide shows waiting banner"    "$(bash "$S/hints.sh")" "1 waiting on you"
has "guide names the jump key"      "$(bash "$S/hints.sh")" "Alt+a to jump"
tmux set -g @junban-lang ja
has "guide in Japanese"             "$(bash "$S/hints.sh")" "返事待ち"
tmux set -g @junban-lang th
has "guide in Thai"                 "$(bash "$S/hints.sh")" "รอคุณตอบ"
tmux set -gu @junban-lang
tmux set -w -t s:2 @junban idle \; set -w -t s:1 @junban idle
has "guide lists keys when calm"    "$(bash "$S/hints.sh")" "Alt+f"
tmux set -g @junban-key-jump M-j
has "guide follows remapped keys"   "$(bash "$S/hints.sh")" "Alt+j"
tmux set -gu @junban-key-jump

echo "naming"
# windows created with -n start hand-named; make 1 and 3 look like plain new windows
tmux set -w -t s:1 automatic-rename on \; set -w -t s:3 automatic-rename on
nm() { TMUX_PANE=$1 python3 "$S/name.py" <<<"$2"; }
nm "$p1" '{"prompt":"Fix the flaky login test on CI"}'
eq  "renamed from prompt"           "$(get s:1 window_name)" "Fix the flaky login test"
nm "$p1" '{"prompt":"ok"}'
eq  "short reply keeps name"        "$(get s:1 window_name)" "Fix the flaky login test"
nm "$p1" '{"prompt":"進めて"}'
eq  "Japanese filler keeps name"    "$(get s:1 window_name)" "Fix the flaky login test"
nm "$p1" '{"prompt":"/compact please do it now"}'
eq  "slash command ignored"         "$(get s:1 window_name)" "Fix the flaky login test"
tmux rename-window -t s:2 mine \; set -w -t s:2 automatic-rename off
nm "$p2" '{"prompt":"Something completely different"}'
eq  "hand-named window untouched"   "$(get s:2 window_name)" "mine"
tmux set -g @junban-rename off
nm "$p3" '{"prompt":"Should not rename this window"}'
hasnt "rename off respected"       "$(get s:3 window_name)" "Should not"
tmux set -gu @junban-rename

echo "self-heal"
tmux respawn-pane -k -t s:1 'sleep 600'   # stands in for the agent process
wid=$(tmux display -p -t s:1 '#{window_id}'); ppid1=$(tmux display -p -t s:1 '#{pane_pid}')
tmux set -w -t s:1 @junban running \; set -w -t s:1 @junban_ts 1000
printf '{"pid":%d,"tmux":"s:%s.%s","status":"busy","statusUpdatedAt":%d}' "$ppid1" "$wid" "$p1" 2000000 \
  > "$HOME/.claude/sessions/$$.json"
python3 "$S/heal.py"
eq  "busy session left running"     "$(get s:1 @junban)" "running"
printf '{"pid":%d,"tmux":"s:%s.%s","status":"idle","statusUpdatedAt":%d}' "$ppid1" "$wid" "$p1" 2000000 \
  > "$HOME/.claude/sessions/$$.json"
python3 "$S/heal.py"
eq  "Esc-interrupted turn healed"   "$(get s:1 @junban)" "idle"
tmux set -w -t s:1 @junban running \; set -w -t s:1 @junban_ts 3000
python3 "$S/heal.py"
eq  "older idle status ignored"     "$(get s:1 @junban)" "running"
printf '{"pid":%d,"tmux":"s:%s.%s","status":"idle","statusUpdatedAt":%d}' $$ "$wid" "$p1" 9000000 \
  > "$HOME/.claude/sessions/$$.json"
python3 "$S/heal.py"
eq  "same pane id, other process → ignored" "$(get s:1 @junban)" "running"
rm "$HOME/.claude/sessions/$$.json"
tmux set -w -t s:2 @junban running \; set -w -t s:2 @junban_ts 1
python3 "$S/heal.py"
eq  "agent exited to shell → cleared" "$(get s:2 @junban)" "idle"

echo "shared trees and parked agents"
tmux kill-server; sleep 0.2
repo="$WORK/repo"; git init -q "$repo"; mkdir -p "$repo/sub"
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$repo" worktree add -q "$WORK/wt" -b side
tmux -f "$WORK/tmux.conf" new -d -s u -n a -c "$repo" -x 160 -y 40
bash "$ROOT/junban.tmux"
tmux new-window -d -t u:2 -n b -c "$repo/sub"
tmux new-window -d -t u:3 -n c -c "$WORK/wt"
tmux new-window -d -t u:4 -n d -c "$HOME"
tmux new-window -d -t u:5 -n e -c "$repo"     # a plain shell: no agent registered
for w in 1 2 3 4; do tmux set -w -t "u:$w" @junban idle \; set -w -t "u:$w" @junban_ts "$(date +%s)"; done
sleep 0.3   # let pane_current_path settle
scan() { tmux set -g @junban-scan-at 0; python3 "$S/scan.py"; }
scan
eq  "same tree flagged"             "$(get u:1 @junban_shared)" "2"
eq  "subdir counts as same tree"    "$(get u:2 @junban_shared)" "2"
eq  "separate worktree not flagged" "$(get u:3 @junban_shared)" ""
eq  "\$HOME never flagged"          "$(get u:4 @junban_shared)" ""
eq  "shell without agent ignored"   "$(get u:5 @junban_shared)" ""
has "guide names the sharing windows" "$(bash "$S/hints.sh")" "a · b"
has "badge shows ⚠"                 "$(tmux show -gv @junban-badge)" "@junban_shared"
eq  "new agent here → worktree"     "$(JUNBAN_DRY_RUN=1 bash "$S/new.sh" "$repo")" "claude --worktree"
eq  "new agent in free tree → plain" "$(JUNBAN_DRY_RUN=1 bash "$S/new.sh" "$WORK")" "claude"
tmux set -g @junban-new-worktree off
eq  "worktree switch can be off"    "$(JUNBAN_DRY_RUN=1 bash "$S/new.sh" "$repo")" "claude"
tmux set -gu @junban-new-worktree
tmux set -g @junban-agent-cmd codex
eq  "other agents start plain"      "$(JUNBAN_DRY_RUN=1 bash "$S/new.sh" "$repo")" "codex"
tmux set -gu @junban-agent-cmd
tmux set -w -t u:2 -u @junban; scan
eq  "flag clears when one leaves"   "$(get u:1 @junban_shared)" ""
tmux set -w -t u:3 @junban_ts $(( $(date +%s) - 30 * 3600 ))
tmux set -w -t u:4 @junban running \; set -w -t u:4 @junban_ts 1
scan
eq  "idle for 30h → parked"         "$(get u:3 @junban_stale)" "30"
eq  "running is never parked"       "$(get u:4 @junban_stale)" ""
has "guide counts parked"           "$(bash "$S/hints.sh")" "1 agents untouched"
tmux set -g @junban-scan-at "$(date +%s)"; tmux set -w -t u:3 @junban_ts "$(date +%s)"
python3 "$S/scan.py"
eq  "scan is throttled"             "$(get u:3 @junban_stale)" "30"
scan
eq  "parked clears on activity"     "$(get u:3 @junban_stale)" ""

echo "wait meter"
unset XDG_STATE_HOME
log="$HOME/.local/state/junban/waits.tsv"; rm -f "$log"
tmux new-window -d -t u:6 -n m; pm=$(tmux display -p -t u:6 '#{pane_id}')
now=$(date +%s)
st "$pm" waiting '{}'; tmux set -w -t u:6 @junban_ts $((now - 90))
st "$pm" running '{}'
eq  "answering logs the wait"       "$(cut -f3,4 "$log")" "waiting	u:m"
eq  "wait length recorded"          "$(awk -F'\t' '{print $2 - $1}' "$log")" "90"
st "$pm" "done" '{}'; tmux set -w -t u:6 @junban_ts $((now - 30))
tmux select-window -t u:6; sleep 0.5
eq  "opening a ✓ window clears it"  "$(get u:6 @junban)" "idle"
eq  "…and logs it as a done wait"   "$(tail -n1 "$log" | cut -f3)" "done"
lines=$(wc -l < "$log")
st "$pm" running '{}'; st "$pm" "done" '{}'
tmux set -w -t u:6 @junban "done"; st "$pm" clear
eq  "closing an agent logs nothing" "$(wc -l < "$log" | tr -d ' ')" "$lines"
printf '%s\t%s\twaiting\tu:old\n' $((now - 9 * 86400)) $((now - 9 * 86400 + 60)) >> "$log"
printf '%s\t%s\tdone\tu:night\n' $((now - 20000)) "$now" >> "$log"
line=$(bash "$S/stats.sh" --line)
eq  "today: count excludes old days" "$(cut -f3 <<<"$line")" "$((lines + 1))"
# the ✓ wait is ~30s (the select above takes a moment), so allow a few seconds
near() { if [ "$2" -ge "$3" ] && [ "$2" -le $(($3 + 3)) ]; then ok "$1"; else bad "$1" "$2 (want ~$3)"; fi; }
near "one long wait capped at 60m"  "$(cut -f1 <<<"$line")" "$((90 + 30 + 3600))"
tmux set -g @junban-meter-cap 10
near "cap is configurable"          "$(bash "$S/stats.sh" --line | cut -f1)" "$((90 + 30 + 600))"
tmux set -gu @junban-meter-cap
tmux set -w -t u:1 @junban_shared ""; for w in 1 2 3 4; do tmux set -w -t "u:$w" -u @junban_stale; done
tmux set -w -t u:1 -u @junban_shared
has "guide shows the meter"         "$(bash "$S/hints.sh")" "kept waiting 1h"
tmux set -g @junban-lang ja
has "meter in Japanese"             "$(bash "$S/hints.sh")" "今日の待たせ時間 1時間"
tmux set -gu @junban-lang
tmux set -g @junban-meter off
hasnt "meter can be turned off"     "$(bash "$S/hints.sh")" "kept waiting"
tmux set -gu @junban-meter
rep=$(bash "$S/stats.sh" 7)
has "report lists today's windows"  "$rep" "u:night"
hasnt "report skips older days"     "$rep" "u:old"

echo "theme off"
tmux kill-server; sleep 0.2
tmux -f "$WORK/tmux.conf" new -d -s t
tmux set -g @junban-theme off
tmux setw -g window-status-format "MINE #W"
bash "$ROOT/junban.tmux"; bash "$ROOT/junban.tmux"
f=$(tmux show -gv window-status-format)
has "user format kept"              "$f" "MINE #W"
eq  "badge spliced exactly once"    "$(grep -o junban-badge <<<"$f" | wc -l | tr -d ' ')" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
