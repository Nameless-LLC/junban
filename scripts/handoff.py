#!/usr/bin/env python3
"""Keep agent sessions short without losing the thread.

A long session costs more on every turn: each request re-reads the whole
conversation, and once an agent has sat idle past the prompt cache, the next
prompt pays to write all of it again. Clearing is cheap; losing what the
session knew is not. So the agent writes down what matters first, and the
fresh session starts from that note.

    handoff.py stop    Stop hook (sync). Past @junban-handoff-tokens, asks the
                       agent once to reply with a handoff note before it stops,
                       and saves the note from that reply (no file permission
                       needed, and you see the summary too).
    handoff.py start   SessionStart hook. After junban cleared a session, hands
                       the new one the note and the git state. After a /clear or
                       a new start of your own, only points at a recent note.
    handoff.py reset   Heartbeat (summary.sh). Clears a session that is long,
                       has a fresh note, has nothing scheduled or running in
                       the background, and has sat idle for
                       @junban-reset-minutes, by typing /clear into it, but
                       only when its input box is empty and no one is looking
                       at the window. The old session stays in /resume.

    @junban-handoff          off | on      (default off)
    @junban-handoff-tokens   context size that asks for a note (default 120000)
    @junban-reset-minutes    idle minutes before the clear (default 60; 0 = never)

Notes live in $XDG_STATE_HOME/junban/handoff/, readable by you only. Resets are
logged to resets.tsv (time, window, tokens, note). Every path exits 0.
"""
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from recap import last_reply  # noqa: E402  (the agent's final message, payload or transcript)

STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
                     "junban")
NOTES = os.path.join(STATE, "handoff")
POINTER_HOURS = 24

ASK = """junban: this conversation is now {tokens:,} tokens and may be cleared while \
idle. Before you stop, reply with a handoff note so that a fresh session can carry on \
with nothing lost. Put it between a line <handoff> and a line </handoff>; junban saves \
it, so do not write a file. Use the language the user writes in, under these headings:

1. Goal: what the user wants, in their words, with every constraint and preference they stated
2. State: what is done, in progress, not started; what was verified, and how
3. Decisions: what was decided and why; what the user approved or turned down
4. Dead ends: what was tried and failed, and why, so it is not tried again
5. Next: the exact next step, and any question still open for the user
6. Pointers: the files, commands, URLs and IDs the next step needs

Keep it under 80 lines. Leave out what git already holds (diffs, logs)."""

RESUMED = """junban cleared the previous session ({sid}) after it sat idle, to keep the \
context short; the user can reopen it with /resume. That session wrote the handoff \
note below for you. Treat it as what you knew; wait for the user's next request \
rather than acting on it.

{note}

Git state now:
{git}"""

POINTER = """A handoff note from an earlier session in this directory, written {when}: \
{path}. Read it only if the user's request continues that work."""


def tmux(*args):
    try:
        return subprocess.run(["tmux", *args], capture_output=True, text=True,
                              timeout=3).stdout.rstrip("\n")
    except Exception:
        return ""


def opt(name, default):
    return tmux("show-option", "-gqv", name).strip() or default


def num(name, default):
    try:
        return int(opt(name, str(default)))
    except ValueError:
        return default


def on():
    # claude -p and the SDKs (CLAUDE_CODE_ENTRYPOINT=sdk-*) return their last reply
    # to a script: a note in its place would break the script.
    if os.environ.get("CLAUDE_CODE_ENTRYPOINT", "").startswith("sdk"):
        return False
    return opt("@junban-handoff", "off") == "on"


def payload():
    try:
        raw = sys.stdin.read()
        data = json.loads(raw) if raw.strip() else {}
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def context_tokens(transcript):
    """What the next request will carry: the last main-thread reply's input
    (fresh, cache write, cache read) plus its output. Subagents run in their own
    context, and <synthetic> rows are Claude Code's own, so both are skipped."""
    try:
        with open(transcript, "rb") as fh:
            fh.seek(0, 2)
            fh.seek(max(0, fh.tell() - 2_000_000))
            lines = fh.read().decode("utf-8", "replace").splitlines()
    except (OSError, TypeError):
        return 0
    for raw in reversed(lines):
        if '"usage"' not in raw:
            continue
        try:
            row = json.loads(raw)
        except ValueError:
            continue
        msg = row.get("message") or {}
        if row.get("type") != "assistant" or row.get("isSidechain") or msg.get("model") == "<synthetic>":
            continue
        u = msg.get("usage") or {}
        return sum(int(u.get(k) or 0) for k in ("input_tokens", "cache_creation_input_tokens",
                                                "cache_read_input_tokens", "output_tokens"))
    return 0


def tree_key(cwd):
    return hashlib.sha1(os.path.realpath(cwd or ".").encode()).hexdigest()[:12]


def note_path(cwd, sid):
    return os.path.join(NOTES, f"{tree_key(cwd)}-{(sid or 'session')[:8]}.md")


def ensure_dir():
    # Notes name clients, hosts and code: readable by you only.
    os.makedirs(NOTES, mode=0o700, exist_ok=True)
    os.chmod(STATE, 0o700)
    os.chmod(NOTES, 0o700)


def setw(pane, name, value):
    if value == "":
        tmux("set", "-wu", "-t", pane, name)
    else:
        tmux("set", "-w", "-t", pane, name, str(value))


def getw(pane, name):
    return tmux("display", "-p", "-t", pane, "#{" + name + "}")


def git_state(cwd):
    out = []
    for args in (["status", "--short", "--branch"], ["log", "--oneline", "-8"]):
        try:
            r = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=3)
            if r.returncode == 0 and r.stdout.strip():
                out.append("\n".join(r.stdout.strip().splitlines()[:30]))
        except Exception:
            pass
    return "\n\n".join(out) or "(not a git repository)"


def stop():
    data = payload()
    pane = os.environ.get("TMUX_PANE")
    if not pane or not on():
        return
    sid = str(data.get("session_id") or "")
    cwd = data.get("cwd") or os.getcwd()
    # The reply's own row can reach the transcript a moment after Stop fires
    # (seen on 2.1.319); on a first turn there is nothing else to read.
    tokens = 0
    for _ in range(10):
        tokens = context_tokens(data.get("transcript_path"))
        if tokens:
            break
        time.sleep(0.2)
    setw(pane, "@junban_ctx", tokens or "")
    setw(pane, "@junban_agent_pane", pane)
    # /clear would drop what is still due to wake this session: a /loop or
    # ScheduleWakeup (session_crons), or work still running in the background.
    busy = bool(data.get("session_crons")) or bool(data.get("background_tasks"))
    setw(pane, "@junban_handoff_hold", "1" if busy else "")
    path = note_path(cwd, sid)
    asked_sid, _, asked_at = getw(pane, "@junban_handoff_asked").partition(" ")
    if data.get("stop_hook_active"):
        # The turn we asked for: save the note it replied with (or nothing, if it declined).
        m = NOTE.search(last_reply(data) or "")
        if m and asked_sid == sid and m.group(1).strip():
            ensure_dir()
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(m.group(1).strip() + "\n")
            setw(pane, "@junban_handoff", path)
        return
    limit = num("@junban-handoff-tokens", 120000)
    if limit <= 0 or tokens < limit:
        return
    # Once per session, and again only after it has grown by half a limit:
    # asking every turn would turn each answer into two.
    if asked_sid == sid and asked_at.isdigit() and tokens < int(asked_at) + limit // 2:
        return
    ensure_dir()
    setw(pane, "@junban_handoff_asked", f"{sid} {tokens}")
    print(json.dumps({"decision": "block", "reason": ASK.format(tokens=tokens)}))


def start():
    data = payload()
    pane = os.environ.get("TMUX_PANE")
    if not pane or not on():
        return
    source = data.get("source") or ""
    cwd = data.get("cwd") or os.getcwd()
    text = ""
    pending = getw(pane, "@junban_handoff_pending")
    if pending:
        setw(pane, "@junban_handoff_pending", "")
    if source == "clear" and pending:
        note_file, _, old_sid = pending.partition("\t")
        try:
            with open(note_file, encoding="utf-8", errors="replace") as fh:
                note = fh.read().strip()
        except OSError:
            note = ""
        if note:
            text = RESUMED.format(sid=old_sid or "?", note=note, git=git_state(cwd))
    elif source in ("startup", "clear"):
        notes = [p for p in glob.glob(os.path.join(NOTES, tree_key(cwd) + "-*.md"))
                 if time.time() - os.path.getmtime(p) < POINTER_HOURS * 3600]
        if notes:
            p = max(notes, key=os.path.getmtime)
            when = time.strftime("%Y-%m-%d %H:%M", time.localtime(os.path.getmtime(p)))
            text = POINTER.format(when=when, path=p)
    if text:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                                 "additionalContext": text}}))


NOTE = re.compile(r"^<handoff>\s*$(.*?)^</handoff>\s*$", re.S | re.M)
RULE = re.compile(r"^\s*─{20,}\s*$")
EMPTY = re.compile(r"^\s*[>❯]\s*$")


DIM = re.compile(r"\x1b\[2m.*?(?:\x1b\[(?:0|22)?m|$)")
SGR = re.compile(r"\x1b\[[0-9;:]*m")


def input_empty(pane):
    """True only when the screen shows Claude Code's input box with nothing in
    it: one prompt line between the last two rules. The suggestion an empty box
    shows ("Try ...") is drawn dim, so dim text does not count. Anything else
    (a draft, a dialog, a different UI) is a reason not to type."""
    lines = [SGR.sub("", DIM.sub("", ln)).replace("\u00a0", " ")
             for ln in tmux("capture-pane", "-e", "-p", "-t", pane).splitlines()]
    rules = [i for i, ln in enumerate(lines) if RULE.match(ln)]
    if len(rules) < 2 or rules[-1] - rules[-2] != 2:
        return False
    return bool(EMPTY.match(lines[rules[-2] + 1]))


def reset():
    if not on():
        return
    minutes = num("@junban-reset-minutes", 60)
    limit = num("@junban-handoff-tokens", 120000)
    if minutes <= 0 or limit <= 0:
        return
    now = time.time()
    try:
        last = float(opt("@junban-handoff-scan-at", "0"))
    except ValueError:
        last = 0
    if now - last < 60:
        return
    tmux("set", "-g", "@junban-handoff-scan-at", str(int(now)))
    rows = tmux("list-windows", "-a", "-F",
                "#{window_id}\t#{@junban}\t#{@junban_ts}\t#{@junban_act}\t#{@junban_ctx}"
                "\t#{@junban_handoff}\t#{@junban_agent_pane}\t#{@junban_handoff_asked}"
                "\t#{window_active}\t#{session_attached}\t#{@junban_handoff_hold}"
                "\t#{session_name}:#{window_name}")
    for row in rows.splitlines():
        f = (row.split("\t") + [""] * 12)[:12]
        wid, state, ts, act, ctx, note, pane, asked, active, attached, hold, name = f
        if hold:
            continue
        # Only windows you have already looked at: a ✓ still holds a result to read.
        if state != "idle" or not pane or not note or not ctx.isdigit() or int(ctx) < limit:
            continue
        if active == "1" and attached not in ("", "0"):
            continue
        quiet_since = max(int(ts) if ts.isdigit() else 0, int(act) if act.isdigit() else 0)
        if not quiet_since or now - quiet_since < minutes * 60:
            continue
        try:
            # The note has to come from the session's last stretch of work.
            if quiet_since - os.path.getmtime(note) > 600:
                continue
        except OSError:
            continue
        if not input_empty(pane):
            continue
        sid = asked.partition(" ")[0]
        setw(pane, "@junban_handoff_pending", f"{note}\t{sid}")
        for o in ("@junban_handoff", "@junban_ctx", "@junban_handoff_asked"):
            setw(pane, o, "")
        tmux("send-keys", "-t", pane, "-l", "/clear")
        time.sleep(0.3)
        tmux("send-keys", "-t", pane, "Enter")
        try:
            ensure_dir()
            with open(os.path.join(STATE, "resets.tsv"), "a", encoding="utf-8") as fh:
                fh.write(f"{int(now)}\t{name.replace(chr(9), ' ')}\t{ctx}\t{note}\n")
        except OSError:
            pass


def main():
    kind = sys.argv[1] if len(sys.argv) > 1 else ""
    {"stop": stop, "start": start, "reset": reset}.get(kind, lambda: None)()


try:
    main()
except Exception:
    pass
