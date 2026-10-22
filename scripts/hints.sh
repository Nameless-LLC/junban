#!/usr/bin/env bash
# The guide line. Tells you the one key that matters right now:
#   someone is waiting → a red banner pointing at the jump key
#   someone finished   → a green banner (with @junban-done-batch, only once the
#                        slot it finished in is over; until then a quiet count)
#   otherwise          → today's wait and a quiet count of agents parked for a
#                        day, and (on its own row) the keys worth remembering

# $1 is the client width (#{client_width}). With it the line is fitted to the
# terminal: today's wait beside a banner goes first, then the recap is cut with
# "…", so the banner itself always shows. Without it nothing is fitted (tmux clips at the edge).
. "$(dirname "$0")/lib.sh"
opt_prefetch @junban-lang @junban-color-bg @junban-color-waiting @junban-color-done @junban-color-key \
  @junban-color-muted @junban-color-slower @junban-color-dim @junban-key-jump @junban-key-list \
  @junban-key-new @junban-key-settings @junban-key-help @junban-nav-keys @junban-meter @junban-tint \
  @junban-tint-waiting @junban-stale-hours @junban-done-batch @junban-meter-cap @junban_meter_cache \
  @junban_update_day @junban_version @junban_version_seen
load_i18n

# Once a day, look for a newer junban (update.sh). The day is marked first, so
# the other rows and clients refreshing at the same moment start nothing.
today=$(date +%Y%m%d)
if [ "$(opt @junban_update_day "")" != "$today" ]; then
  tmux set -g @junban_update_day "$today" 2>/dev/null
  (bash "$JUNBAN_SCRIPTS/update.sh" </dev/null >/dev/null 2>&1 &)
fi

# A new version says so once, at the first status line that draws it: an update
# that ran in the background, or while no one was looking, is not missed. A
# first install says nothing. The file outlives the tmux server; the option
# saves reading it every few seconds.
v=$(opt @junban_version "")
if [ -n "$v" ] && [ "$(opt @junban_version_seen "")" != "$v" ]; then
  tmux set -g @junban_version_seen "$v" 2>/dev/null
  f="${XDG_STATE_HOME:-$HOME/.local/state}/junban/version"
  old=$(cat "$f" 2>/dev/null)
  if [ "$old" != "$v" ]; then
    mkdir -p "${f%/*}" 2>/dev/null; echo "$v" > "$f" 2>/dev/null
    # shellcheck disable=SC2059
    [ -n "$old" ] && tmux display -d 8000 "$(printf "$T_UPDATED" "$v")" 2>/dev/null
  fi
fi

cols=${1:-0}
row=${2:-}
case "$cols" in '' | *[!0-9]*) cols=0 ;; esac
# Character counts need a UTF-8 locale; tmux jobs often run under C.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8 | *[Uu][Tt][Ff]8) ;;
  *) case "$(locale charmap 2>/dev/null)" in
       UTF-8 | utf-8) ;;
       *) for l in C.UTF-8 en_US.UTF-8; do LC_ALL=$l; [ "$(locale charmap 2>/dev/null)" = UTF-8 ] && break; done 2>/dev/null ;;
     esac ;;
esac

# Display width of plain text, erring wide: ASCII is 1, a few symbols this line
# uses are 1, anything else (CJK, emoji) counts as 2.
# _dw sets W; no subshell, since fit calls it once per character.
_dw() {
  local s=${1//[✓·→…]/.} a
  a=${s//[^ -~]/}
  W=$((${#a} + 2 * (${#s} - ${#a})))
}
dw() { _dw "$1"; echo "$W"; }
# Width with tmux #[…] styles removed.
dws() {
  local s=$1 pre rest
  while :; do
    case "$s" in
      *'#['*']'*) pre=${s%%'#['*}; rest=${s#*'#['}; s=$pre${rest#*']'} ;;
      *) break ;;
    esac
  done
  dw "$s"
}
# fit TEXT MAX — TEXT cut to MAX columns, ending in "…" when cut.
fit() {
  local s=$1 max=$2 out="" i used=0
  _dw "$s"; [ "$W" -le "$max" ] && { printf '%s' "$s"; return; }
  [ "$max" -lt 2 ] && return
  for ((i = 0; i < ${#s}; i++)); do
    _dw "${s:i:1}"
    [ $((used + W)) -gt $((max - 1)) ] && break
    used=$((used + W)); out=$out${s:i:1}
  done
  printf '%s…' "${out% }"
}

w=0; d=0; z=0; held=0
slot=$(slot_start)
# The window Alt+a would open (oldest ✋, else oldest ✓), so the banner can say
# what it wants before you go there.
next_rank=9; next_ts=0; next_line=""
# Empty fields print as "-": read collapses runs of tab separators, which would
# shift the fields. (tmux escapes control characters, so no \037 trick.)
while IFS=$'\t' read -r s st name ts recap review; do
  case "$s" in
    waiting) w=$((w + 1)); rank=1 ;;
    done) if [ "$slot" -gt 0 ] && [ "${ts:-0}" -ge "$slot" ]; then held=$((held + 1)); rank=9
          else d=$((d + 1)); rank=2; fi ;;
    *) rank=9 ;;
  esac
  if [ "$rank" -lt 9 ] && { [ "$rank" -lt "$next_rank" ] ||
       { [ "$rank" -eq "$next_rank" ] && [ "${ts:-0}" -lt "$next_ts" ]; }; }; then
    next_rank=$rank; next_ts=${ts:-0}
    next_line="$name"; [ "$recap" != - ] && next_line="$name: $recap"
    # What a finished turn changed tells you how long reviewing it will take.
    [ "$rank" = 2 ] && [ "$review" != - ] && next_line="$next_line · $review"
  fi
  [ "$st" != - ] && z=$((z + 1))
done < <(tmux list-windows -a -F '#{?@junban,#{@junban},-}	#{?@junban_stale,#{@junban_stale},-}	#{=12:window_name}	#{?@junban_ts,#{@junban_ts},0}	#{?@junban_recap,#{@junban_recap},-}	#{?@junban_review,#{@junban_review},-}' 2>/dev/null)
# A window name is free text: a # in it would start a style ("a#[fg=red]").
next_line=${next_line//#/＃}

bg=$(opt @junban-color-bg "#1e2127")
cw=$(opt @junban-color-waiting "#e06c75")
cd_=$(opt @junban-color-done "#98c379")
ck=$(opt @junban-color-key "#e5c07b")
cm=$(opt @junban-color-muted "#7f848e")
# Not the red of ✋: slower replies are worth a look, not a call to come now.
co=$(opt @junban-color-slower "#d19a66")
cdim=$(opt @junban-color-dim "#5c6370")

kj=$(key_for jump M-a a)
kf=$(key_for list M-f f)
kn=$(key_for new M-n C)
ks=$(opt @junban-key-settings M-,); [ -n "$ks" ] && ks=$(keylabel "$ks")
kh=$(key_for help M-/ /)

right=""

# mix COLOR [PCT] — COLOR laid faintly over the line's background, PCT % of it
# (default @junban-tint, 20; 0 turns the tint off). Only #rrggbb colors mix.
mix() {
  local a=${1#\#} b=${bg#\#} p i out=""
  p=${2:-$(num @junban-tint 20 100)}
  case "$p" in '' | *[!0-9]*) p=0 ;; esac
  p=$((10#$p)); [ "$p" -gt 100 ] && p=100
  case "$a$b" in *[!0-9a-fA-F]* | '') echo "$bg"; return ;; esac
  if [ ${#a} -ne 6 ] || [ ${#b} -ne 6 ] || [ "$p" -le 0 ]; then echo "$bg"; return; fi
  for i in 0 2 4; do
    out=$out$(printf '%02x' $(( 16#${b:i:2} + (16#${a:i:2} - 16#${b:i:2}) * p / 100 )))
  done
  echo "#$out"
}

# banner COLOR TEXT [PCT] — the ✋/✓ banner, then as much of the recap as fits.
# The whole row takes a faint wash of COLOR, so the state shows at a glance.
banner() {
  local tint head room
  tint=$(mix "$1" "${3:-}")
  head="#[fill=$tint]#[fg=$bg,bg=$1,bold] $2 #[bg=$tint,nobold] "
  # A recap can be a whole sentence; never let it stop mid-word without a mark.
  next_line=$(fit "$next_line" 96)
  if [ "$cols" -gt 0 ]; then
    room=$((cols - $(dws "$head")))
    if [ -n "$right" ] && [ $(($(dw "$next_line") + 2 + $(dws "$right"))) -le "$room" ]; then :
    else right=""; next_line=$(fit "$next_line" "$room"); fi
  fi
  left="$head#[fg=$1]$next_line"
  # Today's wait, if it stays, sits on the same wash.
  [ -n "$right" ] && right="#[bg=$tint]$right"
}

# The calm line: the keys worth remembering, then today's wait and parked agents.
keys=""
# Alt+[ ] and Alt+w (@junban-nav-keys) move to and close the window beside; tmux clips
# the end of the row, so they go right after the two keys that matter most.
nav=(); [ "$(opt @junban-nav-keys on)" = on ] && nav=("Alt+[ ]|$T_PREVNEXT" "Alt+w|$T_CLOSE")
for pair in "$kj|$T_NEXT" "$kf|$T_LIST" "${nav[@]}" "$kn|$T_NEW" ${ks:+"$ks|$T_SETTINGS"} "$kh|$T_HELP"; do
  keys="$keys#[fg=$ck]${pair%%|*}#[fg=$cm] ${pair#*|}  "
done
info=""
# Held ✓ stay out of the way: a count and when they will show.
# shellcheck disable=SC2059
[ "$held" -gt 0 ] && info="#[fg=$cd_]✓ $(printf "$T_HELD" "$held" "$(hhmm "$(slot_end "$slot")")")  "
# How long agents sat on you today. Seeing the number is most of the fix.
# Row 2 is the keys; the meter never shows there, so skip reading the log.
if [ "$row" != 2 ] && [ "$(opt @junban-meter on)" = on ]; then
  # The numbers change only when the log grows or the day turns, so they are
  # kept in tmux between refreshes instead of read from the whole log each time.
  wlog="${XDG_STATE_HOME:-$HOME/.local/state}/junban/waits.tsv"
  mkey="$today:$(opt @junban-meter-cap 60):$([ -f "$wlog" ] && wc -c < "$wlog" | tr -d ' ')"
  mline=$(opt @junban_meter_cache "")
  if [ "${mline%%|*}" = "$mkey" ]; then mline=${mline#*|}
  else
    mline=$(bash "$JUNBAN_SCRIPTS/stats.sh" --line 2>/dev/null | tr '\t' ' ')
    tmux set -g @junban_meter_cache "$mkey|$mline" 2>/dev/null
  fi
  read -r mt mm mc mtr <<<"$mline"
  case "$mt$mm$mc" in *[!0-9]*) mc=0 ;; esac
  if [ "${mc:-0}" -gt 0 ]; then
    # shellcheck disable=SC2059
    info="$info#[fg=$cm]$(printf "$T_METER" "$(fmt_dur "$mt")" "$(fmt_dur "$mm")")"
    # Quicker than your own recent days is the one comparison worth making.
    # Said in words beside the median: a bare "+32%" after today's total read
    # as more waiting, and nobody could tell whether up was good. A green ▼ or
    # an orange ▲ says it at a glance, the word for anyone who reads on.
    # A change too small to mean anything ("=") says nothing at all.
    # shellcheck disable=SC2059
    case "$mtr" in
      -[0-9]*) info="$info#[fg=$cd_]$(printf "$T_TREND_FAST" "$(amount "$mtr")")" ;;
      +[0-9]* | x[0-9]*) info="$info#[fg=$co]$(printf "$T_TREND_SLOW" "$(amount "$mtr")")" ;;
    esac
    info="$info  "
  fi
fi
# Parked agents can sit for days, so this rides along instead of taking over.
# shellcheck disable=SC2059
[ "$z" -gt 0 ] && info="$info#[fg=$cdim]z $(printf "$T_STALE" "$z" "$(num @junban-stale-hours 24)") → $(printf "$T_STALE_GO" "$kf")"

# With @junban-guide-lines 3 (the default) there are two guide rows ($2 = 1 or 2):
#   row 1: the banner and its recap, today's wait on the right when it fits;
#          without a banner, today's wait and parked agents
#   row 2: the keys
# With @junban-guide-lines 2 there is one, with no keys on it: the keys and the
# wait together ran past ~110 columns in Japanese and clipped the wait off. The
# keys show there while the prefix is pending instead (junban.tmux).
[ "$row" = 1 ] && right="${info:+#[align=right]$info}"
left=""
# shellcheck disable=SC2059
if [ "$w" -gt 0 ]; then
  # An agent stopped on you is the one thing worth a stronger wash.
  banner "$cw" "✋ $(printf "$T_WAITING" "$w") → $(printf "$T_WAITING_GO" "$kj")" "$(num @junban-tint-waiting "$([ "$(num @junban-tint 20)" = 0 ] && echo 0 || echo 35)" 100)"
elif [ "$d" -gt 0 ]; then
  banner "$cd_" "✓ $(printf "$T_DONE" "$d") → $(printf "$T_DONE_GO" "$kj")"
fi
case "$row" in
  1) [ -z "$left" ] && { left=$info; right=""; } ;;
  2) left=$keys; right="" ;;
  *) [ -z "$left" ] && left=$info ;;
esac

# Whatever the left says matters more than what sits right of it.
[ "$cols" -gt 0 ] && [ -n "$right" ] && [ $(($(dws "$left") + 2 + $(dws "$right"))) -gt "$cols" ] && right=""
printf '%s%s' "$left" "$right"
