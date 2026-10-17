<div align="center">

# junban

**Whose turn is it?**<br>
A tmux cockpit for running many AI coding agents at once.

[English](README.md) · [日本語](README.ja.md) · [▶ 25-second demo](https://junban.namelessjp.com/)

<a href="https://junban.namelessjp.com/"><img src="docs/hero-en.svg" alt="junban: six Claude Code sessions in tmux; a red banner says two are waiting on you, Alt+a jumps to the one that has waited longest, Alt+f lists every agent with a live preview" width="100%"></a>

</div>

Your agents work in parallel. Somewhere, one has been waiting twenty minutes for you to approve a `psql` command. You only find out when you click through every window.

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

It installs junban into tmux, reloads it, and connects Claude Code if you have it. Then press **Alt+a**.

<details>
<summary>With TPM instead</summary>

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

Requires tmux ≥ 3.2 and bash. fzf and python3 are optional but recommended.

### Something wrong?

Run `~/.tmux/plugins/junban/scripts/doctor.sh` (or `/junban:doctor` in Claude Code). It names the fix for the usual problems; if it doesn't, paste its output into a [bug report](https://github.com/Nameless-LLC/junban/issues/new?template=bug.yml). It leaves out window names and prompts. Questions and setups go to [Discussions](https://github.com/Nameless-LLC/junban/discussions). Security issues: please report privately, see [SECURITY.md](SECURITY.md).

## The only key you need

**Alt+a.** When nothing is waiting, the second status line shows the five keys worth knowing. When something is, it turns into a banner pointing at Alt+a. You don't need to remember anything; the screen tells you.

| Key | |
|---|---|
| **Alt+a** | Jump to the agent that needs you: waiting before finished, longest first |
| **Alt+f** | Every agent in one list, neediest first, searchable, with a live preview |
| **Alt+n** | New agent window in the current directory (in its own worktree if another agent already works there) |
| **Alt+g** | Scratch shell in a popup that survives closing |
| **Alt+/** | Cheat sheet, generated from your actual bindings, with today's timeline and the wait report |
| prefix T | Today's timeline: a row per window, when each agent worked, waited on you, or finished |
| Alt+1…9 · Alt+[ ] · Alt+Tab · Alt+z | Go to window · prev/next · last · zoom |

Terminal swallows Alt? Every action also works after the prefix: `prefix a`, `f`, `C`, `g`, `/`.

The full manual, with every option: [junban.namelessjp.com/manual](https://junban.namelessjp.com/manual/).

## What makes it different

There are [good plugins](#prior-art) that put a status icon on your tabs. junban began as one of those and kept going once we ran agents side by side all day.

**It tells you what to do, not just what's happening.** The guide line changes with the situation, so a new teammate can be productive on day one without learning a single binding. A tip rotates in the corner once a minute.

**Badges don't get stuck.** Hooks have blind spots: press Esc mid-turn and no "stop" event ever fires, so hook-only tools show "working" forever. junban cross-checks Claude Code's own live session records (`~/.claude/sessions`) and verifies the process really runs in that pane. A pane id is only unique per tmux server, so it checks the process tree too.

**Windows name themselves after the task, and stay named.** By default a window takes the first line of your prompt. Point it at any model (a small model resident in a local Ollama answers in under a second) and it summarises the last few prompts instead. Replies like "ok", "yes", "進めて" or "ครับ" never rename anything. A window you name yourself (`prefix ,`) is never touched again.

**It catches the two habits that cost the most.** Two agents in one git working tree overwrite each other's edits and commit each other's half-done work; those windows get a ⚠ and the guide line names them. Alt+n then starts the second Claude Code in its own worktree (`claude --worktree`) instead. Agents left idle for a day get a dim `z`, sink to the bottom of the Alt+f list, and are counted after the keys, so the one that needs you never gets lost among forty parked ones.

**It says in one line what each agent needs.** When an agent asks, needs permission or finishes, the ✋/✓ banner and the Alt+f list show one line on what it wants or what came of the turn ("tests pass, PR #12 opened"). With a namer model set, the model writes it; otherwise it is the first real line of the reply. Phone notifications carry the same line. Turn it off with `set -g @junban-recap off`.

**It measures how long your agents sat waiting on you.** The guide line shows today's total and your median reply time (`⏱ kept waiting 42m today · median reply 3m10s`). Alt+/ adds a bar per day for the last week, this week against last (median reply and total), your best day, a streak of days with a median reply under your goal, and today's worst windows; `scripts/stats.sh 30` goes further back. A wait runs from ✋ or ✓ until you answer or look; finishing while you watch is no wait, and one agent left overnight counts for at most an hour. Everything stays in a local TSV file.

**A timeline of your day.** prefix T (and the top of Alt+/) draws a row per window: yellow █ working, red ▓ waiting for you, green ▒ done and not looked at, then when you were active, how long agents worked and waited on you, and how many ran at once. `scripts/timeline.sh 1` shows yesterday. It is a view for you, and it stays on your machine; set `@junban-key-timeline M-y` for an Alt key (there is none by default, since Alt+t toggles thinking in Claude Code).

**A small mascot.** The call board's eyes sit on the status line, reacting to your agents: `[▮ ▮]!` when someone is waiting, `[◠ ◠]` when one finishes, `[▮▮ ]` glancing around while they run, `[▬ ▬]z` when there is nothing to do. It also comments on your week in the Alt+/ report. Turn it off with `set -g @junban-mascot off`.

**Speaks your language.** English, 日本語 and ไทย built in, picked from your locale. Japanese and Thai window names are truncated by display width, not bytes, so tabs stay aligned.

**Plain tmux and bash.** No daemon, no background process, nothing to keep alive. 124 tests; CI runs them on Linux and macOS.

## Configuration

Everything is optional. Put it in `~/.tmux.conf` **before** the plugin line.

```tmux
# Look
set -g @junban-theme on            # off = keep your theme, only add badges + counter
set -g @junban-position top        # top | bottom
set -g @junban-guide on            # the second status line
set -g @junban-guide-lines 2       # 3 = the banner gets a row of its own, keys + tip below
set -g @junban-tint 20             # % of the banner color washed over its row (0 = off)
set -g @junban-tint-waiting 35     # the same for ✋ (an agent stopped on you)
set -g @junban-tips on             # rotating tip on the right
set -g @junban-lang ja             # en | ja | th (default: from $LANG)

# Keys ("" to unbind)
set -g @junban-key-jump M-a
set -g @junban-key-list M-f
set -g @junban-key-new M-n
set -g @junban-key-scratch M-g
set -g @junban-key-help M-/
set -g @junban-key-timeline ""     # e.g. M-y (prefix T always works)
set -g @junban-nav-keys on         # Alt+1..9, Alt+[ ], Alt+Tab, Alt+z
set -g @junban-prefix-keys on      # prefix a/f/C/g/ fallbacks
set -g @junban-agent-cmd claude    # what Alt+n starts
set -g @junban-new-worktree auto   # auto = Alt+n uses claude --worktree when the tree is taken | off

# Hygiene
set -g @junban-shared-check on     # ⚠ when two agents share a git working tree
set -g @junban-stale-hours 24      # z on agents idle this long (0 = off)
set -g @junban-meter on            # ⏱ today's wait total on the guide line
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
```

Colors: `@junban-color-{waiting,done,running,bg,fg,accent,muted,dim,current-bg}`. With your own theme, put `#{E:@junban-badge}` anywhere in a format.

## Other agents

| Agent | Setup | What you get |
|---|---|---|
| Claude Code | the plugin (installed by the line above) | ✋ ✓ ●, one-line recap, names; badges heal themselves after Esc |
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
