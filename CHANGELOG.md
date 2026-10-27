# Changelog

## 0.8.3 — 2026-10-27

### Security

- **$OPENAI_API_KEY is no longer sent to any OpenAI-compatible server but OpenAI's.** With a `…/v1` model URL and no `@junban-namer-key`, junban used to send that key to whatever server the URL named. It now sends it only to api.openai.com; for another server, name the variable that holds its key in `@junban-namer-key`.

## 0.8.2 — 2026-10-27

### Fixed

- **The restore message no longer says "0 window(s)" or points at an empty menu.** When nothing is left to restore by hand, it only says how many came back.

## 0.8.1 — 2026-10-27

### Fixed

- **Restoring no longer misses windows whose pane once ran another Claude Code session.** That session's leftover record sometimes kept the window from being saved, or from being reopened after the restart.

## 0.8.0 — 2026-10-27

### Added

- **Windows come back after a restart.** junban keeps a list of which window runs which Claude Code conversation. When tmux starts again, it reopens the ones worth reopening (waiting on you, working, finished and not yet looked at, or active in the last day; never ones marked z) in their old session, folder and name with `claude --resume`, and says how many. The rest are under Alt+, → Restore windows. `@junban-restore off` turns off the automatic reopening. Each tmux server keeps its own list.

## 0.7.8 — 2026-10-25

### Fixed

- **Alt+n's new-worktree notice is no longer hidden by the spinner.** Both now share the status line while the agent starts.

## 0.7.7 — 2026-10-25

### Fixed

- **Alt+n's spinner can no longer land on Claude Code's folder-trust prompt.** It used to draw in the new pane, and a frame written just as Claude Code drew its prompt stayed on top of the options, so the window looked frozen. The spinner now shows on the status line and never writes into the pane; it stops as soon as the agent draws anything.

## 0.7.6 — 2026-10-23

### Fixed

- **The stopped spinner no longer leaves "Starting claude…" above Claude Code's trust prompt.** Its line is wiped when nothing of the agent's is on it.

## 0.7.5 — 2026-10-23

### Fixed

- **Alt+n's spinner no longer draws over Claude Code's "trust this folder?" prompt.** The prompt comes before any hook and leaves the cursor on the top row, so the spinner kept going for a minute on top of it. It now stops as soon as anything else is on the screen.

## 0.7.4 — 2026-10-22

### Fixed

- **Alt+w asks properly with the guide rows off.** With `@junban-guide off` the close prompt was empty.
- **The installer no longer says open Claude Code sessions pick up junban by themselves.** It now says to run `/reload-plugins` in them.
- **junban's state files are written readable only by you**, the version and update log included.

### Changed

- **The site, manual and READMEs were reviewed line by line against the code**, in English and Japanese. Several descriptions were corrected: the Alt+a order, what needs Python 3 and fzf, when the VS Code window switch applies (VS Code connected remotely to Linux), what `@junban-done-batch` holds back, and what is logged.

## 0.7.3 — 2026-10-22

### Changed

- **An update says so once, where you will see it.** "junban updated to X" now shows the first time the status line draws after a new version arrives, so an update that ran in the background or overnight is not missed. A first install says nothing.

## 0.7.2 — 2026-10-22

### Changed

- **The installed version shows in Alt+/ (next to the title) and in Alt+, (next to Update now).** It used to be only in `doctor.sh`.

## 0.7.1 — 2026-10-22

### Fixed

- **Jumping to another project from VS Code no longer swaps this window's terminal.** When no terminal showed that project (its window's terminal was closed), junban switched the terminal you were in, so one project's agent ended up under another project's window. It now opens that project's folder in VS Code, which brings its window forward if it is already open.

## 0.7.0 — 2026-10-20

### Added

- **junban updates itself.** Once a day it fast-forwards to the newest release, reloads, and updates the Claude Code plugin. Releases are cut by CI: a version bump that passes on Linux and macOS becomes tag vX.Y.Z with these notes. Alt+, → Update now does it at once; Alt+, → Updates picks releases (default), every change on main, or off (`@junban-update`). A checkout with local changes or a pinned commit is never touched. `doctor.sh` shows the channel and the last update.

## 0.6.2 — 2026-10-20

### Changed

- **Alt+n no longer looks frozen while the agent starts.** Claude Code can take several seconds to draw anything; the new pane now spins "Starting claude…" at once (gone just before Claude draws), and the tab shows a dim ◌ until the agent's first hook reports in (or a minute passes, for agents without junban's hooks).
- **The window opens at once** (0.27 s → 0.08 s): the check for another agent in the same tree now runs inside the new window, under the spinner.

### Fixed

- **The weekly report no longer slips a day at a minute's turn.** The clock was read in pieces, so a report made at 03:29:59 could count today as yesterday.
- **Two settings saved at once both stick.** Picking in Alt+, from two clients at the same moment could drop one choice.

## 0.6.1 — 2026-10-20

### Changed

- **Thai reads more naturally.** "Median" is มัธยฐาน (ค่ากลาง also covers the mean), the trend compares with "the last 7 days" rather than "the day 7 days ago", and the settings menu labels read as whole phrases.
- Tests run in two halves side by side (64 s → 55 s).

## 0.6.0 — 2026-10-19

### Fixed

- **A tool call no longer pays for its output.** PostToolUse ran the whole hook on every tool call, parsing the tool's full output: a 2 MB Read cost half a second and a 20 MB one could time the hook out. It now asks tmux one question and returns while the agent is already running (`state.sh tool`; Codex and Gemini too).
- **A `#` in a window name no longer leaks style text into the status line** ("issue #" or "a#[fg=red]b").
- **Odd option values can no longer break the status line or run code.** `@junban-done-batch 08`, `@junban-tint 999`, `@junban-meter-cap 60m` and the like fall back to their defaults; `@junban-meter-cap` was evaluated as arithmetic, so a crafted value ran a command. `@junban-lang` takes only en, ja or th.
- **One bad row stops nothing.** A damaged wait log, an odd `@junban_ts` or a session file that is not an object used to stop the meter or the badge repair for every window.
- **One bad line in `settings.conf` costs only itself**, instead of tmux dropping the whole file.
- **Logs stay small.** Past 4 MB, the wait, state and done logs keep their last 90 days; the status line reads them every few seconds.
- **The status line is about five times faster** (0.85 s → 0.17 s per refresh with a banner, 0.6 s → 0.13 s for the keys row): options come from one tmux call instead of twenty, recaps are fitted without a subshell per character, and today's wait is kept between refreshes until the log grows or the day turns.
- **The status line never waits for badge repair**, which now runs in the background, one at a time. The keys row no longer reads the wait log, and reloading no longer piles up terminal-features entries.

### Changed

- **Alt+, points out a tmux.conf line that would undo a choice.** A line after the plugin line wins on every start, so a choice made in the menu quietly came back. The menu marks the option "⚠ tmux.conf", names the file and line, and offers to turn that line into a comment (after asking; a backup goes next to it as `.junban.bak`, and a symlinked tmux.conf stays a symlink). Saving such a choice says so too.
- **Trends stay calm when the change is noise.** A median under 15 s apart (5 min for a week's total) or under 10% says nothing on the status line and "≈ ほぼ同じ" in the report. Double or more reads as a ratio, "▲3.3倍 遅い", instead of "+233%".

## 0.5.0 — 2026-10-19

### Added

- **Settings on Alt+,.** A menu for what Alt+n starts, the language, where the status line sits and how many rows it has, the wait meter, ✓ in batches and the mascot. A choice applies at once and is saved to `~/.config/junban/settings.conf`, which junban reads on every load, so tmux.conf is never rewritten. The two Alt+n choices that skip permission checks ask first; "Type a command…" takes anything else. Every menu ends with "Close (q / Esc)".

### Changed

- **Alt+g is no longer bound by default.** Claude Code runs a shell command with `!`, and the scratch shell was rarely opened. prefix g still opens it, and `set -g @junban-key-scratch M-g` brings the Alt key back. Alt+, takes its place on the keys row.

## 0.4.5 — 2026-10-19

### Changed

- **The manual says how to get bypass permissions in Alt+n windows.** Claude Code offers it on Shift+Tab only when started with a flag for it, and Alt+n starts plain `claude`; put the flag in `@junban-agent-cmd`.

- **This week against last reads the same way.** The Alt+/ report showed "(-50%)" for the median reply and the total wait. Each now has a green ▼ and a word when it went down ("▼50% 速い", "▼50% 減") and an orange ▲ when it went up.

## 0.4.4 — 2026-10-19

### Changed

- **Slower replies are orange, not red.** Red already means an agent is waiting on you. `@junban-color-slower` sets the colour.

## 0.4.3 — 2026-10-19

### Changed

- **The reply trend reads at a glance.** A green ▼ when you reply quicker than the last 7 days, a red ▲ when slower, then the word: "返答の中央値 3分10秒 ▼32% 速い（前7日比）".

## 0.4.2 — 2026-10-19

### Changed

- **The reply trend on the status line is said in words.** "· 前7日比 +32%" after today's wait read as more waiting, and nobody could tell whether up was good. It now sits right after the median and says which way: "返答の中央値 3分10秒（前7日より32%速い）" or "…遅い". A change of 0% is left out.

## 0.4.1 — 2026-10-18

### Added

- **Alt+w closes the window.** It asks first and names the window, since the agent in it stops. It sits on the keys row next to Alt+[ ], which now reads "prev / next" to make room. `@junban-nav-keys off` turns it off with the other window keys.

## 0.4.0 — 2026-10-18

### Added

- **What a finished turn changed.** The ✓ banner and the Alt+f list say what changed since you sent the prompt: `3 files +41 −88 · 2 commits · PR #12`. A turn that touched nothing says so, so you know it is a quick read. In Alt+f the preview starts with the diff stat, and Ctrl+o opens the PR the agent gave. Claude Code, Codex and Gemini.
- **Finished work in batches** (`@junban-done-batch 30`, off by default). ✓ wait for the next :00 or :30 and come as one notification; until then the guide line only counts them ("2 finished, shown at 15:30"). ✋ still comes at once, Alt+a still reaches a held ✓, and the wait meter starts a held ✓'s wait when it shows.

## 0.3.12 — 2026-10-18

### Changed

- **The keys row shows Alt+[ ] instead of Alt+1-9.** Stepping to the window beside is what you reach for; Alt+1-9 still works.
- **Tabs count from 1.** Alt+1 opened the second tab when tabs started at 0. With `@junban-nav-keys` on (the default), junban sets `base-index 1` and `renumber-windows on` and renumbers running sessions, so the number on a tab is the one you press. The Ctrl+b hint says `1-9`.

## 0.3.11 — 2026-10-18

### Added

- **The keys row shows Alt+1-9.** Moving to a window by its number sits right after Alt+a and Alt+f, so it stays if a narrow terminal clips the end. Hidden with `@junban-nav-keys off`.

## 0.3.10 — 2026-10-18

### Removed

- **Tips.** With three rows they never had room, and cut to fit they could not be read. `@junban-tips` is gone; Alt+/ still lists every key.

### Fixed

- The manual's calm example shows the wait and the keys on their own rows, as the guide does now.

## 0.3.9 — 2026-10-18

### Removed

- **The shared-tree `!` badge.** Several agents in one checkout is how many people work, so the badge was on almost all the time, and it gave you nothing to act on. It is gone, along with `@junban-shared-check`. Alt+n still starts a second Claude Code in its own worktree when one already works in that tree (`@junban-new-worktree`).

## 0.3.8 — 2026-10-18

### Fixed

- **Tips never showed with three rows.** They sat after the keys on the last row, which leaves no room on a 110-column terminal in Japanese, so every tip was dropped. When calm, the tip now sits right of today's wait on the second row and is cut with "…" instead of dropped. During a ✋/✓ banner it moves back after the keys, where it shows if it fits.

## 0.3.7 — 2026-10-18

### Added

- **The prefix tells you what can follow it.** While Ctrl+b (your prefix) is down, the keys row lists `0-9`, `n/p` and junban's prefix keys instead of the Alt ones. Useful where Alt never reaches tmux (phones, some web terminals).

### Changed

- **`@junban-guide-lines 2` now means "no keys row".** The one guide row shows the ✋/✓ banner or today's wait; the keys appear there only while the prefix is down. The default stays at three rows.

## 0.3.6 — 2026-10-18

### Changed

- **Three status rows by default.** Today's wait (and parked agents) gets the second row, the keys and tip the third. On one row, the keys and the wait ran to about 146 columns in Japanese, so on a 110-column terminal the wait was cut off entirely. A ✋/✓ banner takes the second row, with today's wait at its right end when there is room. `set -g @junban-guide-lines 2` keeps the single row.

### Fixed

- **Badges cut in half in VS Code.** `⚠` and `⏱` are one column to tmux, but xterm.js draws them as two-column emoji and clips the right half. The shared-tree badge is now a red `!` (like the `z` for parked agents), and the wait meter has no icon.

## 0.3.5 — 2026-10-18

### Changed

- **The ⚠ banner on the guide line is gone.** The tab badge already marks windows that share a working tree; repeating their names on the second row only took the space the keys and tips need.

### Fixed

- **⚠ on agents that already have their own worktree.** An agent that Alt+n started with `claude --worktree`, or one that moved into a worktree mid-session, was still reported as sharing the repo root, so junban warned about the very split it had made. tmux's `pane_current_path` shows the launching `bash -c` shell's directory, not claude's. The hooks now record the directory the agent actually works in (the payload's `cwd`, else the hook's own), and the shared-tree check uses it.

## 0.3.4 — 2026-10-18

### Changed

- **Alt+/ and the timeline close the way you expect.** The popups no longer open in a pager: arrows, PgUp/PgDn, Space and the mouse wheel scroll, and any other key, Alt+/ again, or a click inside closes them. The last row says so.

### Fixed

- `setup.sh codex|gemini` recognises its own hooks by their exact path, so running it twice from a clone whose path has no "junban" in it no longer adds them twice.
- A timeline test could be off by a second.

## 0.3.3 — 2026-10-18

### Added

- **VS Code: Alt+a / Alt+f raise the project's window.** If you keep one VS Code window per project, each terminal in its own tmux session, jumping used to put project B's agent under project A's terminal tab. junban now brings forward the VS Code window that already shows that session (through VS Code's remote `code` CLI), and leaves your terminal alone. Plain terminals, Web terminals and sessions no window shows still switch in place. `set -g @junban-vscode-raise off` keeps the old behaviour.
- **Timeline.** `prefix T` draws today per window: yellow working, red waiting for you, green done and unseen, with active span, working time, waits and the most agents at once. Alt+/ shows it above the wait report. `@junban-key-timeline` sets a root key.
- **Optional third status row** (`@junban-guide-lines 3`): the ✋/✓ banner gets row 1 to itself and the keys, meter and tip move below instead of disappearing.
- The banner row takes a faint wash of its colour (`@junban-tint`, default 20%; `@junban-tint-waiting`, default 35%, for ✋; 0 turns it off).
- **A manual** at [junban.namelessjp.com/manual](https://junban.namelessjp.com/manual/): every badge, key, report and option in one page, in English and Japanese.

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
