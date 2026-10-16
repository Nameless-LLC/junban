#!/usr/bin/env bash
# setup.sh codex|gemini [--print] — hook another agent into junban.
#
#   codex    adds junban's hooks to ~/.codex/hooks.json ($CODEX_HOME if set).
#            Codex asks you to trust new hooks once: run /hooks in Codex.
#   gemini   adds them to ~/.gemini/settings.json.
#   --print  show what would be written instead of writing it.
#
# Safe to run again: junban's own entries are replaced, nothing else is touched,
# and the previous file is kept as *.bak. Claude Code needs none of this; its
# hooks come with the plugin.
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
agent=${1:-}; mode=${2:-}

case "$agent" in
  codex)  file="${CODEX_HOME:-$HOME/.codex}/hooks.json"
          events="SessionStart UserPromptSubmit PostToolUse PermissionRequest Stop Interrupt SessionEnd" ;;
  gemini) file="$HOME/.gemini/settings.json"
          events="SessionStart BeforeAgent AfterTool Notification AfterAgent SessionEnd" ;;
  *) echo "usage: setup.sh codex|gemini [--print]" >&2; exit 2 ;;
esac
command -v python3 >/dev/null 2>&1 || { echo "junban: setup needs python3" >&2; exit 1; }

# shellcheck disable=SC2086  # one argument per event
python3 - "$agent" "$file" "$S/hook.sh" "$mode" $events <<'PY'
import json, os, shlex, shutil, sys

agent, path, hook, mode, events = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:]
try:
    with open(path, encoding="utf-8") as fh:
        conf = json.load(fh)
except FileNotFoundError:
    conf = {}
except ValueError as e:
    sys.exit(f"junban: {path} is not plain JSON ({e}); add the hooks by hand, see README")

hooks = conf.setdefault("hooks", {})
for ev in list(hooks):  # drop junban's earlier entries, keep everyone else's
    kept = []
    for group in hooks[ev]:
        group["hooks"] = [h for h in group.get("hooks", []) if "junban" not in h.get("command", "") or "hook.sh" not in h.get("command", "")]
        if group["hooks"]:
            kept.append(group)
    hooks[ev] = kept
    if not kept:
        del hooks[ev]

# Codex counts timeouts in seconds, Gemini in milliseconds.
timeout = 5 if agent == "codex" else 5000
for ev in events:
    entry = {"type": "command", "command": f"bash {shlex.quote(hook)} {agent} {ev}", "timeout": timeout}
    if agent == "codex" and ev in ("SessionEnd", "Interrupt"):
        entry["timeout"] = 3  # Codex caps these two at 3 s
    if agent == "gemini":
        entry["name"] = f"junban-{ev}"
    group = {"hooks": [entry]}
    if agent == "gemini" and ev in ("AfterTool", "Notification"):
        group["matcher"] = "*"
    hooks.setdefault(ev, []).append(group)

out = json.dumps(conf, indent=2, ensure_ascii=False) + "\n"
if mode == "--print":
    print(out, end="")
    sys.exit(0)
os.makedirs(os.path.dirname(path), exist_ok=True)
if os.path.exists(path):
    shutil.copy2(path, path + ".bak")
with open(path, "w", encoding="utf-8") as fh:
    fh.write(out)
print(f"junban: hooks written to {path}")
if agent == "codex":
    print("junban: start Codex inside tmux and run /hooks once to trust them")
else:
    print("junban: start Gemini CLI inside tmux; /hooks lists them")
PY
