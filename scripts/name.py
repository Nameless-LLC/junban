#!/usr/bin/env python3
"""Keep each window named after what its agent is working on *now*.

Runs from the UserPromptSubmit hook (async, so it never delays the agent).

    @junban-rename   off | prompt | llm      (default: prompt)
      prompt  first meaningful line of what you typed
      llm     ask a model to summarise the last few prompts; falls back to prompt
    @junban-namer-url    e.g. http://localhost:11434 (Ollama) or https://api.openai.com/v1
    @junban-namer-model  e.g. qwen3:8b, gpt-4o-mini
    @junban-namer-key    name of the env var holding the API key (OpenAI-compatible only)

Rules that keep names stable:
  * short replies ("ok", "yes", "進めて", "ครับ") never rename
  * a window you renamed yourself is left alone forever
  * slash commands, shell escapes, pasted blobs and code fences are ignored
"""
import json
import os
import re
import subprocess
import sys
import urllib.request

MIN_CHARS, MAX_CHARS, TURNS, TIMEOUT = 8, 24, 4, 6

FILLER = re.compile(
    r"^(ok|okay|yes|no|y|n|sure|go|go ahead|continue|thanks|thank you|lgtm|do it|fix it|"
    r"はい|いいえ|うん|了解|ok です|お願い|お願いします|よろしく|続けて|進めて|やって|直して|調べて|"
    r"ありがとう|なるほど|確認|完了|できた|"
    r"ได้|โอเค|ครับ|ค่ะ|ต่อ|ทำต่อ|ขอบคุณ)[\s。.!！]*$",
    re.I)


def tmux(*a):
    return subprocess.run(["tmux", *a], capture_output=True, text=True, timeout=3).stdout.strip()


def clean(text):
    text = re.sub(r"<pasted_content.*?</pasted_content[^>]*>", " ", text, flags=re.S)
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    text = re.sub(r"<[^>]+>", " ", text)
    for line in text.splitlines():
        line = re.sub(r"\s+", " ", line.strip().strip("`\"'"))
        if line and not line.startswith(("/", "!", "#")):
            return line
    return ""


def recent_prompts(path):
    """Earlier prompts from the transcript ('last-prompt' rows only:
    plain user rows also carry tool results)."""
    out = []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()[-400:]
    except (OSError, TypeError):
        return out
    for raw in lines:
        if '"last-prompt"' not in raw:
            continue
        try:
            p = clean(json.loads(raw).get("lastPrompt") or "")
        except ValueError:
            continue
        if p and (not out or out[-1] != p):
            out.append(p)
    return out


def system_prompt():
    lang = tmux("show", "-gqv", "@junban-lang")
    if not lang:
        loc = os.environ.get("LC_ALL") or os.environ.get("LANG") or ""
        lang = loc[:2]
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for name in (lang, "en"):
        try:
            for line in open(os.path.join(here, "i18n", f"{name}.sh"), encoding="utf-8"):
                if line.startswith("NAMER_SYSTEM="):
                    return line.split("=", 1)[1].strip().strip('"')
        except OSError:
            continue
    return ""


def ask_llm(context, system=None, max_tokens=32):
    url = tmux("show", "-gqv", "@junban-namer-url").rstrip("/")
    model = tmux("show", "-gqv", "@junban-namer-model")
    if not url or not model:
        return ""
    msgs = [{"role": "system", "content": system or system_prompt()},
            {"role": "user", "content": "\n".join("- " + c for c in context)}]
    headers = {"Content-Type": "application/json"}
    if url.endswith("/v1"):  # OpenAI-compatible
        endpoint = url + "/chat/completions"
        body = {"model": model, "messages": msgs, "temperature": 0.2, "max_tokens": max_tokens}
        key = os.environ.get(tmux("show", "-gqv", "@junban-namer-key") or "OPENAI_API_KEY", "")
        if key:
            headers["Authorization"] = "Bearer " + key
    else:  # Ollama native: lets us switch thinking off, which /v1 does not
        endpoint = url + "/api/chat"
        body = {"model": model, "messages": msgs, "stream": False, "think": False,
                "options": {"temperature": 0.2, "num_predict": max_tokens}}
    req = urllib.request.Request(endpoint, json.dumps(body).encode(), headers)
    got = json.loads(urllib.request.urlopen(req, timeout=TIMEOUT).read())
    text = (got.get("message") or {}).get("content") or \
        ((got.get("choices") or [{}])[0].get("message") or {}).get("content") or ""
    lines = [l for l in text.strip().splitlines() if l.strip()]
    return lines[-1].strip().strip("「」\"'。 ") if lines else ""


def main():
    pane = os.environ.get("TMUX_PANE")
    if not pane:
        return
    mode = tmux("show", "-gqv", "@junban-rename") or "prompt"
    if mode == "off":
        return

    name_now = tmux("display", "-p", "-t", pane, "#{window_name}")
    ours = tmux("show", "-wqv", "-t", pane, "@junban_name")
    auto = tmux("show", "-wqv", "-t", pane, "automatic-rename")
    # Renamed by hand (prefix ,) → automatic-rename is off and the name isn't ours.
    if auto == "off" and name_now != ours:
        return

    raw = sys.stdin.read()
    data = json.loads(raw) if raw.strip() else {}
    prompt = clean(data.get("prompt") or "")
    if len(prompt) < MIN_CHARS or FILLER.match(prompt):
        return

    name = ""
    if mode == "llm":
        context = (recent_prompts(data.get("transcript_path")) + [prompt])[-TURNS:]
        try:
            name = ask_llm(context)
        except Exception:
            name = ""
    name = (name or prompt)[:MAX_CHARS].rstrip().replace("#", "＃")
    if not name or name == name_now:
        return
    tmux("set", "-w", "-t", pane, "automatic-rename", "off")
    tmux("set", "-w", "-t", pane, "@junban_name", name)
    tmux("rename-window", "-t", pane, name)


if __name__ == "__main__":  # recap.py imports ask_llm from here
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
