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
plain() { bash "$S/hints.sh" "$@" | sed 's/#\[[^]]*\]//g'; }

echo "plugin"
bash "$ROOT/junban.tmux"
eq  "three status rows by default"  "$(tmux show -gv status)" "3"
# list-keys with a key argument prints nothing on tmux 3.7, so search the table
has "Alt+a bound"                   "$(tmux list-keys -T root | grep -F ' M-a ')" "jump.sh"
has "prefix a bound"                "$(tmux list-keys -T prefix | grep -E ' a +run-shell')" "jump.sh"
has "Alt+w asks before closing"     "$(tmux list-keys -T root | grep -F ' M-w ')" "confirm-before"
has "…naming the window"            "$(tmux list-keys -T root | grep -F ' M-w ')" "#W"
has "badge in window format"        "$(tmux show -gv window-status-format)" "@junban-badge"
# Alt+1 is the first tab: a session whose tabs start at 0 is renumbered from 1.
tmux set -g base-index 0 \; set -g renumber-windows off
tmux new -d -s z0 \; new-window -d -t z0
bash "$ROOT/junban.tmux"
eq  "tabs renumbered from 1"        "$(tmux list-windows -t z0 -F '#I' | tr '\n' ' ')" "1 2 "
tmux new-window -d -t z0 \; kill-window -t z0:1
eq  "closing a tab closes the gap"  "$(tmux list-windows -t z0 -F '#I' | tr '\n' ' ')" "1 2 "
tmux kill-session -t z0

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
has "keys row lists keys when calm" "$(bash "$S/hints.sh" 0 2)" "Alt+f"
has "keys row lists window moves"   "$(plain 0 2)" "Alt+f all agents  Alt+[ ] prev / next  Alt+w close  Alt+n"
tmux set -g @junban-nav-keys off
hasnt "…not when nav keys are off"  "$(plain 0 2)" "Alt+[ ]"
hasnt "…nor Alt+w"                  "$(plain 0 2)" "Alt+w"
tmux set -gu @junban-nav-keys
tmux set -g @junban-lang ja
nav=$(plain 0 2); nav=${nav//[^ -~]/xx}
if [ ${#nav} -le 110 ]; then ok "Japanese keys row fits 110 columns"; else bad "Japanese keys row fits 110 columns" "${#nav} cols"; fi
tmux set -gu @junban-lang
hasnt "single guide row has no keys" "$(bash "$S/hints.sh")" "Alt+n"
tmux set -g @junban-key-jump M-j
has "guide follows remapped keys"   "$(bash "$S/hints.sh" 0 2)" "Alt+j"
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
tmux set -w -t s:2 @junban running \; set -w -t s:2 @junban_ts 1 \; set -p -t "$p2" @junban_cwd /gone
python3 "$S/heal.py"
eq  "agent exited to shell → cleared" "$(get s:2 @junban)" "idle"
eq  "…and its dir forgotten"        "$(tmux display -p -t "$p2" '#{@junban_cwd}')" ""

echo "Alt+n worktrees and parked agents"
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
tree() { python3 "$S/scan.py" --tree "$1"; }
eq  "agents in a tree counted"      "$(tree "$repo")" "2"
eq  "subdir counts as same tree"    "$(tree "$repo/sub")" "2"
eq  "separate worktree counted apart" "$(tree "$WORK/wt")" "1"
eq  "\$HOME never counted"          "$(tree "$HOME")" "0"
# Sharing a tree is how people work, so it is not flagged (0.3.8).
tmux set -w -t u:1 @junban_shared 2; scan
eq  "old shared flag cleared"       "$(get u:1 @junban_shared)" ""
hasnt "no shared badge"             "$(tmux show -gv @junban-badge)" "@junban_shared"
# ⚠ and ⏱ are one column to tmux but drawn as two-column emoji by xterm.js
# (VS Code), which clips them in half.
hasnt "no ⚠ in the badge"           "$(tmux show -gv @junban-badge)" "⚠"
hasnt "no ⏱ on the guide line"      "$(bash "$S/hints.sh")" "⏱"
# Alt+n's `bash -c "claude --worktree; …"` keeps pane_current_path at the repo
# root while claude works in its worktree; its hooks run there.
git -C "$repo" worktree add -q "$WORK/wt2" -b side2
tmux new-window -d -t u:9 -n f -c "$repo"; p9=$(tmux display -p -t u:9 '#{pane_id}')
(cd "$WORK/wt2" && TMUX_PANE=$p9 bash "$S/state.sh" idle </dev/null)
eq  "hook dir beats pane path"      "$(tree "$repo")" "2"
TMUX_PANE=$p9 bash "$S/state.sh" running <<<"{\"cwd\":\"$repo\"}"
eq  "payload cwd recorded"          "$(tree "$repo")" "3"
TMUX_PANE=$p9 bash "$S/state.sh" running <<<"{\"cwd\":\"$WORK/wt2\"}"
eq  "moving to a worktree counts apart" "$(tree "$repo")" "2"
eq  "agent dir kept per pane"       "$(tmux display -p -t "$p9" '#{@junban_cwd}')" "$WORK/wt2"
TMUX_PANE=$p9 bash "$S/state.sh" clear </dev/null
eq  "closing forgets the agent dir" "$(tmux display -p -t "$p9" '#{@junban_cwd}')" ""
tmux kill-window -t u:9
eq  "new agent here → worktree"     "$(JUNBAN_DRY_RUN=1 bash "$S/new.sh" "$repo")" "claude --worktree"
eq  "new agent in free tree → plain" "$(JUNBAN_DRY_RUN=1 bash "$S/new.sh" "$WORK")" "claude"
tmux set -g @junban-new-worktree off
eq  "worktree switch can be off"    "$(JUNBAN_DRY_RUN=1 bash "$S/new.sh" "$repo")" "claude"
tmux set -gu @junban-new-worktree
tmux set -g @junban-agent-cmd codex
eq  "other agents start plain"      "$(JUNBAN_DRY_RUN=1 bash "$S/new.sh" "$repo")" "codex"
tmux set -gu @junban-agent-cmd
tmux set -w -t u:2 -u @junban
eq  "an agent leaving frees the tree" "$(tree "$repo")" "1"
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
# Timings cross a second boundary now and then, so allow a few seconds.
near() { if [ "$2" -ge "$3" ] && [ "$2" -le $(($3 + 3)) ]; then ok "$1"; else bad "$1" "$2 (want ~$3)"; fi; }
unset XDG_STATE_HOME
log="$HOME/.local/state/junban/waits.tsv"; rm -f "$log"
tmux new-window -d -t u:6 -n m; pm=$(tmux display -p -t u:6 '#{pane_id}')
now=$(date +%s)
st "$pm" waiting '{}'; tmux set -w -t u:6 @junban_ts $((now - 90))
st "$pm" running '{}'
eq  "answering logs the wait"       "$(cut -f3,4 "$log")" "waiting	u:m"
near "wait length recorded"         "$(awk -F'\t' '{print $2 - $1}' "$log")" "90"

st "$pm" "done" '{}'; tmux set -w -t u:6 @junban_ts $((now - 30))
tmux select-window -t u:6; sleep 0.5
eq  "opening a ✓ window clears it"  "$(get u:6 @junban)" "idle"
eq  "…and logs it as a done wait"   "$(tail -n1 "$log" | cut -f3)" "done"
lines=$(wc -l < "$log" | tr -d " ")
st "$pm" running '{}'; st "$pm" "done" '{}'
tmux set -w -t u:6 @junban "done"; st "$pm" clear
eq  "closing an agent logs nothing" "$(wc -l < "$log" | tr -d ' ')" "$lines"
printf '%s\t%s\twaiting\tu:old\n' $((now - 9 * 86400)) $((now - 9 * 86400 + 60)) >> "$log"
printf '%s\t%s\tdone\tu:night\n' $((now - 20000)) "$now" >> "$log"
line=$(bash "$S/stats.sh" --line)
eq  "today: count excludes old days" "$(cut -f3 <<<"$line")" "$((lines + 1))"
near "one long wait capped at 60m"  "$(cut -f1 <<<"$line")" "$((90 + 30 + 3600))"
tmux set -g @junban-meter-cap 10
near "cap is configurable"          "$(bash "$S/stats.sh" --line | cut -f1)" "$((90 + 30 + 600))"
tmux set -gu @junban-meter-cap
for w in 1 2 3 4; do tmux set -w -t "u:$w" -u @junban_stale; done
has "guide shows the meter"         "$(bash "$S/hints.sh")" "kept waiting 1h"
has   "calm row 1 is today's wait"  "$(bash "$S/hints.sh" 110 1)" "kept waiting 1h"
hasnt "…without the keys"           "$(bash "$S/hints.sh" 110 1)" "Alt+f"
has   "calm row 2 is the keys"      "$(bash "$S/hints.sh" 110 2)" "Alt+f"
calm=$(plain 110 1); calm=${calm//[✓·→…]/x}; calm=${calm//[^ -~]/xx}
if [ ${#calm} -le 110 ]; then ok "calm row 1 fits 110 columns"; else bad "calm row 1 fits 110 columns" "${#calm} cols"; fi
hasnt "…without the wait"           "$(bash "$S/hints.sh" 110 2)" "kept waiting"
tmux set -g @junban-lang ja
has "meter in Japanese"             "$(bash "$S/hints.sh")" "今日の待ち時間 1時間"
tmux set -gu @junban-lang
tmux set -g @junban-meter off
hasnt "meter can be turned off"     "$(bash "$S/hints.sh")" "kept waiting 1h"
tmux set -gu @junban-meter
rep=$(bash "$S/stats.sh" 7)
has "report lists today's windows"  "$rep" "u:night"
hasnt "report skips older days"     "$rep" "u:old"

# shellcheck disable=SC2012  # ls -l is the portable way to read modes (stat differs on macOS)
eq  "wait log is private"           "$(ls -ld "$log" | cut -c1-10)" "-rw-------"
# shellcheck disable=SC2012
eq  "…and so is its folder"         "$(ls -ld "${log%/*}" | cut -c1-10)" "drwx------"

echo "graphs and mascot"
# Last week: 6 waits of 4 min. This week: 3 min on days 1-3, 2 min five times today.
: > "$log"
for d in 8 9 10 11 12 13; do e=$((now - d * 86400)); printf '%s\t%s\twaiting\tu:a\n' $((e - 240)) "$e" >> "$log"; done
for d in 0 0 0 0 0; do printf '%s\t%s\tdone\tu:b\n' $((now - 125)) $((now - 5)) >> "$log"; done
for d in 1 2 3; do e=$((now - d * 86400)); printf '%s\t%s\tdone\tu:b\n' $((e - 180)) "$e" >> "$log"; done
rep=$(bash "$S/stats.sh" 7)
has "bar for each day"              "$rep" "████████████████"
has "this week against last"        "$rep" "median reply 4m00s → 2m00s (-50%)"
has "personal best"                 "$rep" "Personal best: $(date +%m/%d), median reply 2m00s"
has "streak within the goal"        "$rep" "days in a row with a median reply under 5 min"
has "mascot cheers a quicker week"  "$rep" '[◠ ◠]'
has "…and says why"                 "$rep" "a new personal best today! 50% quicker"
eq  "trend needs 5 waits before"    "$(bash "$S/stats.sh" --line | cut -f4)" "-"
for d in 4 5; do e=$((now - d * 86400)); printf '%s\t%s\tdone\tu:b\n' $((e - 180)) "$e" >> "$log"; done
eq  "trend: today vs last 7 days"   "$(bash "$S/stats.sh" --line | cut -f4)" "-33%"
has "guide says the trend in words"  "$(bash "$S/hints.sh")" "(33% quicker than the last 7 days)"
for d in 0 0 0 0 0 0; do printf '%s\t%s\tdone\tu:b\n' $((now - 605)) $((now - 5)) >> "$log"; done
has "…and when replies got slower"  "$(bash "$S/hints.sh")" "median reply 10m (233% slower than the last 7 days)"
hasnt "…with no bare sign"          "$(bash "$S/hints.sh")" "+233%"
tmux set -w -t u:6 @junban waiting
has "mascot calls when someone waits" "$(bash "$S/summary.sh")" "[▮ ▮]"
tmux set -w -t u:6 -u @junban
tmux set -g @junban-mascot off
hasnt "mascot can be turned off"     "$(bash "$S/summary.sh")" "▮"
hasnt "…in the report too"           "$(bash "$S/stats.sh" 7)" "[◠ ◠]"
tmux set -gu @junban-mascot

echo "timeline"
slog="$HOME/.local/state/junban/states.tsv"; rm -f "$slog"
tmux new-window -d -t u:7 -n tl; pt=$(tmux display -p -t u:7 '#{pane_id}')
tkey=$(tmux display -p -t u:7 '#{pid}:#{window_id}')
st "$pt" running '{}'; st "$pt" waiting '{}'; st "$pt" waiting '{}'
eq  "each change logged once"       "$(cut -f2 "$slog" | tr '\n' ' ')" "running waiting "
eq  "keyed by server and window"    "$(cut -f3,4 "$slog" | tail -n 1)" "$tkey	u:tl"
eq  "log kept to yourself"          "$(stat -c %a "$slog" 2>/dev/null || stat -f %Lp "$slog")" "600"
st "$pt" clear
eq  "closing the agent ends its row" "$(tail -n 1 "$slog" | cut -f2)" "clear"
st "$pt" clear
eq  "…once"                         "$(grep -c clear "$slog")" "1"
# Yesterday, two windows: A works 10:00-11:00 then waits 5 h (counts 1 h),
# B works 10:30-11:30 under another name it was renamed from.
# Yesterday's midnight from one clock reading (separate date calls can straddle a second).
n2=$(date +%s); mid=$(python3 -c 'import datetime as d; print(int((d.datetime.now().replace(hour=0, minute=0, second=0, microsecond=0) - d.timedelta(days=1)).timestamp()))')
{
  printf '%s\trunning\t9:@1\tu:alpha\n'  $((mid + 36000))
  printf '%s\tdone\t9:@1\tu:alpha\n'     $((mid + 39600))
  printf '%s\tidle\t9:@1\tu:alpha\n'     $((mid + 57600))
  printf '%s\trunning\t9:@2\tu:old-name\n' $((mid + 37800))
  printf '%s\tidle\t9:@2\tu:beta\n'      $((mid + 41400))
} > "$slog"
tl=$(COLUMNS=100 bash "$S/timeline.sh" 1)
has "a row per window"              "$tl" "u:alpha"
has "…named as it was last"         "$tl" "u:beta"
hasnt "…not twice"                  "$tl" "old-name"
has "running time is the union"     "$tl" "agents working 1h30m"
has "waits capped like the meter"   "$tl" "waited on you 1h00m"
has "busiest moment"                "$tl" "up to 2 at once"
has "first to last activity"        "$tl" "Active 10:00–12:00"
has "hour marks"                    "$tl" "10"
has "nothing that day"              "$(COLUMNS=100 bash "$S/timeline.sh" 3)" "Nothing recorded"
# Today: a window still open runs on to now; one that is gone stops at its last change.
if [ $((n2 - mid - 86400)) -gt 700 ]; then
  printf '%s\trunning\t%s\tu:tl\n' $((now - 600)) "$tkey" >> "$slog"
  printf '%s\trunning\t9:@9\tu:gone\n' $((now - 600)) >> "$slog"
  tl=$(COLUMNS=100 bash "$S/timeline.sh")
  has "open window runs to now"     "$tl" "agents working 10m"
  hasnt "closed window drops out"   "$tl" "u:gone"
fi
has "prefix T opens it"             "$(tmux list-keys -T prefix | grep -E ' T +display-popup')" "timeline.sh"
has "doctor counts the log"         "$(bash "$S/doctor.sh")" "states.tsv 7 rows"
tmux kill-window -t u:7

echo "recap"
tmux new-window -d -t u:7 -n r; pr=$(tmux display -p -t u:7 '#{pane_id}')
rc() { TMUX_PANE=$pr python3 "$S/recap.py" "$1" <<<"$2"; }
# shellcheck disable=SC2016  # literal backticks: markdown to strip
rc ask '{"tool_input":{"questions":[{"question":"Merge into **main** or `release`?"}]}}'
eq  "ask: the question, markdown gone" "$(get u:7 @junban_recap)" "Merge into main or release?"
rc notify '{"message":"Claude needs your permission to use Bash"}'
eq  "notify: the permission asked"  "$(get u:7 @junban_recap)" "Claude needs your permission to use Bash"
tr="$WORK/t.jsonl"
{ echo '{"type":"user","message":{"content":"go"}}'
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Earlier reply"}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}'
  # shellcheck disable=SC2028  # \\n is JSON, not an escape for echo
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"## Result\n\n**All 66 tests pass**; PR #12 opened.\n\nDetails…"}]}}'
} > "$tr"
tmux set -w -t u:7 @junban "done" \; set -w -t u:7 @junban_prompt "fix the flaky test"
done_log="$HOME/.local/state/junban/done.tsv"; rm -f "$done_log"
rc "done" "{\"transcript_path\":\"$tr\"}"
eq  "done: first real line of the last reply" "$(get u:7 @junban_recap)" "All 66 tests pass; PR ＃12 opened."
eq  "done: logged with window and prompt" "$(cut -f2- "$done_log")" "u:r	fix the flaky test	All 66 tests pass; PR ＃12 opened."
rc "done" '{"last_assistant_message":"Blocked: need the API key for staging"}'
eq  "done: payload message preferred" "$(get u:7 @junban_recap)" "Blocked: need the API key for staging"
tmux set -w -t u:7 @junban running
rc "done" '{"last_assistant_message":"Too late, you moved on"}'
eq  "late recap after a new prompt dropped" "$(get u:7 @junban_recap)" "Blocked: need the API key for staging"
st "$pr" running '{"prompt":"now deploy it"}'
eq  "new prompt clears the recap"   "$(get u:7 @junban_recap)" ""
tmux set -g @junban-recap off
rc ask '{"tool_input":{"questions":[{"question":"Should not appear"}]}}'
eq  "recap off respected"           "$(get u:7 @junban_recap)" ""
tmux set -gu @junban-recap
# banner names what the next window wants
tmux set -w -t u:7 @junban "done" \; set -w -t u:7 @junban_ts 5 \; set -w -t u:7 @junban_recap "tests pass"
has "✓ banner carries the recap"    "$(bash "$S/hints.sh")" "r: tests pass"
tmux set -w -t u:6 @junban waiting \; set -w -t u:6 @junban_ts 9 \; set -w -t u:6 @junban_recap "which branch?"
has "✋ beats ✓ in the banner"       "$(bash "$S/hints.sh")" "m: which branch?"
# fitted to the client width: the recap is cut with …
tmux set -w -t u:6 @junban_recap "はい、英語圏の人には英語で表示されます。いま日本語なのは設定のためです"
has   "narrow terminal cuts the recap with …" "$(plain 70)" "…"
has   "banner survives a narrow terminal" "$(plain 50)" "Alt+a to jump"
long=$(plain 70); long=${long//[✓·→…]/x}; long=${long//[^ -~]/xx}
if [ ${#long} -le 70 ]; then ok "cut line fits the width"; else bad "cut line fits the width" "${#long} cols"; fi
has   "C locale still counts characters" "$(LC_ALL=C plain 70)" "…"
# three rows: the banner (or today's wait) on row 1, the keys on row 2
has   "row 1 carries the banner"      "$(plain 120 1)" "Alt+a to jump"
has   "wide row 1: wait right of the banner" "$(plain 200 1)" "kept waiting"
hasnt "narrow row 1: the banner wins" "$(plain 80 1)" "kept waiting"
has   "row 2 keeps the keys under a banner" "$(plain 200 2)" "Alt+f"
hasnt "no tips on any row"            "$(plain 400 1)$(plain 400 2)$(plain 400)" "💡"
has   "banner row takes a wash of its color" "$(bash "$S/hints.sh" 120 1)" "#[fill=#613b42]"
tmux set -g @junban-tint 0
has   "tint 0 leaves the row plain"   "$(bash "$S/hints.sh" 120 1)" "#[fill=#1e2127]"
tmux set -gu @junban-tint
tmux set -gu @junban-guide-lines; bash "$ROOT/junban.tmux"
eq  "unset → three status rows"      "$(tmux show -gv status)" "3"
has "third row runs the guide"      "$(tmux show -gv 'status-format[2]')" "hints.sh #{client_width} 2"
# Prefix down: the keys row lists what can follow it. Evaluate the branch as if pressed.
pressed() { tmux display -p "$(tmux show -gv "status-format[$1]" | sed 's/#{?client_prefix,/#{?#{==:a,a},/')" | sed 's/#\[[^]]*\]//g'; }
has   "prefix shows what follows it" "$(pressed 2)" "1-9 that window  n/p next / previous window  a next  f all agents"
hasnt "…instead of the guide"        "$(pressed 2)" "Alt+f"
tmux set -g @junban-lang ja; bash "$ROOT/junban.tmux"
has   "prefix hint in Japanese"      "$(pressed 2)" "a 次へ  f 一覧"
tmux set -gu @junban-lang
tmux set -g @junban-prefix-keys off; bash "$ROOT/junban.tmux"
hasnt "prefix keys off → only tmux's own" "$(pressed 2)" "a next"
tmux set -gu @junban-prefix-keys
tmux set -g @junban-guide-lines 2; bash "$ROOT/junban.tmux"
eq  "back to two rows"              "$(tmux show -gv status)" "2"
has "one guide row: prefix hint too" "$(pressed 1)" "f all agents"
hasnt "our third row removed"       "$(tmux show -gv 'status-format[2]')" "hints.sh"
tmux set -w -t u:6 @junban idle
# notifications: the ✓ one comes from recap.py, with the line
notes="$WORK/notes"; : > "$notes"
tmux set -g @junban-notify-cmd "cat >> $notes"
tmux set -w -t u:7 @junban running
st "$pr" "done" '{}'; sleep 0.3
eq  "state.sh leaves ✓ to recap"     "$(cat "$notes")" ""
rc "done" '{"last_assistant_message":"Deployed to staging"}'
eq  "recap sends ✓ with the line"   "$(cat "$notes")" "✓ r: Deployed to staging"
tmux set -gu @junban-notify-cmd
# with a namer model set, the line comes from the model
# A one-shot stub model. It says when it is listening (a cold python3 on a CI
# runner can take longer than any fixed sleep) and gives up after 20s, so a
# request that never comes cannot hang the suite.
ready="$WORK/stub-ready"; rm -f "$ready"
python3 - "$ready" <<'PY' &
import http.server, json, socketserver, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        ok = "final message" in body["messages"][0]["content"] and body["options"]["num_predict"] == 48
        out = json.dumps({"message": {"content": "Model: 3 files fixed" if ok else "wrong prompt"}}).encode()
        self.send_response(200); self.end_headers(); self.wfile.write(out)
    def log_message(self, *a): pass
# socketserver, not HTTPServer: HTTPServer looks up its own hostname on bind,
# which takes seconds on macOS runners.
srv = socketserver.TCPServer(("127.0.0.1", 0), H)
srv.timeout = 20
open(sys.argv[1], "w").write(str(srv.server_address[1]))
srv.handle_request()
PY
stub=$!
for _ in $(seq 100); do [ -s "$ready" ] && break; sleep 0.1; done
port=$(cat "$ready" 2>/dev/null)
tmux set -g @junban-namer-url "http://127.0.0.1:$port" \; set -g @junban-namer-model stub \; set -w -t u:7 @junban "done"
# no_proxy: urllib honours system proxy settings (macOS runners), never wanted for a local stub.
no_proxy='*' NO_PROXY='*' rc "done" '{"last_assistant_message":"Long reply about fixing three files"}'
eq  "model writes the recap"        "$(get u:7 @junban_recap)" "Model: 3 files fixed"
tmux set -gu @junban-namer-url \; set -gu @junban-namer-model
kill "$stub" 2>/dev/null; wait "$stub" 2>/dev/null

echo "other agents"
tmux new-window -d -t u:8 -n x; px=$(tmux display -p -t u:8 '#{pane_id}')
hk() { TMUX_PANE=$px bash "$S/hook.sh" "$1" "$2" <<<"$3"; }
eq  "codex: hooks print nothing"    "$(hk codex SessionStart '{"source":"startup"}')" ""
eq  "codex SessionStart → idle"     "$(get u:8 @junban)" "idle"
hk codex UserPromptSubmit '{"prompt":"migrate the billing tables"}' >/dev/null
eq  "codex prompt → running"        "$(get u:8 @junban)" "running"
eq  "…and the prompt is kept"       "$(get u:8 @junban_prompt)" "migrate the billing tables"
hk codex PermissionRequest '{"tool_name":"Bash","tool_input":{"command":"psql -c \"drop table t\""}}' >/dev/null; sleep 0.5
eq  "codex approval → waiting"      "$(get u:8 @junban)" "waiting"
eq  "…recap names the command"      "$(get u:8 @junban_recap)" 'Bash: psql -c "drop table t"'
hk codex PostToolUse '{"tool_name":"Bash"}' >/dev/null
eq  "approved → running again"      "$(get u:8 @junban)" "running"
hk codex Interrupt '{}' >/dev/null
eq  "Esc (Interrupt) → idle"        "$(get u:8 @junban)" "idle"
hk codex Stop '{"last_assistant_message":"Migration applied, 3 tables"}' >/dev/null; sleep 0.5
eq  "codex Stop → done"             "$(get u:8 @junban)" "done"
eq  "…with its recap"               "$(get u:8 @junban_recap)" "Migration applied, 3 tables"
hk codex SessionEnd '{}' >/dev/null
eq  "codex exit clears the badge"   "$(get u:8 @junban)" ""
eq  "gemini: hooks print JSON"      "$(hk gemini SessionStart '{"source":"startup"}')" "{}"
hk gemini BeforeAgent '{"prompt":"fix the flaky test"}' >/dev/null
eq  "gemini prompt → running"       "$(get u:8 @junban)" "running"
hk gemini Notification '{"notification_type":"ToolPermission","message":"Allow shell: rm -rf build?"}' >/dev/null; sleep 0.5
eq  "gemini permission → waiting"   "$(get u:8 @junban)" "waiting"
eq  "…recap is its message"         "$(get u:8 @junban_recap)" "Allow shell: rm -rf build?"
hk gemini Notification '{"notification_type":"ToolPermission","message":"Tool Confirm Shell Command requires execution","details":{"type":"exec","title":"Confirm Shell Command","command":"mkdir -p build/out","rootCommand":"mkdir"}}' >/dev/null; sleep 0.5
eq  "…or the command it will run"   "$(get u:8 @junban_recap)" "Shell: mkdir -p build/out"
hk gemini AfterAgent '{"prompt_response":"[no response text]"}' >/dev/null; sleep 0.5
eq  "gemini AfterAgent → done"      "$(get u:8 @junban)" "done"
eq  "no recap from an empty reply"  "$(get u:8 @junban_recap)" "Shell: mkdir -p build/out"
hk gemini SessionEnd '{}' >/dev/null
eq  "gemini exit clears the badge"  "$(get u:8 @junban)" ""

mkdir -p "$HOME/.codex"; printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"notify-me"}]}]}}' > "$HOME/.codex/hooks.json"
bash "$S/setup.sh" codex >/dev/null; bash "$S/setup.sh" codex >/dev/null
cx=$(cat "$HOME/.codex/hooks.json")
has "setup keeps your own hooks"    "$cx" "notify-me"
eq  "…and adds ours exactly once"   "$(grep -c 'hook.sh codex Stop' <<<"$cx")" "1"
has "setup: Codex timeouts in s"    "$cx" '"timeout": 5'
bash "$S/setup.sh" gemini >/dev/null
has "setup: Gemini timeouts in ms"  "$(cat "$HOME/.gemini/settings.json")" '"timeout": 5000'

echo "doctor"
tmux rename-window -t u:8 "acme-secret-client"
doc=$(bash "$S/doctor.sh")
has "doctor: plugin loaded"         "$doc" "ok    junban.tmux loaded"
has "doctor: badges found"          "$doc" "ok    badges in the window list"
has "doctor: a verdict"             "$doc" "result: "
hasnt "doctor: no window names"     "$doc" "acme-secret-client"
tmux set -g @junban-notify-cmd 'curl -d @- ntfy.sh/my-private-topic'
hasnt "doctor: hides secret options" "$(bash "$S/doctor.sh")" "my-private-topic"
tmux set -gu @junban-notify-cmd
tmux set -gu @junban-dir
has "doctor: says when not loaded"  "$(bash "$S/doctor.sh")" "FAIL  junban.tmux is not loaded"
tmux set -g @junban-dir "$ROOT"
has "help points at the doctor"     "$(bash "$S/help.sh" </dev/null | cat)" "doctor.sh"

echo "quoting"
qd="$WORK/a'; touch $WORK/PWNED; ' b"; mkdir -p "$qd"
tmux new-window -d -t u:9 -c "$qd"; tmux set -g @junban-agent-cmd true
tmux run -t u:9 "$(tmux list-keys -T root M-n | sed 's/.*run-shell -b "//; s/"$//')"; sleep 1
eq  "Alt+n: a quote in a path runs nothing" "$([ -e "$WORK/PWNED" ] && echo yes || echo no)" "no"
tmux set -gu @junban-agent-cmd

echo "VS Code windows"
# Real clients under script(1) so /proc/<client>/environ is genuine. Linux only.
if [ -r /proc/self/environ ] && command -v script >/dev/null 2>&1; then
  mkdir -p "$WORK/rc/remote-cli" "$WORK/a" "$WORK/real/proj" "$WORK/links"
  ln -s "$WORK/real/proj" "$WORK/links/proj"
  # shellcheck disable=SC2016  # $VSCODE_IPC_HOOK_CLI expands when the fake code runs
  printf '#!/bin/sh\necho "$VSCODE_IPC_HOOK_CLI $*" > "%s/raised"\n' "$WORK" > "$WORK/rc/remote-cli/code"
  chmod +x "$WORK/rc/remote-cli/code"
  tmux new -d -s proj -n agent -c "$WORK/real/proj"
  tmux new -d -s bare -n other
  tmux new -d -s vsa -n mine -c "$WORK/a"
  # attach_as SESSION PWD [TERM_PROGRAM] [IPC]
  attach_as() {
    (cd "$2" && sleep 60 | env TERM=xterm TERM_PROGRAM="${3:-}" VSCODE_IPC_HOOK_CLI="${4:-}" \
      PATH="$WORK/rc/remote-cli:$PATH" PWD="$2" script -qfec "tmux attach -t =$1" /dev/null) >/dev/null 2>&1 &
  }
  tty_of() { for _ in 1 2 3 4 5 6 7 8 9 10; do t=$(tmux list-clients -t "=$1" -F '#{client_tty}' | head -n1); [ -n "$t" ] && { echo "$t"; return; }; sleep 0.3; done; }
  attach_as vsa "$WORK/a" vscode ipcA;        ta=$(tty_of vsa)
  attach_as proj "$WORK/links/proj" vscode ipcB; tty_of proj >/dev/null
  sess_of() { tmux list-clients -F '#{client_tty} #S' | awk -v t="$1" '$1 == t { print $2 }'; }
  go() { JUNBAN_CLIENT=$1 bash -c ". '$S/lib.sh'; go_to $2"; }
  go "$ta" proj:1
  eq  "other window shows it → raise that window" "$(cat "$WORK/raised" 2>/dev/null)" "ipcA $WORK/links/proj"
  eq  "raising leaves this terminal alone"  "$(sess_of "$ta")" "vsa"
  rm -f "$WORK/raised"; go "$ta" bare:1
  eq  "no window for it → switch in place"  "$(sess_of "$ta")" "bare"
  hasnt "…without calling code"             "$(ls "$WORK")" "raised"
  tmux switch-client -c "$ta" -t =vsa
  tmux set -g @junban-vscode-raise off; go "$ta" proj:1; tmux set -gu @junban-vscode-raise
  eq  "@junban-vscode-raise off → switch"   "$(sess_of "$ta")" "proj"
  attach_as bare "$WORK/a";                    tw=$(tty_of bare)
  tmux switch-client -c "$ta" -t =vsa; tmux switch-client -c "$tw" -t =vsa
  go "$tw" proj:1
  eq  "plain terminal → switch as before"   "$(sess_of "$tw")" "proj"
  hasnt "…without calling code"             "$(ls "$WORK")" "raised"
  # ✓ clears only for a terminal that has focus; a background window's client is no reader.
  pv=$(tmux display -p -t vsa:1 '#{pane_id}')
  TMUX_PANE=$pv bash "$S/state.sh" "done" </dev/null
  eq  "done while its terminal has focus → idle" "$(get vsa:1 @junban)" "idle"
  tmux kill-session -t =proj; tmux kill-session -t =bare; tmux kill-session -t =vsa
else
  echo "  (skipped: needs /proc and script(1))"
fi

echo "popups"
# page.sh in a real pane: scroll keys scroll, anything else closes.
pg() {  # pg N KEYS... — open 1..N, send each key literally, print "top-line closed?"
  tmux new -d -s pg -x 80 -y 12 "seq $1 | bash '$S/page.sh'; echo CLOSED; sleep 30"; sleep 0.5; shift
  for k in "$@"; do tmux send-keys -t pg: -l "$k"; done; sleep 0.4
  printf '%s %s' "$(tmux capture-pane -pt pg: | head -n 1)" "$(tmux capture-pane -pt pg: | grep -c CLOSED)"
  tmux kill-session -t pg:
}
E=$'\033'
eq  "long text opens at the top"      "$(pg 100)" "1 0"
eq  "↓ scrolls"                       "$(pg 100 "${E}[B" "${E}[B")" "3 0"
eq  "wheel scrolls three lines"       "$(pg 100 "${E}[<65;5;5M")" "4 0"
eq  "Space pages"                     "$(pg 100 " ")" "11 0"
eq  "q closes"                        "$(pg 100 q)" "CLOSED 1"
eq  "Esc closes"                      "$(pg 100 "${E}")" "CLOSED 1"
eq  "a click closes"                  "$(pg 100 "${E}[<0;5;5M")" "CLOSED 1"
eq  "Alt+/ again closes"              "$(pg 100 "${E}/")" "CLOSED 1"
eq  "Space closes short text"         "$(pg 3 " ")" "CLOSED 1"

echo "finished work in batches"
tmux new-window -d -t u:17 -n held; ph=$(tmux display -p -t u:17 '#{pane_id}')
eq  "batching off by default"       "$(bash -c ". '$S/lib.sh'; slot_start")" "0"
tmux set -g @junban-done-batch 30
slot=$(bash -c ". '$S/lib.sh'; slot_start")
z=$(date +%z); off=$(( (10#${z:1:2} * 3600 + 10#${z:3:2} * 60) * (${z:0:1}1) ))
eq  "slots follow the wall clock"   "$(( (slot + off) % 1800 ))" "0"
for w in $(tmux list-windows -t u -F '#{window_index}'); do tmux set -w -t "u:$w" -u @junban; done
tmux set -w -t u:17 @junban "done" \; set -w -t u:17 @junban_ts "$(date +%s)"
has "a fresh ✓ is held"             "$(bash "$S/hints.sh" 160 1)" "1 finished, shown at"
hasnt "…without the banner"         "$(bash "$S/hints.sh" 160 1)" "finished →"
tmux set -w -t u:17 @junban_ts $((slot - 60))
has "an earlier slot's ✓ shows"     "$(bash "$S/hints.sh" 160 1)" "1 finished → "
eq  "Alt+a still goes to held ✓"    "$(JUNBAN_DRY_RUN=1 bash "$S/jump.sh")" "u:17"
log="$HOME/.local/state/junban/waits.tsv"; : > "$log"
tmux set -w -t u:17 @junban_ts "$(date +%s)"; st "$ph" idle
eq  "opening a held ✓ is no wait"   "$(wc -l < "$log" | tr -d ' ')" "0"
st "$ph" "done" '{}'; tmux set -w -t u:17 @junban "done" \; set -w -t u:17 @junban_ts $((slot - 60)); st "$ph" idle
eq  "the wait starts when it shows" "$(cut -f1 "$log")" "$slot"
# one notification per slot, listing what finished in it
notes="$WORK/notes"; : > "$notes"
tmux set -g @junban-notify-cmd "cat >> $notes"
tmux set -w -t u:17 @junban "done" \; set -w -t u:17 @junban_ts $((slot - 60)) \; set -w -t u:17 @junban_recap "tests pass"
sleep 0.3; rm -rf "$HOME/.local/state/junban"/digest.*; tmux set -g @junban-digest-at $((slot - 1800))
bash "$S/digest.sh"; bash "$S/digest.sh"
eq  "slot end sends one digest"     "$(cat "$notes")" "✓ 1 finished
- held: tests pass"
tmux set -w -t u:17 @junban running; st "$ph" "done" '{}'; sleep 0.3
TMUX_PANE=$ph python3 "$S/recap.py" "done" <<<'{"last_assistant_message":"Deployed"}'
eq  "no ✓ one by one while batching" "$(grep -c . "$notes")" "2"
tmux set -gu @junban-notify-cmd; tmux set -gu @junban-done-batch; tmux set -gu @junban-digest-at
tmux kill-window -t u:17

echo "what a turn changed"
rv="$WORK/rv"; git init -q "$rv"; printf 'a\nb\nc\n' > "$rv/f.txt"
git -C "$rv" add f.txt; git -C "$rv" -c user.name=t -c user.email=t@t commit -q -m init
tmux new-window -d -t u:17 -n rev -c "$rv"; pv=$(tmux display -p -t u:17 '#{pane_id}')
rvw() { TMUX_PANE=$pv python3 "$S/review.py" "$1" <<<"$2"; }
rvw start "{\"cwd\":\"$rv\"}"; tmux set -w -t u:17 @junban "done"
rvw "done" "{\"cwd\":\"$rv\",\"last_assistant_message\":\"Answered.\"}"
eq  "nothing touched"               "$(get u:17 @junban_review)" "no file changes"
printf 'a\nB\nc\nd\n' > "$rv/f.txt"; git -C "$rv" -c user.name=t -c user.email=t@t commit -qam edit
printf 'x\n' > "$rv/new.txt"; printf 'e\n' >> "$rv/f.txt"
rvw "done" "{\"cwd\":\"$rv\",\"last_assistant_message\":\"Done, see https://github.com/o/r/pull/7 for the PR.\"}"
eq  "files, lines, commits, PR"     "$(get u:17 @junban_review)" "2 files +3 −1 · 1 commit · PR ＃7"
eq  "PR link kept"                  "$(get u:17 @junban_pr)" "https://github.com/o/r/pull/7"
has "✓ banner says what changed"    "$(bash "$S/hints.sh" 160 1)" "2 files +3 −1"
has "Alt+f preview shows the diff"  "$(FZF_PREVIEW_LINES=30 python3 "$S/review.py" preview u:17)" "f.txt"
opened="$WORK/opened"
# shellcheck disable=SC2016  # $1 belongs to the stub browser
printf '#!/bin/sh\necho "$1" > %s\n' "$opened" > "$WORK/browser"; chmod +x "$WORK/browser"
BROWSER="$WORK/browser" bash "$S/switch.sh" --open u:17; sleep 0.3
eq  "Ctrl+o opens the PR"           "$(cat "$opened" 2>/dev/null)" "https://github.com/o/r/pull/7"
tmux set -w -t u:17 @junban running; rvw "done" "{\"cwd\":\"$rv\"}"
eq  "late result after a new prompt dropped" "$(get u:17 @junban_review)" "2 files +3 −1 · 1 commit · PR ＃7"
st "$pv" idle; st "$pv" running '{"prompt":"next task"}'
eq  "a new prompt clears it"        "$(get u:17 @junban_review)" ""
tmux kill-window -t u:17

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
