# Security

junban runs inside your terminal and reads what your agents' hooks send it, so we take reports seriously.

## Reporting a vulnerability

Please report privately through GitHub: **Security → Report a vulnerability** on this repository
(https://github.com/Nameless-LLC/junban/security/advisories/new). Do not open a public issue.

Include what an attacker controls (a directory name, a prompt, a hook payload, a tmux option…), what it lets them do, and the output of `scripts/doctor.sh` if it helps. We aim to reply within three working days and to ship a fix as a patch release.

## What junban touches

- It reads hook payloads from Claude Code, Codex CLI and Gemini CLI on stdin and stores a few short strings as tmux window options. Nothing from a payload is run as a command.
- It writes two logs under `$XDG_STATE_HOME/junban` (default `~/.local/state/junban`), readable by you only: how long agents waited, and for each finished turn the prompt and the one-line recap.
- It sends data off the machine only when you configure it to: `@junban-namer-url` (prompts and agents' final messages go to that model) and `@junban-notify-cmd` (the badge and the recap line go to whatever that command reaches; a public ntfy.sh topic is readable by anyone who guesses its name).

## Supported versions

Fixes go into the latest release only.
