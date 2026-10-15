#!/usr/bin/env bash
# shellcheck disable=SC2059  # i18n strings are printf formats by design
# How long your agents sat waiting on you, from the log state.sh keeps.
#
#   stats.sh          last 7 days, then today's windows that waited longest
#   stats.sh 30       last 30 days
#   stats.sh --line   today's "total<TAB>median<TAB>count" (the guide line uses it)
#
# A wait runs from the moment an agent asks you something (✋) or finishes (✓)
# until you answer or look. Finishing while you watch is no wait at all.
# Each wait counts for at most @junban-meter-cap minutes (default 60), so one
# agent left overnight does not drown out the rest of the day.
. "$(dirname "$0")/lib.sh"
load_i18n

log="${XDG_STATE_HOME:-$HOME/.local/state}/junban/waits.tsv"
cap=$(( $(opt @junban-meter-cap 60) * 60 ))
now=$(date +%s)
midnight=$(( now - (10#$(date +%H) * 3600 + 10#$(date +%M) * 60 + 10#$(date +%S)) ))

# capped SINCE — "day<TAB>seconds<TAB>kind<TAB>window" for each wait ending after SINCE.
capped() {
  [ -f "$log" ] || return 0
  awk -F'\t' -v since="$1" -v cap="$cap" -v mid="$midnight" '
    $2 >= since && $2 >= $1 {
      d = $2 - $1; if (cap > 0 && d > cap) d = cap
      day = ($2 >= mid) ? 0 : int((mid - $2 - 1) / 86400) + 1   # 0 = today, 1 = yesterday …
      print day "\t" d "\t" $3 "\t" $4 }' "$log"
}

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

if [ "${1:-}" = --line ]; then
  capped "$midnight" | cut -f2 | summarise
  exit 0
fi

days=${1:-7}
case "$days" in '' | *[!0-9]*) days=7 ;; esac
rows=$(capped $(( midnight - (days - 1) * 86400 )))
b=$'\033[1m'; dim=$'\033[2m'; r=$'\033[0m'

printf '\n  %s%s%s\n\n' "$b" "$(printf "$STATS_TITLE" "$days")" "$r"
{
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$STATS_DAY" "$STATS_TOTAL" "$STATS_COUNT" "$STATS_MEDIAN" "✋" "✓"
for ((i = days - 1; i >= 0; i--)); do
  day=$(date -d "@$(( midnight - i * 86400 ))" +%m/%d 2>/dev/null || date -r "$(( midnight - i * 86400 ))" +%m/%d)
  [ "$i" -eq 0 ] && day="$day $STATS_TODAY"
  these=$(printf '%s\n' "$rows" | awk -F'\t' -v d="$i" '$1 == d')
  IFS=$'\t' read -r total median count < <(printf '%s\n' "$these" | awk -F'\t' 'NF { print $2 }' | summarise)
  w=$(printf '%s\n' "$these" | awk -F'\t' '$3 == "waiting"' | grep -c . || true)
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$day" "$(fmt_dur "$total")" "$count" \
    "$(fmt_dur "$median")" "$w" "$((count - w))"
done
} | table "$dim"

top=$(printf '%s\n' "$rows" | awk -F'\t' '$1 == 0 { t[$4] += $2; n[$4]++ }
  END { for (k in t) print t[k] "\t" n[k] "\t" k }' | sort -rn | head -n 8)
if [ -n "$top" ]; then
  printf '\n  %s%s%s\n' "$dim" "$STATS_BY_WINDOW" "$r"
  while IFS=$'\t' read -r total count name; do
    printf '%s\t%s×\t%s\n' "$(fmt_dur "$total")" "$count" "$name"
  done <<<"$top" | table ""
fi
printf '\n  %s%s%s\n' "$dim" "$(printf "$STATS_NOTE" "$(( cap / 60 ))")" "$r"
