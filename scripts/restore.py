#!/usr/bin/env python3
"""Bring Claude Code windows back after tmux (or the machine) restarts.

  restore.py save          remember which window runs which Claude Code session
  restore.py rotate        after a server restart, keep that list as "previous"
  restore.py list [auto]   previous windows not open now, one per line:
                           index, picked-by-auto, session, window name, cwd, id
  restore.py open CMD N..  reopen entries N.. (or "all", "auto") with CMD --resume

The list lives in $XDG_STATE_HOME/junban/windows-<socket>.json, one per tmux
socket, tagged with the server pid: a different pid on the same socket means
the server restarted, and only then is anything reopened. Another tmux server
(tmux -L, a test run) keeps its own list.

auto picks what you would reopen by hand: an agent waiting on you, running,
or finished and not yet looked at, and anything active in the last day, except
windows marked z (untouched for @junban-stale-hours).
"""
import glob
import hashlib
import json
import os
import subprocess
import sys
import time

DAY = 86400


def tmux(*args):
    return subprocess.run(["tmux", *args], capture_output=True, text=True, timeout=5).stdout


def state_dir():
    d = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "junban")
    os.makedirs(d, mode=0o700, exist_ok=True)
    return d


def server():
    out = tmux("display", "-p", "#{socket_path}\t#{pid}").strip().split("\t")
    return (out + ["", ""])[:2]


def load(name):
    try:
        with open(os.path.join(state_dir(), name)) as fh:
            d = json.load(fh)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def write(name, data):
    path = os.path.join(state_dir(), name)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        json.dump(data, fh)
    os.replace(tmp, path)


def parent(pid):
    try:
        with open(f"/proc/{pid}/stat") as fh:
            return int(fh.read().rsplit(")", 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
        out = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
        return int(out) if out.isdigit() else 0


def descends(pid, ancestor):
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


def sessions():
    """Claude Code's own records: {"session:@win.%pane": record}."""
    live = {}
    for f in glob.glob(os.path.expanduser("~/.claude/sessions/*.json")):
        try:
            with open(f) as fh:
                d = json.load(fh)
        except Exception:
            continue
        if isinstance(d, dict) and isinstance(d.get("tmux"), str) and ".%" in d["tmux"] and d.get("sessionId"):
            live[d["tmux"]] = d
    return live


def current():
    """Windows of this server that run a Claude Code session."""
    live = sessions()
    out = []
    rows = tmux("list-panes", "-a", "-F",
                "#{session_name}\t#{window_id}\t#{pane_id}\t#{pane_pid}\t#{window_name}\t#{@junban}\t#{@junban_ts}\t#{@junban_stale}")
    seen = set()
    for row in rows.splitlines():
        sess, wid, pane, ppid, name, st, ts, stale = (row.split("\t") + [""] * 8)[:8]
        d = live.get(f"{sess}:{wid}.{pane}")
        if not d or wid in seen or not descends(d.get("pid"), ppid):
            continue
        seen.add(wid)
        out.append({"session": sess, "name": name, "cwd": d.get("cwd") or "", "id": d["sessionId"],
                    "state": st, "ts": int(ts) if ts.isdigit() else 0, "stale": bool(stale)})
    return out


def names(sock):
    k = hashlib.sha1(sock.encode()).hexdigest()[:10]
    return f"windows-{k}.json", f"windows-{k}.prev.json"


def save():
    sock, pid = server()
    if not sock:
        return
    cur, _ = names(sock)
    old = load(cur)
    # A list from before a restart waits for rotate; never overwrite it here.
    if old.get("socket") == sock and old.get("pid") != pid:
        return
    write(cur, {"socket": sock, "pid": pid, "saved": int(time.time()), "windows": current()})


def rotate():
    sock, pid = server()
    if not sock:
        return
    cur, prev = names(sock)
    old = load(cur)
    if old.get("socket") == sock and old.get("pid") != pid:
        write(prev, old)
        os.remove(os.path.join(state_dir(), cur))
        print("rotated")


def picked(w, now):
    if w.get("stale"):
        return False
    if w.get("state") in ("waiting", "running", "done"):
        return True
    return now - int(w.get("ts") or 0) < DAY


def candidates():
    prev = load(names(server()[0])[1])
    open_ids = {d["sessionId"] for d in sessions().values()}
    now = time.time()
    out = []
    for i, w in enumerate(prev.get("windows") or []):
        if not isinstance(w, dict) or not w.get("id") or w["id"] in open_ids:
            continue
        if not os.path.isdir(w.get("cwd") or ""):
            continue
        out.append((i, picked(w, now), w))
    return out


def reopen(cmd, w):
    run = f"{cmd} --resume {w['id']}; exec $SHELL"
    sess, name, cwd = w.get("session") or "junban", w.get("name") or "claude", w["cwd"]
    if subprocess.run(["tmux", "has-session", "-t", f"={sess}"], capture_output=True).returncode == 0:
        wid = tmux("new-window", "-d", "-P", "-F", "#{window_id}", "-t", f"={sess}:", "-n", name, "-c", cwd, run).strip()
    else:
        tmux("new-session", "-d", "-s", sess, "-n", name, "-c", cwd, run)
        wid = tmux("display", "-p", "-t", f"={sess}:", "#{window_id}").strip()
    if wid:
        # Keep the task name it had, not "claude".
        tmux("set", "-w", "-t", wid, "automatic-rename", "off")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "save":
        save()
    elif cmd == "rotate":
        rotate()
    elif cmd == "list":
        auto = sys.argv[2:3] == ["auto"]
        for i, p, w in candidates():
            if auto and not p:
                continue
            print("\t".join(str(x) for x in (i, int(p), w.get("session", ""), w.get("name", ""), w["cwd"], w["id"])))
    elif cmd == "open" and len(sys.argv) > 3:
        agent, which = sys.argv[2], sys.argv[3:]
        n = 0
        for i, p, w in candidates():
            if which == ["all"] or (which == ["auto"] and p) or str(i) in which:
                reopen(agent, w)
                n += 1
        print(n)


try:
    main()
except Exception:
    pass
