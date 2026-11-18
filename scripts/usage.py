#!/usr/bin/env python3
"""How much of your plan's limit is left, and when this pace runs out of it.

  usage.py record      read Claude Code's status line input on stdin and keep it
  usage.py install     put statusline.sh in front of your status line command
  usage.py uninstall   put your own status line command back

Claude Code hands its status line command the plan's usage (rate_limits:
seven_day and, on some plans, five_hour, each a percentage and a reset time)
and the size of the conversation. record keeps, per account (the
CLAUDE_CONFIG_DIR it runs under), a short history of the percentage, and works
out when the recent pace would reach 100 %. It publishes that to tmux:

  @junban_ctx   (window)  tokens in this window's conversation
  @junban_acct  (window)  the account this window's agent runs under
  @junban_limits (global)  account|limit|percent|eta|reset;... current first

hints.sh shows it. Nothing here asks the network: it is what Claude Code
already knows.
"""
import json
import os
import subprocess
import sys
import time

KEEP = 8 * 86400      # history kept per account
STEP = 300            # at most one sample per 5 minutes unless the value moves
PACE = 6 * 3600       # how far back the pace is measured
STALE = 8 * 86400     # an account not seen for this long is dropped from the line


def state_dir():
    d = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "junban", "usage")
    os.makedirs(d, mode=0o700, exist_ok=True)
    return d


def account():
    """main for ~/.claude, b for ~/.claude-b, otherwise the directory name."""
    d = (os.environ.get("CLAUDE_CONFIG_DIR") or "").rstrip("/")
    if not d or os.path.realpath(d) == os.path.realpath(os.path.expanduser("~/.claude")):
        return "main"
    n = os.path.basename(d)
    for p in (".claude-", "claude-", "."):
        if n.startswith(p) and len(n) > len(p):
            return n[len(p):]
    return n


def tmux(*args):
    try:
        subprocess.run(["tmux", *args], capture_output=True, timeout=3)
    except Exception:
        pass


def load(path):
    try:
        with open(path) as fh:
            d = json.load(fh)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def write(path, data):
    tmp = f"{path}.{os.getpid()}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        json.dump(data, fh)
    os.replace(tmp, path)


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def eta(samples, limit, now):
    """When the pace of the last PACE seconds reaches 100 %, or 0."""
    if not limit or limit.get("pct") is None:
        return 0
    reset = limit.get("reset") or 0
    pts = [(t, p) for t, p, r in samples if r == reset and now - t <= PACE]
    if len(pts) < 2:
        return 0
    (t0, p0), (t1, p1) = pts[0], pts[-1]
    if t1 - t0 < 600 or p1 <= p0:
        return 0
    when = t1 + (100 - p1) * (t1 - t0) / (p1 - p0)
    # After the reset it does not matter: the limit is back to zero by then.
    return int(when) if not reset or when < reset else 0


def publish(now):
    """@junban_limits: every account seen lately, the one just recorded first."""
    rows = []
    for f in sorted(os.listdir(state_dir())):
        if not f.endswith(".json"):
            continue
        d = load(os.path.join(state_dir(), f))
        if not d.get("account") or now - d.get("ts", 0) > STALE:
            continue
        # The tighter of the two limits is the one that stops you.
        best = None
        for name in ("five_hour", "seven_day"):
            lim = d.get(name) or {}
            pct = lim.get("pct")
            if pct is None:
                continue
            reset = lim.get("reset") or 0
            # Past its reset the number is from the old window: count it as 0.
            if reset and reset < now:
                pct = 0
            if best is None or pct > best[1]:
                best = (name, pct, lim.get("eta") or 0, reset)
        if best:
            rows.append((d.get("ts", 0), d["account"], best))
    rows.sort(key=lambda r: -r[0])
    tmux("set", "-g", "@junban_limits",
         ";".join(f"{a}|{n}|{int(p)}|{e}|{r}" for _, a, (n, p, e, r) in rows))


def record():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    now = int(time.time())
    acct = account()
    pane = os.environ.get("TMUX_PANE")
    cw = data.get("context_window") or {}
    ctx = num(cw.get("total_input_tokens"))
    if pane:
        if ctx is not None:
            tmux("set", "-w", "-t", pane, "@junban_ctx", str(int(ctx)))
        tmux("set", "-w", "-t", pane, "@junban_acct", acct)
    rl = data.get("rate_limits")
    if not isinstance(rl, dict):
        return
    path = os.path.join(state_dir(), f"{acct}.json")
    d = load(path)
    d["account"], d["ts"] = acct, now
    for name in ("seven_day", "five_hour"):
        lim = rl.get(name)
        if not isinstance(lim, dict) or num(lim.get("used_percentage")) is None:
            d.pop(name, None)
            continue
        pct, reset = num(lim["used_percentage"]), int(num(lim.get("resets_at")) or 0)
        hist = [s for s in d.get(f"{name}_hist") or [] if isinstance(s, list) and len(s) == 3 and now - s[0] < KEEP]
        if not hist or hist[-1][1] != pct or hist[-1][2] != reset or now - hist[-1][0] >= STEP:
            hist.append([now, pct, reset])
        d[f"{name}_hist"] = hist
        d[name] = {"pct": pct, "reset": reset}
        d[name]["eta"] = eta(hist, d[name], now)
    write(path, d)
    publish(now)


# ---- install ------------------------------------------------------------------

def settings_path():
    return os.path.join(os.path.expanduser("~/.claude"), "settings.json")


def next_path():
    return os.path.join(state_dir(), "statusline-next")


def install():
    here = os.path.join(os.path.dirname(os.path.realpath(__file__)), "statusline.sh")
    p = settings_path()
    s = load(p)
    cur = (s.get("statusLine") or {}).get("command") or ""
    if cur.endswith("statusline.sh") and "junban" in cur:
        print("already in place")
        return
    if cur:
        with open(next_path(), "w") as fh:
            fh.write(cur)
    if os.path.exists(p):
        with open(p) as src, open(p + ".bak-junban-usage", "w") as dst:
            dst.write(src.read())
    s["statusLine"] = {"type": "command", "command": here}
    write(p, s)
    print(f"status line now runs {here}" + (f", then {cur}" if cur else ""))


def uninstall():
    p = settings_path()
    s = load(p)
    try:
        with open(next_path()) as fh:
            prev = fh.read().strip()
    except OSError:
        prev = ""
    if prev:
        s["statusLine"] = {"type": "command", "command": prev}
    else:
        s.pop("statusLine", None)
    write(p, s)
    try:
        os.remove(next_path())
    except OSError:
        pass
    print("status line restored")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "record":
        try:
            record()
        except Exception:
            pass  # never break a status line
    elif cmd == "install":
        install()
    elif cmd == "uninstall":
        uninstall()
    else:
        print(__doc__.strip())
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
