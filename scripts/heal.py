#!/usr/bin/env python3
"""Repair states that hooks alone cannot get right.

Hooks have blind spots: pressing Esc mid-turn fires no Stop hook, and killing
the agent can skip SessionEnd. Every hook-only status plugin therefore shows a
"running" badge forever on an agent that is actually sitting idle.

Claude Code keeps its own live status in ~/.claude/sessions/<pid>.json,
including which tmux pane it runs in ("session:@window.%pane"). When that file
says idle and is newer than our last transition, we believe it.
We also drop badges from windows whose agent process is gone.
"""
import glob
import json
import os
import subprocess
import time

GRACE = 3  # seconds; the session file can lag a hook by a moment
SHELLS = {"bash", "zsh", "fish", "sh", "dash", "ksh", "tcsh", "nu"}


def tmux(*args):
    return subprocess.run(["tmux", *args], capture_output=True, text=True, timeout=3).stdout


def parent(pid):
    try:
        with open(f"/proc/{pid}/stat") as fh:
            return int(fh.read().rsplit(")", 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
        out = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)],
                             capture_output=True, text=True).stdout.strip()
        return int(out) if out.isdigit() else 0


def descends(pid, ancestor):
    """True if pid runs inside the pane whose shell is `ancestor` — this rules out
    a same-named pane on another tmux server, and dead or recycled pids."""
    try:
        pid, ancestor = int(pid), int(ancestor)
    except (TypeError, ValueError):
        return False
    for _ in range(32):
        if pid == ancestor:
            return True
        if pid <= 1:
            return False
        pid = parent(pid)
    return False


def main():
    rows = tmux("list-panes", "-a", "-F",
                "#{window_id}\t#{pane_id}\t#{@junban}\t#{@junban_ts}\t#{pane_current_command}\t#{session_name}\t#{pane_pid}").splitlines()
    windows = {}
    for row in rows:
        wid, pane, state, ts, cmd, sess, ppid = (row.split("\t") + [""] * 7)[:7]
        # One odd value (hand-set, from an old version) must not stop the rest.
        w = windows.setdefault(wid, {"state": state, "ts": int(ts) if ts.isdigit() else 0, "panes": [], "cmds": []})
        # Pane ids are only unique per tmux server, so key on the full location
        w["panes"].append((f"{sess}:{wid}.{pane}", ppid))
        w["cmds"].append(cmd)
    stale = {w: v for w, v in windows.items() if v["state"] == "running"}
    if not stale:
        return

    live = {}
    for f in glob.glob(os.path.expanduser("~/.claude/sessions/*.json")):
        try:
            with open(f) as fh:
                d = json.load(fh)
        except Exception:
            continue
        loc = d.get("tmux") if isinstance(d, dict) else None
        if isinstance(loc, str) and ".%" in loc:
            live[loc] = d

    now = time.time()
    for wid, v in stale.items():
        try:
            fix(wid, v, live, now)
        except Exception:
            continue


def fix(wid, v, live, now):
    sessions = [live[loc] for loc, ppid in v["panes"]
                if loc in live and descends(live[loc].get("pid"), ppid)]
    if not sessions:
        # Not a Claude Code pane (or it has exited). Only clear it when every
        # pane is back at a bare shell, so other agents driving state.sh survive.
        if all(c in SHELLS for c in v["cmds"]) and now - v["ts"] > GRACE:
            tmux("set", "-w", "-t", wid, "@junban", "idle")
            # The shell is the pane's directory again, not the agent's worktree.
            for loc, _ in v["panes"]:
                tmux("set", "-pu", "-t", loc.rsplit(".", 1)[1], "@junban_cwd")
        return
    if all(s.get("status") == "idle" and
           s.get("statusUpdatedAt", 0) / 1000 > v["ts"] + GRACE for s in sessions):
        tmux("set", "-w", "-t", wid, "@junban", "idle")


try:
    main()
except Exception:
    pass
