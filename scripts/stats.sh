#!/usr/bin/env bash
# shellcheck disable=SC2059  # i18n strings are printf formats by design
# How long your agents sat waiting on you, from the log state.sh keeps.
#
#   stats.sh          last 7 days with a bar per day, this week against last,
#                     your best day and streak, then today's slowest windows
#   stats.sh 30       last 30 days
#   stats.sh --line   today's "total<TAB>median<TAB>count<TAB>trend" (the guide
#                     line uses it; trend is today's median against the 7 days
#                     before, like "-32%", or "-" when there is too little data)
#
# A wait runs from the moment an agent asks you something (✋) or finishes (✓)
# until you answer or look. Finishing while you watch is no wait at all.
# Each wait counts for at most @junban-meter-cap minutes (default 60), so one
# agent left overnight does not drown out the rest of the day.
# The streak counts days whose median reply is within @junban-goal minutes
# (default 5); days without agents neither extend nor break it.
. "$(dirname "$0")/lib.sh"
load_i18n

log="${XDG_STATE_HOME:-$HOME/.local/state}/junban/waits.tsv"
cap=$(( $(opt @junban-meter-cap 60) * 60 ))
goal=$(opt @junban-goal 5)
case "$goal" in '' | *[!0-9]*) goal=5 ;; esac
now=$(date +%s)
midnight=$(( now - (10#$(date +%H) * 3600 + 10#$(date +%M) * 60 + 10#$(date +%S)) ))
# Fewer waits than this and a median says more about luck than about you.
MIN_N=5

# capped SINCE — "day<TAB>seconds<TAB>kind<TAB>window" for each wait ending after SINCE.
capped() {
  [ -f "$log" ] || return 0
  awk -F'\t' -v since="$1" -v cap="$cap" -v mid="$midnight" '
    $2 >= since && $2 >= $1 {
      d = $2 - $1; if (cap > 0 && d > cap) d = cap
      day = ($2 >= mid) ? 0 : int((mid - $2 - 1) / 86400) + 1   # 0 = today, 1 = yesterday …
      print day "\t" d "\t" $3 "\t" $4 }' "$log"
}

# daily — reads capped rows, prints "day<TAB>total<TAB>median<TAB>count" for
# each day that has waits, today first.
daily() {
  sort -t "$(printf '\t')" -k1,1n -k2,2n | awk -F'\t' '
    function flush() {
      if (n) print day "\t" t "\t" ((n % 2) ? v[(n + 1) / 2] : int((v[n / 2] + v[n / 2 + 1]) / 2)) "\t" n }
    NR == 1 || $1 != day { flush(); day = $1; n = 0; t = 0 }
    { v[++n] = $2; t += $2 }
    END { flush() }'
}

# span FROM TO — waits on days FROM..TO (0 = today) from capped rows on stdin,
# summarised as "total<TAB>median<TAB>count".
span() { awk -F'\t' -v a="$1" -v b="$2" '$1 >= a && $1 <= b { print $2 }' | summarise; }

# pct NEW OLD → "-32%"
pct() { awk -v n="$1" -v o="$2" 'BEGIN { p = (n - o) * 100 / o; printf "%+d%%", p + (p < 0 ? -0.5 : 0.5) }'; }

# table HEADSTYLE — align TSV on stdin by display width (日本語 and ไทย are not
# one column per byte), right-aligning every column but the first and last.
table() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import sys, unicodedata
def w(s):
    return sum(0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in s)
rows = [l.rstrip("\n").split("\t") for l in sys.stdin if l.strip()]
n = max(len(r) for r in rows)
wid = [max(w(r[i]) for r in rows if i < len(r)) for i in range(n)]
for k, r in enumerate(rows):
    cells = []
    for i, c in enumerate(r):
        pad = " " * (wid[i] - w(c))
        cells.append(c + pad if i in (0, n - 1) else pad + c)
    line = "  " + "   ".join(cells).rstrip()
    print(sys.argv[1] + line + "\033[0m" if k == 0 and sys.argv[1] else line)
' "$1"
  else
    column -t -s "$(printf '\t')"
  fi
}

# summarise — reads seconds on stdin, prints "total<TAB>median<TAB>count".
summarise() {
  sort -n | awk '{ v[NR] = $1; t += $1 }
    END { if (!NR) { print "0\t0\t0"; exit }
          m = (NR % 2) ? v[(NR + 1) / 2] : int((v[NR / 2] + v[NR / 2 + 1]) / 2)
          print t "\t" m "\t" NR }'
}

# bar VALUE MAX WIDTH — a horizontal bar in eighths of a cell.
bar() {
  local e=$(( $2 > 0 ? $1 * $3 * 8 / $2 : 0 )) out="" i
  local parts=("" ▏ ▎ ▍ ▌ ▋ ▊ ▉)
  for ((i = 0; i < e / 8; i++)); do out="${out}█"; done
  [ "$1" -gt 0 ] && [ "$e" -eq 0 ] && e=1   # any wait at all shows
  printf '%s%s' "$out" "${parts[e % 8]}"
}

day_label() {
  date -d "@$(( midnight - $1 * 86400 ))" +%m/%d 2>/dev/null || date -r "$(( midnight - $1 * 86400 ))" +%m/%d
}

if [ "${1:-}" = --line ]; then
  rows=$(capped $(( midnight - 7 * 86400 )))
  IFS=$'\t' read -r t m c < <(printf '%s\n' "$rows" | span 0 0)
  IFS=$'\t' read -r _ pm pc < <(printf '%s\n' "$rows" | span 1 7)
  trend=-
  [ "$c" -ge 3 ] && [ "$pc" -ge "$MIN_N" ] && [ "$pm" -gt 0 ] && trend=$(pct "$m" "$pm")
  printf '%s\t%s\t%s\t%s\n' "$t" "$m" "$c" "$trend"
  exit 0
fi

days=${1:-7}
case "$days" in '' | *[!0-9]*) days=7 ;; esac
[ "$days" -lt 1 ] && days=1
all=$(capped 0)
rows=$(printf '%s\n' "$all" | awk -F'\t' -v n="$days" 'NF && $1 < n')
per_day=$(printf '%s\n' "$all" | awk NF | daily)
b=$'\033[1m'; dim=$'\033[2m'; r=$'\033[0m'
mascot=$(opt @junban-mascot off)

printf '\n  %s%s%s\n\n' "$b" "$(printf "$STATS_TITLE" "$days")" "$r"
peak=$(printf '%s\n' "$per_day" | awk -F'\t' -v n="$days" 'NF && $1 < n && $2 > m { m = $2 } END { print m + 0 }')
{
printf '%s\t%s\t%s\t%s\t%s\t%s\t\n' "$STATS_DAY" "$STATS_TOTAL" "$STATS_COUNT" "$STATS_MEDIAN" "✋" "✓"
for ((i = days - 1; i >= 0; i--)); do
  day=$(day_label "$i")
  [ "$i" -eq 0 ] && day="$day $STATS_TODAY"
  IFS=$'\t' read -r total median count < <(printf '%s\n' "$rows" | span "$i" "$i")
  w=$(printf '%s\n' "$rows" | awk -F'\t' -v d="$i" '$1 == d && $3 == "waiting"' | grep -c . || true)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$day" "$(fmt_dur "$total")" "$count" \
    "$(fmt_dur "$median")" "$w" "$((count - w))" "$(bar "$total" "$peak" 16)"
done
} | table "$dim"

# This week against last: the number that says whether the habit is sticking.
IFS=$'\t' read -r tt tm tc < <(printf '%s\n' "$all" | span 0 6)
IFS=$'\t' read -r lt lm lc < <(printf '%s\n' "$all" | span 7 13)
face="" say=""
if [ "$tc" -ge "$MIN_N" ] && [ "$lc" -ge "$MIN_N" ] && [ "$lm" -gt 0 ] && [ "$lt" -gt 0 ]; then
  printf '\n  %s\n' "$(printf "$STATS_WEEK" "$(fmt_dur "$lm")" "$(fmt_dur "$tm")" "$(pct "$tm" "$lm")" \
    "$(fmt_dur "$lt")" "$(fmt_dur "$tt")" "$(pct "$tt" "$lt")")"
  p=$(pct "$tm" "$lm"); p=${p%\%}; p=${p#+}
  if [ "$p" -le -10 ]; then face='[◠ ◠]'; say=$(printf "$MASCOT_UP" $(( -p )))
  elif [ "$p" -ge 10 ]; then face='[▬ ▬]'; say=$(printf "$MASCOT_DOWN" "$p")
  else face='[▮ ▮]'; say=$MASCOT_SAME
  fi
else
  face='[▮ ▮]?'; say=$MASCOT_NEW
fi

# Personal best: the day with the quickest median reply (enough waits to count).
best=$(printf '%s\n' "$per_day" | awk -F'\t' -v n="$MIN_N" 'NF && $4 >= n' | sort -t "$(printf '\t')" -k3,3n -k1,1n | head -n 1)
if [ -n "$best" ]; then
  IFS=$'\t' read -r bd _ bm _ <<<"$best"
  printf '  %s\n' "$(printf "$STATS_BEST" "$(day_label "$bd")" "$(fmt_dur "$bm")")"
  [ "$bd" -eq 0 ] && say="$MASCOT_BEST $say"
fi

# Streak: recent days within the goal. Today only counts once it is within it.
streak=$(printf '%s\n' "$per_day" | awk -F'\t' -v g=$(( goal * 60 )) '
  NF { if ($3 <= g) s++; else if ($1 > 0) exit }
  END { print s + 0 }')
[ "$streak" -ge 2 ] && printf '  %s\n' "$(printf "$STATS_STREAK" "$streak" "$goal")"
[ "$mascot" = on ] && printf '\n  %s%s%s  %s\n' "$b" "$face" "$r" "$say"

top=$(printf '%s\n' "$rows" | awk -F'\t' '$1 == 0 { t[$4] += $2; n[$4]++ }
  END { for (k in t) print t[k] "\t" n[k] "\t" k }' | sort -rn | head -n 8)
if [ -n "$top" ]; then
  printf '\n  %s%s%s\n' "$dim" "$STATS_BY_WINDOW" "$r"
  while IFS=$'\t' read -r total count name; do
    printf '%s\t%s×\t%s\n' "$(fmt_dur "$total")" "$count" "$name"
  done <<<"$top" | table ""
fi
printf '\n  %s%s%s\n' "$dim" "$(printf "$STATS_NOTE" "$(( cap / 60 ))")" "$r"
