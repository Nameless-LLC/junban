#!/usr/bin/env python3
"""One line on what an agent needs from you, so you can triage without switching.

    recap.py done     Stop hook: what came of the turn ("tests pass, PR #12 opened")
    recap.py ask      PreToolUse(AskUserQuestion): the question it is asking
    recap.py notify   Notification(permission_prompt…): what it wants permission for
                      (or, from Codex's PermissionRequest, the tool call itself)

The line goes on the window as @junban_recap; the guide line and the Alt+f list
show it. A new prompt clears it (state.sh). Finished turns are also appended to
$XDG_STATE_HOME/junban/done.tsv (end, window, prompt, recap) for later digests.

    @junban-recap   on | off   (default on)
      Uses the namer model (@junban-namer-url / -model) when one is set, else the
      first meaningful line of the agent's final message.

Runs async from the hook, so a slow model never holds the agent up.
"""
import json
import os
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True  # no __pycache__ inside the plugin directory
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from name import ask_llm, tmux  # noqa: E402  (same model settings as window names)

MAX_CHARS = 60


def strip_md(line):
    line = re.sub(r"`([^`]*)`", r"\1", line)
    line = re.sub(r"\*\*([^*]*)\*\*|__([^_]*)__", lambda m: m.group(1) or m.group(2), line)
    line = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", line)
    line = re.sub(r"^\s*(#+|[-*+]|\d+[.)]|>)\s+", "", line)
    return re.sub(r"\s+", " ", line).strip(" |")


def first_line(text):
    """The first line that says something: agents tend to lead with the outcome."""
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    for line in text.splitlines():
        if line.lstrip().startswith("#"):  # a heading names the section, not the outcome
            continue
        line = strip_md(line)
        if len(line) >= 4 and not re.fullmatch(r"[-=|: ]+", line):
            # Without a model the first sentence is the summary; the rest only
            # gets cut off on the guide line.
            m = re.match(r"(.{4,}?[。！？]|.{4,}?[.!?](?=\s))", line)
            return m.group(1) if m else line
    return ""


def last_reply(data):
    """The agent's final message: from the hook payload when it carries it,
    otherwise the last assistant text in the transcript."""
    for key in ("last_assistant_message", "prompt_response"):  # Claude/Codex, Gemini
        text = data.get(key)
        # Gemini sends "[no response text]" when the turn failed before replying.
        if isinstance(text, str) and text.strip() and text.strip() != "[no response text]":
            return text
    path = data.get("transcript_path")
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()[-300:]
    except (OSError, TypeError):
        return ""
    for raw in reversed(lines):
        if '"assistant"' not in raw:
            continue
        try:
            row = json.loads(raw)
        except ValueError:
            continue
        if row.get("type") != "assistant":
            continue
        parts = [c.get("text", "") for c in (row.get("message") or {}).get("content") or []
                 if isinstance(c, dict) and c.get("type") == "text"]
        if any(p.strip() for p in parts):
            return "\n".join(parts)
    return ""


def permission_line(data):
    """Codex's PermissionRequest carries the tool call, not a message:
    "Bash: psql -c 'drop table…'" says what you are about to approve."""
    tool = " ".join(str(data.get("tool_name") or "").split())
    args = data.get("tool_input") or {}
    detail = ""
    if isinstance(args, dict):
        for key in ("command", "cmd", "file_path", "path", "url", "description"):
            v = args.get(key)
            if v:
                detail = " ".join(v) if isinstance(v, list) else str(v)
                break
    elif args:
        detail = str(args)
    detail = " ".join(detail.split())
    return f"{tool}: {detail}" if tool and detail else tool or detail


def gemini_line(data):
    """Gemini's ToolPermission message is generic ("Tool Confirm Shell Command
    requires execution"); its details carry what it actually wants to do."""
    d = data.get("details")
    if not isinstance(d, dict):
        return ""
    what = next((str(d[k]) for k in ("command", "filePath", "fileName", "url", "prompt") if d.get(k)), "")
    label = "Shell" if d.get("type") == "exec" else " ".join(str(d.get("title") or d.get("type") or "").split())
    what = " ".join(what.split())
    return f"{label}: {what}" if label and what else what


def recap_system():
    lang = tmux("show", "-gqv", "@junban-lang")
    if not lang:
        lang = (os.environ.get("LC_ALL") or os.environ.get("LANG") or "")[:2]
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for name in (lang, "en"):
        try:
            for line in open(os.path.join(here, "i18n", f"{name}.sh"), encoding="utf-8"):
                if line.startswith("RECAP_SYSTEM="):
                    return line.split("=", 1)[1].strip().strip('"')
        except OSError:
            continue
    return ""


def summarise(reply):
    line = ""
    if tmux("show", "-gqv", "@junban-namer-url") and tmux("show", "-gqv", "@junban-namer-model"):
        try:
            # Head and tail: the outcome is usually stated first, the open question last.
            body = reply if len(reply) < 3000 else reply[:1800] + "\n…\n" + reply[-1000:]
            line = ask_llm([body], system=recap_system(), max_tokens=48)
        except Exception:
            line = ""
    return line or first_line(reply)


def main():
    pane = os.environ.get("TMUX_PANE")
    kind = sys.argv[1] if len(sys.argv) > 1 else ""
    if not pane or (tmux("show", "-gqv", "@junban-recap") or "on") == "off":
        return
    raw = sys.stdin.read()
    data = json.loads(raw) if raw.strip() else {}

    if kind == "ask":
        qs = ((data.get("tool_input") or {}).get("questions") or [{}])
        line = strip_md(str(qs[0].get("question") or "")) if qs else ""
    elif kind == "notify":
        line = gemini_line(data) or strip_md(str(data.get("message") or "")) or permission_line(data)
    elif kind == "done":
        line = summarise(last_reply(data))
    else:
        return
    line = line.replace("#", "＃").replace("\t", " ")[:MAX_CHARS].rstrip()
    # A slow model can answer after you have already sent the next prompt.
    if kind == "done" and tmux("display", "-p", "-t", pane, "#{@junban}") == "running":
        return
    if line:
        tmux("set", "-w", "-t", pane, "@junban_recap", line)
    if kind != "done":
        return
    win = tmux("display", "-p", "-t", pane, "#{session_name}:#{window_name}").replace("\t", " ")
    prompt = tmux("display", "-p", "-t", pane, "#{@junban_prompt}").replace("\t", " ")
    state_dir = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "junban")
    try:
        # Prompts and recaps can name clients and code: readable by you only.
        os.makedirs(state_dir, mode=0o700, exist_ok=True)
        os.chmod(state_dir, 0o700)
        path = os.path.join(state_dir, "done.tsv")
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "a", encoding="utf-8") as fh:
            if line:
                fh.write(f"{int(time.time())}\t{win}\t{prompt}\t{line}\n")
    except OSError:
        pass
    # state.sh leaves the ✓ notification to us when recaps are on, so the phone
    # gets "✓ CI fix: tests pass" rather than just a window name. Not if you
    # already opened it.
    ncmd = tmux("show", "-gqv", "@junban-notify-cmd")
    # With @junban-done-batch, digest.sh sends finished turns together.
    batch = tmux("show", "-gqv", "@junban-done-batch")
    if batch.isdigit() and int(batch) > 0:
        ncmd = ""
    if ncmd and tmux("display", "-p", "-t", pane, "#{@junban}") == "done":
        name = tmux("display", "-p", "-t", pane, "#{window_name}")
        msg = f"✓ {name}: {line}" if line else f"✓ {name}"
        subprocess.run(["sh", "-c", ncmd], input=msg + "\n", text=True,
                       capture_output=True, timeout=10)
    for c in tmux("list-clients", "-F", "#{client_name}").splitlines():
        tmux("refresh-client", "-S", "-t", c)


if __name__ == "__main__":  # review.py imports last_reply from here
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
