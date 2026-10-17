# Changelog

## 0.3.3 — 2026-10-18

### Added

- **VS Code: Alt+a / Alt+f raise the project's window.** If you keep one VS Code window per project, each terminal in its own tmux session, jumping used to put project B's agent under project A's terminal tab. junban now brings forward the VS Code window that already shows that session (through VS Code's remote `code` CLI), and leaves your terminal alone. Plain terminals, Web terminals and sessions no window shows still switch in place. `set -g @junban-vscode-raise off` keeps the old behaviour.
- **Timeline.** `prefix T` draws today per window: yellow working, red waiting for you, green done and unseen, with active span, working time, waits and the most agents at once. Alt+/ shows it above the wait report. `@junban-key-timeline` sets a root key.
- **Optional third status row** (`@junban-guide-lines 3`): the ✋/✓ banner gets row 1 to itself and the keys, meter and tip move below instead of disappearing.
- The banner row takes a faint wash of its colour (`@junban-tint`, default 20%; `@junban-tint-waiting`, default 35%, for ✋; 0 turns it off).

### Fixed

- ✓ never showed when every session had a client attached (one session per project, windows in the background): an attached, active window counted as "you are looking at it". Now a terminal on that session must have focus, and coming back to a terminal marks its ✓ as seen.
- A long recap pushed the ✓ banner past the edge of the terminal. The guide line now fits the width: the tip goes first, then the recap is cut with "…".

## 0.3.2 — 2026-10-16

### Security

- `SECURITY.md`: report vulnerabilities privately through GitHub Security Advisories. It also lists what junban stores and what can leave your machine (namer URL, notify command).
- `/junban:doctor` may run only `scripts/doctor.sh`, and the report masks `@junban-agent-cmd`.
- CI runs with read-only repository permissions.

## 0.3.1 — 2026-10-16

### Security

- Alt+n could run commands hidden in a directory name: a name containing a single quote broke out of the quoted path when you pressed Alt+n there. The path is now quoted by tmux (`#{q:pane_current_path}`), with a regression test.
- The wait log (`waits.tsv`, `done.tsv`) holds window names, prompts and recaps and was readable by other users on the machine. Files are now 0600 in a 0700 directory; existing files are tightened on the next write.
- `setup.sh` shell-quotes the hook path it writes.

### Added

- `scripts/doctor.sh` (or `/junban:doctor` in Claude Code) checks tmux, the plugin and each agent's hooks, and prints a report you can paste into a bug report. It leaves out window names and prompts.
- Issue forms for bugs and ideas; questions go to Discussions.

### Changed

- Gemini CLI: the recap for a permission prompt names the command ("Shell: touch build/out/a.txt") instead of Gemini's generic "Tool Confirm Shell Command requires execution".

## 0.3.0 — 2026-10-16

- **Codex CLI and Gemini CLI.** `scripts/setup.sh codex` or `scripts/setup.sh gemini` writes the hooks (keeping yours, with a `.bak`; `--print` to preview). Codex gets ✋ ✓ ●, a recap that names the command it wants to run, and Esc clears the badge; trust the hooks once with `/hooks`. Gemini gets ✋ ✓ ● and recap. `set -g @junban-agent-cmd codex` makes Alt+n start Codex.
- **Weekly report.** Alt+/ shows a bar per day, this week against last (median reply and total), your best day, and a streak of days with a median reply under `@junban-goal` (default 5 minutes). The guide line compares with the previous seven days.
- **Mascot, on by default.** The call board's eyes on the status line: `[▮ ▮]!` someone is waiting, `[◠ ◠]` one finished, `[▮▮ ]` agents running, `[▬ ▬]z` nothing to do. It also comments on your week in the report. `set -g @junban-mascot off` hides it.
- Fixed: the stub model in the tests hung on macOS runners; CI now has a time limit.

## 0.2.0 — 2026-10-16

- **One line on what each agent needs.** When an agent asks, needs permission or finishes, the banner and the Alt+f list say what it wants or what came of the turn. Written by your namer model if you set one, else the first real line of the reply. Phone notifications carry it too. `@junban-recap off` turns it off.
- **Wait meter.** The guide line shows how long agents sat waiting on you today and your median reply time (⏱). Alt+/ adds the last seven days; `scripts/stats.sh N` goes further back. Stored in a local TSV file only.
- **Shared-tree warning.** Windows whose agents share a git working tree get ⚠, and Alt+n starts the next agent in its own worktree.
- **Parked agents.** Agents untouched for a day get a dim `z` and sink to the bottom of Alt+f.
- Fixed: tests read key bindings from the full table (tmux 3.7 `list-keys KEY` prints nothing); `wc` padding on macOS.

## 0.1.0 — 2026-10-16

First public release.

- Badges on tmux tabs: ✋ waiting on you, ✓ done, ● running. They heal themselves from Claude Code's session records, so an Esc mid-turn doesn't leave a stuck badge.
- Alt+a jumps to the agent that has waited longest; Alt+f lists all agents (fzf if installed).
- A second status line that lists the keys worth knowing, turns into a banner when someone needs you, and rotates a tip once a minute.
- Window names from what you asked, optionally summarised by a local model; short replies never rename, and names you set yourself are left alone.
- English, Japanese and Thai, cut by display width.
- Claude Code plugin for the hooks; `scripts/state.sh` for any other agent.
