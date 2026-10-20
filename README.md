<div align="center">

# junban

**Whose turn is it?**<br>
A tmux plugin that shows which of your AI coding agents is waiting on you.

[English](README.md) · [日本語](README.ja.md) · [▶ 25-second demo](https://junban.namelessjp.com/)

<a href="https://junban.namelessjp.com/"><img src="docs/hero-en.svg" alt="junban: six Claude Code sessions in tmux; a red banner says two are waiting on you, Alt+a jumps to the one that has waited longest, Alt+f lists every agent with a live preview" width="100%"></a>

</div>

Your agents work in parallel. Somewhere, one has been waiting twenty minutes for you to approve a `psql` command. You only find out by opening every window.

**junban** (順番, Japanese for *"whose turn"*) fixes that, and tells you what to press next.

- **✋ red**: an agent is waiting for you (permission or question)
- **✓ green**: it finished and you haven't looked yet
- **● yellow**: it is working

Then one key, **Alt+a**, takes you to whoever has waited longest.

## Install

One line in a terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/Nameless-LLC/junban/main/install.sh | bash
```

It installs junban into tmux and connects Claude Code if you have it.

<details>
<summary>With TPM (the tmux plugin manager) instead</summary>

Add to `~/.tmux.conf` and press prefix + I:

```tmux
set -g @plugin 'Nameless-LLC/junban'
```

Then connect Claude Code:

```sh
claude plugin marketplace add Nameless-LLC/junban && claude plugin install junban@junban
```

</details>

Codex CLI or Gemini CLI: `~/.tmux/plugins/junban/scripts/setup.sh codex` (or `gemini`). See [Other agents](#other-agents).

Requires tmux ≥ 3.2 and bash. python3 and fzf are optional; they add window naming, the timeline and list search.

### Something wrong?

Run `~/.tmux/plugins/junban/scripts/doctor.sh` (or `/junban:doctor` in Claude Code). It names the fix for the usual problems; if it doesn't, paste its output into a [bug report](https://github.com/Nameless-LLC/junban/issues/new?template=bug.yml). It leaves out window names and prompts. Questions go to [Discussions](https://github.com/Nameless-LLC/junban/discussions). Security issues: please report privately, see [SECURITY.md](SECURITY.md).

## The only key you need

**Alt+a.** The bottom status line always shows the keys worth knowing. When an agent is waiting, the line above it shows a banner pointing at Alt+a.

| Key | |
|---|---|
| **Alt+a** | Jump to the agent that needs you: waiting before finished, longest first |
| **Alt+f** | Every agent in one list, neediest first, searchable, with a live preview |
| **Alt+n** | New agent window in the current directory (in its own worktree if another agent already works there) |
| **Alt+,** | Settings: what Alt+n starts, language, status rows and more. Saved to `~/.config/junban/settings.conf` |
| **Alt+/** | Cheat sheet, generated from your actual bindings, with today's timeline and the wait report |
| prefix T | Today's timeline: a row per window, when each agent worked, waited on you, or finished |
| Alt+1…9 · Alt+[ ] · Alt+Tab · Alt+z · Alt+w | Go to window · prev/next · last · zoom · close (asks first) |

Terminal doesn't send Alt? Every action also works after the prefix: `prefix a`, `f`, `C`, `g`, `/`.

The full manual, with every option: [junban.namelessjp.com/manual](https://junban.namelessjp.com/manual/).

## What makes it different

Plenty of [plugins](#prior-art) badge your tabs, and a couple also jump to the longest wait (gs/tmux-agent-status) or measure waiting (muxa); the [comparison](https://junban.namelessjp.com/#compare) lines them up. junban does those in one tmux plugin with no daemon, and adds two things we didn't find elsewhere: a status line that shows your next key, and idle windows that move out of the way.

**Badges don't get stuck.** Press Esc mid-task and Claude Code sends no "stop" event, so tools that rely only on hooks show "working" forever. junban checks Claude Code's own session records (`~/.claude/sessions`) and walks the process tree to make sure it has the right pane.

**Windows are named after the task.** By default a window takes the first line of your prompt. Set a model and it summarises your last few prompts instead (a small model in a local Ollama takes under a second). Short replies like "ok" or "yes" never rename a window, and a name you set yourself (`prefix ,`) is never changed.

**Alt+n never looks frozen.** The new pane spins while the agent starts, and the tab shows a dim ◌ until the agent is up.

**Idle windows move out of the way.** Windows untouched for a day get a dim `z` and move to the bottom of the Alt+f list, so the one that needs you never gets lost among dozens of idle ones.

**It says in one line what each agent needs.** When an agent asks, needs permission or finishes, the ✋/✓ banner and the Alt+f list show one line on what it wants or how the work turned out ("tests pass, PR #12 opened"). With a model set, the model writes it; otherwise it is the first real line of the reply. Phone notifications carry the same line. Turn it off with `set -g @junban-recap off`. For finished work it also says what changed (`3 files +41 −88 · 2 commits · PR #12`); in the Alt+f list the preview starts with the diff stat and Ctrl+o opens the PR.

**Finished work can come in batches.** With `set -g @junban-done-batch 30`, ✓ wait for the next :00 or :30 and arrive as one notification; until then the status line only counts them. ✋ still interrupts at once.

**It measures how long your agents sat waiting on you.** The status line shows today's total and your median reply time (`kept waiting 42m today · median reply 3m10s`). Alt+/ adds a bar per day for the last week, this week against last (median reply and total), your best day, a streak of days with a median reply under your goal, and today's worst windows; `scripts/stats.sh 30` goes further back. A wait runs from ✋ or ✓ until you answer or look; finishing while you watch is no wait, and one agent left overnight counts for at most an hour. Everything stays in a local TSV file.

**A timeline of your day.** prefix T (and the top of Alt+/) draws a row per window: yellow █ working, red ▓ waiting for you, green ▒ done and not looked at, then when you were active, how long agents worked and waited on you, and how many ran at once. `scripts/timeline.sh 1` shows yesterday. It is a view for you, and it stays on your machine; set `@junban-key-timeline M-y` for an Alt key (there is none by default, since Alt+t toggles thinking in Claude Code).

**A small mascot.** A face on the status line reacts to your agents: `[▮ ▮]!` when someone is waiting, `[◠ ◠]` when one finishes, `[▮▮ ]` glancing around while they run, `[▬ ▬]z` when there is nothing to do. It also comments on your week in the Alt+/ report. Turn it off with `set -g @junban-mascot off`.

**Speaks your language.** English, 日本語 and ไทย built in, chosen from your system language. Japanese and Thai window names are truncated by display width, not bytes, so tabs stay aligned.

**Plain tmux and bash**, plus python3 for some features. Nothing stays running: work rides on tmux's own status refresh. CI runs the tests on Linux and macOS.

## Configuration

Everything is optional. Put it in `~/.tmux.conf` **before** the plugin line. The common ones are also on **Alt+,**, which saves to `~/.config/junban/settings.conf`; a choice made there wins over the same line before the plugin line, and the menu points out (and offers to turn off) one after it, which would undo the choice on the next start.

```tmux
# Look
set -g @junban-theme on            # off = keep your theme, only add badges + counter
set -g @junban-position top        # top | bottom
set -g @junban-guide on            # the second status line
set -g @junban-guide-lines 3       # 2 = no keys row; the keys show while the prefix is down
set -g @junban-tint 20             # % of the banner color washed over its row (0 = off)
set -g @junban-tint-waiting 35     # the same for ✋ (an agent stopped on you)
set -g @junban-lang ja             # en | ja | th (default: from $LANG)

# Keys ("" to unbind)
set -g @junban-key-jump M-a
set -g @junban-key-list M-f
set -g @junban-key-new M-n
set -g @junban-key-scratch ""     # e.g. M-g (prefix g always works)
set -g @junban-key-settings M-,
set -g @junban-key-help M-/
set -g @junban-key-timeline ""     # e.g. M-y (prefix T always works)
set -g @junban-nav-keys on         # Alt+1..9 (tabs count from 1), Alt+[ ], Alt+Tab, Alt+z, Alt+w
set -g @junban-prefix-keys on      # prefix a/f/C/g/ fallbacks
set -g @junban-agent-cmd claude    # what Alt+n starts
set -g @junban-new-worktree auto   # auto = Alt+n uses claude --worktree when the tree is taken | off

# Hygiene
set -g @junban-stale-hours 24      # z on agents idle this long (0 = off)
set -g @junban-meter on            # today's wait total on the status line
set -g @junban-meter-cap 60        # minutes one wait can count for
set -g @junban-goal 5              # streak: days with a median reply within this many minutes
set -g @junban-mascot on           # off = hide the face on the status line

# Window names
set -g @junban-rename prompt       # off | prompt | llm
set -g @junban-namer-url http://localhost:11434   # Ollama, or an OpenAI-compatible …/v1
set -g @junban-namer-model qwen3:8b
set -g @junban-namer-key OPENAI_API_KEY           # env var holding the key (…/v1 only)

# Notifications when an agent starts waiting or finishes (message on stdin)
set -g @junban-notify-cmd 'xargs -0 notify-send junban'
set -g @junban-notify-cmd 'curl -s -d @- ntfy.sh/your-topic'   # the message includes the recap line; a public ntfy.sh topic is readable by anyone who knows its name
set -g @junban-done-batch off      # 30 = ✓ arrive together every 30 minutes
```

Colors: `@junban-color-{waiting,done,running,bg,fg,accent,muted,dim,current-bg}`. With your own theme, put `#{E:@junban-badge}` anywhere in a format.

## Other agents

| Agent | Setup | What you get |
|---|---|---|
| Claude Code | the plugin (installed by the line above) | ✋ ✓ ●, one-line recap, names; badges fix themselves after Esc |
| Codex CLI | `scripts/setup.sh codex`, then trust the hooks once with `/hooks` in Codex | ✋ ✓ ●, recap names the command it wants to run, names; Esc clears the badge |
| Gemini CLI | `scripts/setup.sh gemini` | ✋ ✓ ●, recap names the command it wants to run, names |

```sh
~/.tmux/plugins/junban/scripts/setup.sh codex    # writes ~/.codex/hooks.json
~/.tmux/plugins/junban/scripts/setup.sh gemini   # writes ~/.gemini/settings.json
```

Both keep your existing hooks, replace only junban's own entries (safe to re-run) and leave a `.bak`; `--print` shows what would be written. Alt+n starts Codex if you `set -g @junban-agent-cmd codex`.

Anything else that can run a command can drive junban too; it only cares about a window option:

```sh
~/.tmux/plugins/junban/scripts/state.sh running   # or waiting | done | idle | clear
```

## How it works

```
Claude Code hook ──► scripts/state.sh ──► tmux window option @junban
                                               │
                         status line, Alt+a, Alt+f read it
                                               │
     every 5 s: heal.py checks ~/.claude/sessions and fixes stale states
```

`hooks/hooks.json` is the whole Claude Code side. Read it; it is 40 lines.

## Prior art

Credit where it's due. These do overlapping things and some may suit you better:
[tmux-agent-indicator](https://github.com/accessd/tmux-agent-indicator) ·
[tmux-agent-status (RatulMaharaj)](https://github.com/RatulMaharaj/tmux-agent-status) ·
[tmux-agent-status (rorhcdream)](https://github.com/rorhcdream/tmux-agent-status), which showed that session files beat hooks ·
[tmux-handlr](https://github.com/CRThaze/tmux-handlr) ·
[claude-code-tmux-status](https://github.com/XavierYounan/claude-code-tmux-status) ·
[tmux-window-notifier](https://github.com/mrf/tmux-window-notifier)

## Develop

```sh
bash tests/run.sh          # isolated tmux server; never touches yours
bash tools/demo.sh         # a fake busy morning: tmux -L junban-demo attach
bash tools/hero.sh en      # regenerate the README image from a live session
```

MIT. Built at [Nameless](https://namelessjp.com), where it runs all day.
