#!/usr/bin/env python3
"""Spot the two habits that quietly cost the most when running many agents.

1. Two agents in one working tree. They overwrite each other's edits and one of
   them ends up committing the other's half-done work. Separate git worktrees
   fix it. Windows that share a tree get @junban_shared = <count>.
2. Agents parked for days. The list grows until the one that needs you is
   lost among them. Idle/done windows untouched for @junban-stale-hours
   (default 24) get @junban_stale = <hours>.

Runs from summary.sh on every status refresh, but does real work at most once
per @junban-scan-interval seconds (default 30): it shells out to git.

`scan.py --tree PATH` prints how many agent windows already work in PATH's
working tree (used by new.sh to decide whether to start in a new worktree).
"""
import os
import subprocess
import sys
import time


def tmux(*args):
    return subprocess.run(["tmux", *args], capture_output=True, text=True, timeout=3).stdout


def opt(name, default):
    v = tmux("show-option", "-gqv", name).strip()
    return v or default


_tops = {}


def toplevel(path):
    """The working tree root for path, or None when it is not worth checking.
    A linked worktree has its own root, so separate worktrees never collide.
    $HOME is skipped: a dotfiles repo there would make every agent "shared"."""
    if not path:
        return None
    if path not in _tops:
        try:
            out = subprocess.run(["git", "-C", path, "rev-parse", "--show-toplevel"],
                                 capture_output=True, text=True, timeout=2)
            top = out.stdout.strip() if out.returncode == 0 else None
        except Exception:
            top = None
        if top and os.path.realpath(top) == os.path.realpath(os.path.expanduser("~")):
            top = None
        _tops[path] = top
    return _tops[path]


def agent_windows(leftovers=None):
    """{window_id: {...}} for windows an agent has registered in (@junban set).
    Windows that still carry our flags without an agent go into `leftovers`."""
    wins = {}
    rows = tmux("list-panes", "-a", "-F",
                "#{window_id}\t#{@junban}\t#{@junban_ts}\t#{pane_current_path}"
                "\t#{@junban_shared}\t#{@junban_stale}\t#{@junban_cwd}").splitlines()
    for row in rows:
        wid, state, ts, path, shared, stale, cwd = (row.split("\t") + [""] * 7)[:7]
        # The directory the agent's hooks ran in (state.sh) beats pane_current_path,
        # which shows the launching shell's directory, not a worktree claude moved to.
        path = cwd or path
        if not state:
            if leftovers is not None and (shared or stale):
                leftovers.add(wid)
            continue
        w = wins.setdefault(wid, {"state": state, "ts": int(ts or 0), "paths": [],
                                  "shared": shared, "stale": stale})
        w["paths"].append(path)
    return wins


def trees(wins):
    """{toplevel: [window_id, ...]}; a window counts once per tree."""
    out = {}
    for wid, w in wins.items():
        for top in {toplevel(p) for p in w["paths"]} - {None}:
            out.setdefault(top, []).append(wid)
    return out


def setw(wid, name, value):
    if value:
        tmux("set", "-w", "-t", wid, name, str(value))
    else:
        tmux("set", "-wu", "-t", wid, name)


def scan():
    now = time.time()
    try:
        every = int(opt("@junban-scan-interval", "30"))
    except ValueError:
        every = 30
    try:
        last = float(opt("@junban-scan-at", "0"))
    except ValueError:
        last = 0
    if now - last < every:
        return
    tmux("set", "-g", "@junban-scan-at", str(int(now)))

    leftovers = set()
    wins = agent_windows(leftovers)
    for wid in leftovers - set(wins):
        setw(wid, "@junban_shared", "")
        setw(wid, "@junban_stale", "")

    shared = {}
    if opt("@junban-shared-check", "on") == "on":
        for wids in trees(wins).values():
            if len(wids) > 1:
                for wid in wids:
                    shared[wid] = len(wids)

    try:
        hours = float(opt("@junban-stale-hours", "24"))
    except ValueError:
        hours = 24
    for wid, w in wins.items():
        stale = ""
        if hours > 0 and w["state"] in ("idle", "done") and w["ts"]:
            age = (now - w["ts"]) / 3600
            if age >= hours:
                stale = int(age)
        if str(shared.get(wid, "")) != w["shared"]:
            setw(wid, "@junban_shared", shared.get(wid, ""))
        if str(stale) != w["stale"]:
            setw(wid, "@junban_stale", stale)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--tree":
        top = toplevel(sys.argv[2])
        print(len(trees(agent_windows()).get(top, [])) if top else 0)
        return
    scan()


try:
    main()
except Exception:
    if len(sys.argv) == 3:
        print(0)
