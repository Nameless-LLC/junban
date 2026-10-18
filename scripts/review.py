#!/usr/bin/env python3
"""What a finished turn changed, so you can pick what to review first.

    review.py start          UserPromptSubmit: remember HEAD and the time
    review.py done           Stop: @junban_review = "3 files +41 −88 · 2 commits · PR #12",
                             @junban_pr = the PR link the agent gave, if any
    review.py preview WIN    the Alt+f preview: the turn's diff stat, then the pane

A turn's change is the working tree against the HEAD it started from, plus
untracked files written since, so commits made during the turn count too. Other
agents in the same tree count as well: the tree is what you will review.

Runs async from the hook (Codex and Gemini through hook.sh), never holding the agent up.
"""
import json
import os
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True  # no __pycache__ inside the plugin directory
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from recap import last_reply  # noqa: E402
from name import tmux  # noqa: E402

PR_RE = re.compile(r"https?://[^\s)>\]`'\"]+/(?:pull|merge_requests)/(\d+)")


def git(cwd, *args, timeout=5):
    out = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=timeout)
    return out.stdout if out.returncode == 0 else None


def words():
    """The T_REVIEW_* strings for the user's language."""
    lang = tmux("show", "-gqv", "@junban-lang")
    if not lang:
        lang = (os.environ.get("LC_ALL") or os.environ.get("LANG") or "")[:2]
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    w = {}
    for name in ("en", lang):
        try:
            for line in open(os.path.join(here, "i18n", f"{name}.sh"), encoding="utf-8"):
                for part in line.strip().split("; "):
                    m = re.match(r'(T_REVIEW_\w+)="(.*)"$', part)
                    if m:
                        w[m.group(1)] = m.group(2)
        except OSError:
            continue
    return w


def agent_dir(pane, data):
    return data.get("cwd") or tmux("display", "-p", "-t", pane, "#{@junban_cwd}") or os.getcwd()


def summary(cwd, base, since, reply, w):
    parts = []
    if base and git(cwd, "rev-parse", "--verify", "-q", base + "^{commit}"):
        files = add = rm = 0
        for row in (git(cwd, "diff", "--numstat", base) or "").splitlines():
            a, d, _ = (row.split("\t") + ["", ""])[:3]
            files += 1
            add += int(a) if a.isdigit() else 0
            rm += int(d) if d.isdigit() else 0
        root = (git(cwd, "rev-parse", "--show-toplevel") or "").strip()
        for path in (git(cwd, "ls-files", "--others", "--exclude-standard") or "").splitlines()[:5000]:
            try:
                if os.path.getmtime(os.path.join(root, path)) >= since:
                    files += 1
            except OSError:
                pass
        commits = int((git(cwd, "rev-list", "--count", base + "..HEAD") or "0").strip() or 0)
        if files:
            label = w.get("T_REVIEW_FILE", "1 file") if files == 1 else w.get("T_REVIEW_FILES", "%d files") % files
            parts.append(f"{label} +{add} −{rm}")
        if commits:
            parts.append(w.get("T_REVIEW_COMMIT", "1 commit") if commits == 1
                         else w.get("T_REVIEW_COMMITS", "%d commits") % commits)
        if not files and not commits:
            parts.append(w.get("T_REVIEW_NONE", "no file changes"))
    prs = PR_RE.findall(reply)
    urls = [m.group(0) for m in PR_RE.finditer(reply)]
    if prs:
        parts.append(f"PR #{prs[-1]}")
    return " · ".join(parts), (urls[-1] if urls else "")


def main():
    pane = os.environ.get("TMUX_PANE")
    kind = sys.argv[1] if len(sys.argv) > 1 else ""
    if kind == "preview" and len(sys.argv) > 2:
        return preview(sys.argv[2])
    if not pane:
        return
    raw = sys.stdin.read()
    data = json.loads(raw) if raw.strip() else {}
    if not isinstance(data, dict):
        data = {}
    cwd = agent_dir(pane, data)
    if kind == "start":
        head = (git(cwd, "rev-parse", "HEAD") or "").strip()
        tmux("set", "-w", "-t", pane, "@junban_base", f"{head} {int(time.time())}")
    elif kind == "done":
        base, _, since = tmux("display", "-p", "-t", pane, "#{@junban_base}").partition(" ")
        line, url = summary(cwd, base, int(since) if since.isdigit() else int(time.time()), last_reply(data), words())
        # A new prompt may have come in while git ran.
        if tmux("display", "-p", "-t", pane, "#{@junban}") == "running":
            return
        for opt, val in (("@junban_review", line.replace("#", "＃")), ("@junban_pr", url)):
            if val:
                tmux("set", "-w", "-t", pane, opt, val)
            else:
                tmux("set", "-wu", "-t", pane, opt)
        for c in tmux("list-clients", "-F", "#{client_name}").splitlines():
            tmux("refresh-client", "-S", "-t", c)


def preview(win):
    """Diff stat of the turn on top (for ✓ windows), then the pane's last lines."""
    lines = int(os.environ.get("FZF_PREVIEW_LINES") or 30)
    state, base, cwd, path = (tmux("display", "-p", "-t", win,
                                   "#{@junban}\t#{@junban_base}\t#{@junban_cwd}\t#{pane_current_path}")
                              .split("\t") + ["", "", "", ""])[:4]
    top = []
    base = base.partition(" ")[0]
    if state == "done" and base:
        stat = git(cwd or path, "-c", "color.ui=always", "diff", "--stat=80", base) or ""
        top = stat.rstrip("\n").splitlines()[-(lines // 3):] if stat.strip() else []
        if top:
            top.append("")
    pane = subprocess.run(["tmux", "capture-pane", "-ep", "-t", win], capture_output=True, text=True).stdout
    body = [ln for ln in pane.splitlines() if ln.strip()][-(lines - len(top)):]
    print("\n".join(top + body))


try:
    main()
except Exception:
    pass
sys.exit(0)
