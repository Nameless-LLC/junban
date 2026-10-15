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
hasnt "mascot is opt-in"            "$rep" '\(^o^)/'
tmux set -g @junban-mascot on
rep=$(bash "$S/stats.sh" 7)
has "mascot cheers a quicker week"  "$rep" '\(^o^)/'
has "…and says why"                 "$rep" "a new personal best today! 50% quicker"
eq  "trend needs 5 waits before"    "$(bash "$S/stats.sh" --line | cut -f4)" "-"
for d in 4 5; do e=$((now - d * 86400)); printf '%s\t%s\tdone\tu:b\n' $((e - 180)) "$e" >> "$log"; done
eq  "trend: today vs last 7 days"   "$(bash "$S/stats.sh" --line | cut -f4)" "-33%"
has "guide shows the trend"         "$(bash "$S/hints.sh")" "-33% vs the last 7 days"
tmux set -w -t u:6 @junban waiting
has "mascot calls when someone waits" "$(bash "$S/summary.sh")" "(O_O)"
tmux set -w -t u:6 -u @junban
tmux set -gu @junban-mascot
hasnt "no mascot unless asked"      "$(bash "$S/summary.sh")" "_"

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
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        ok = "final message" in body["messages"][0]["content"] and body["options"]["num_predict"] == 48
        out = json.dumps({"message": {"content": "Model: 3 files fixed" if ok else "wrong prompt"}}).encode()
        self.send_response(200); self.end_headers(); self.wfile.write(out)
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
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
