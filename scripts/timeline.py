"""timeline.py LOG DAY COLS CAP ALIVE — draw one day of states.tsv, a row per window.

Called by timeline.sh, which passes the labels in the user's language as
environment variables. DAY is 0 for today, 1 for yesterday. CAP is how many
seconds a ✋ or ✓ counts before it is treated as the agent simply sitting there
(the same cap as the wait meter). ALIVE lists the window keys that still exist:
a window that is gone stops at its last change instead of running on to now.
"""
import os
import sys
import time
import unicodedata
from datetime import datetime, timedelta

log, day, cols, cap = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
alive = set(sys.argv[5].split()) if len(sys.argv) > 5 else set()
L = os.environ.get
now = time.time()
start = (datetime.now().replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=day)).timestamp()
end = min(now, (datetime.fromtimestamp(start) + timedelta(days=1)).timestamp())

COLOR = os.environ.get("NO_COLOR") is None
STYLE = {"running": ("\033[33m", "█"), "waiting": ("\033[31m", "▓"), "done": ("\033[32m", "▒")}
DIM, BOLD, RESET = ("\033[2m", "\033[1m", "\033[0m") if COLOR else ("", "", "")


def paint(state, text=None):
    c, g = STYLE[state]
    return (c if COLOR else "") + (text or g) + (RESET if COLOR else "")


def width(s):
    return sum(0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in s)


def clip(s, w):
    out = ""
    for c in s:
        if width(out + c) > w:
            return out[:-1] + "…" if width(out) >= w else out + "…"
        out += c
    return out + " " * (w - width(out))


def dur(s):
    s = int(s)
    h, m, sec = L("T_H", "h"), L("T_M", "m"), L("T_S", "s")
    if s < 60:
        return f"{s}{sec}"
    if s < 3600:
        return f"{s // 60}{m}"
    return f"{s // 3600}{h}{s % 3600 // 60:02d}{m}"


def hm(t):
    return datetime.fromtimestamp(t).strftime("%H:%M")


# Read every change; spans are built per window from one change to the next.
events = {}
names = {}
try:
    with open(log, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if len(f) < 4 or not f[0].isdigit():
                continue
            t = int(f[0])
            if t > end:
                continue
            events.setdefault(f[2], []).append((t, f[1]))
            if t >= start or f[2] not in names:
                names[f[2]] = f[3]
except FileNotFoundError:
    pass

spans = {}  # key -> [(from, to, state)] within the day, idle left out
for key, ev in events.items():
    ev.sort()
    for i, (t, st) in enumerate(ev):
        if st not in STYLE:
            continue
        if i + 1 < len(ev):
            t2 = ev[i + 1][0]
        elif key in alive:
            t2 = now
        else:
            continue  # the window closed without telling us when
        if st != "running" and cap > 0:
            t2 = min(t2, t + cap)  # past the cap it is just sitting there
        a, b = max(t, start), min(t2, end)
        if b > a:
            spans.setdefault(key, []).append((a, b, st))

title = datetime.fromtimestamp(start).strftime("%m/%d")
print(f"\n  {BOLD}{L('TL_TITLE', 'Timeline — %s') % title}{RESET}\n")
if not spans:
    print(f"  {L('TL_EMPTY', 'Nothing recorded for this day yet.')}\n")
    sys.exit(0)

# Hours shown: from the first activity to the last, whole hours.
first = min(s[0] for v in spans.values() for s in v)
last = max(s[1] for v in spans.values() for s in v)
h0 = datetime.fromtimestamp(first).replace(minute=0, second=0, microsecond=0).timestamp()
h1 = datetime.fromtimestamp(last).replace(minute=0, second=0, microsecond=0).timestamp() + 3600

rows = sorted(spans, key=lambda k: spans[k][0][0])
label_w = max(6, min(20, max(width(names[k]) for k in rows)))
room = max(12, cols - label_w - 5)
step = next((m * 60 for m in (1, 2, 3, 5, 10, 15, 20, 30, 60, 120) if (h1 - h0) / (m * 60) <= room), 7200)
ncell = int((h1 - h0 + step - 1) // step)

# Hour marks above the bars, as many as fit without touching.
axis = [" "] * (ncell + 6)
every = next(n for n in (1, 2, 3, 4, 6, 12, 24) if 3600 * n / step >= 3)
t = h0
while t < h1:
    h = datetime.fromtimestamp(t).hour
    if h % every == 0:
        i = int((t - h0) // step)
        for j, c in enumerate(str(h)):
            if i + j < len(axis):
                axis[i + j] = c
    t += 3600
print(f"  {' ' * label_w}  {DIM}{''.join(axis).rstrip()}{RESET}")

for k in rows:
    cells = []
    for i in range(ncell):
        a, b = h0 + i * step, h0 + (i + 1) * step
        got = {}
        for s0, s1, st in spans[k]:
            o = min(b, s1) - max(a, s0)
            if o > 0:
                got[st] = got.get(st, 0) + o
        if sum(got.values()) * 4 < step:
            cells.append(" ")
            continue
        # Time an agent sat waiting on you is what this view is for: weigh it double,
        # so a short ✋ in a wide column still shows.
        st = max(got, key=lambda s: (got[s] * (1 if s == "running" else 2), s != "running"))
        cells.append(paint(st))
    print(f"  {clip(names[k], label_w)}  {''.join(cells).rstrip()}")

# Totals across windows: union of running time, waits summed, the busiest moment.
marks = []
waited = 0
for v in spans.values():
    for a, b, st in v:
        if st == "running":
            marks += [(a, 1), (b, -1)]
        else:
            waited += b - a
marks.sort()
run_total, depth, peak, since = 0, 0, 0, None
for t, d in marks:
    if depth > 0:
        run_total += t - since
    depth += d
    peak = max(peak, depth)
    since = t

print()
print("  " + "   ".join([paint("running") + " " + L("TL_RUNNING", "agent working"),
                         paint("waiting") + " " + L("TL_WAITING", "waiting for you"),
                         paint("done") + " " + L("TL_DONE", "done, not looked at")]))
print()
print("  " + L("TL_SPAN", "Active %s–%s") % (hm(first), hm(last)) + "  ·  "
      + L("TL_RUN", "agents working %s") % dur(run_total) + "  ·  "
      + L("TL_WAITED", "waited on you %s") % dur(waited)
      + ("  ·  " + L("TL_PEAK", "up to %d at once") % peak if peak > 1 else ""))
print(f"  {DIM}{L('TL_MORE', 'One column = %s. timeline.sh 1 shows yesterday.') % dur(step)}{RESET}\n")
