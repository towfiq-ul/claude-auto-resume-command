# /auto-resume — continue a Claude Code session when your usage limit resets

This repo has two related tools:

- **`/auto-resume`** (below) — you tell it when to resume; it types
  `continue` back into your session at that time.
- **[`claude-session-guardian`](#session-guardian--automatic-progress-notes--auto-resume)**
  — a Stop hook that detects the usage-limit banner itself and calls
  `claude-auto-resume` automatically, plus leaves a progress note. No
  manual step needed.

---

When Claude Code hits a usage limit, the session pauses ("resets at 7pm").
`auto-resume` waits until the time you give it, then feeds your instruction
(default: `continue`) back to the session — by typing it into the **same
terminal**, or, when no terminal injection is possible, by resuming the
session headlessly in **offline mode**.

## How it works

- `claude-auto-resume <time> [instruction]` remembers which terminal window
  (or tmux pane) it was started from and launches a small detached watcher
  process.
- At the target time the watcher re-activates that window and types the
  instruction using **xdotool** (X11) — or **tmux send-keys** if you run
  Claude inside tmux.
- **Offline mode**: if neither tmux nor xdotool is available (headless box,
  Wayland without tmux), the instruction is saved instead, and at the target
  time it is executed with a headless `claude --continue` in the directory
  you scheduled from. The same happens as a fallback if the terminal window
  is gone at fire time. Reattach afterward with `claude --continue`; the
  raw output is also kept in `~/.claude/auto-resume/resume-<timestamp>.log`.
  Force it with `claude-auto-resume --offline <time> [instruction]`.

## Install

```bash
./install.sh
```

This symlinks:

- `auto-resume.sh` → `~/.local/bin/claude-auto-resume` (script on PATH)
- `commands/auto-resume.md` → `~/.claude/commands/auto-resume.md`
  (slash command)

`xdotool` is optional (needed only for terminal injection on X11 outside
tmux — skip it if you always use tmux, or if offline mode is enough):

```bash
sudo apt install xdotool
```

## Uninstall

```bash
./uninstall.sh
```

Removes the two symlinks above (only if they still point into this repo)
and offers to delete `~/.claude/auto-resume/` (state/logs).

## Usage

Inside a Claude Code session, **before** the limit blocks you:

```
/auto-resume 2h30m
```

**After** the limit already hit (the model can't respond, so the slash
command won't work) — use the shell escape instead, it runs locally:

```
! claude-auto-resume 3h
```

Time formats: `2h30m`, `45m`, `90` (minutes), `19:45`, `7pm`.
Optional second argument overrides the typed instruction (default
`continue`):

```
! claude-auto-resume 19:05 "continue the task from where you left off"
```

Force offline mode (save the instruction, run it headlessly at the time):

```
! claude-auto-resume --offline 19:05 "continue the task from where you left off"
```

Manage:

```
claude-auto-resume status            # lists ALL pending jobs, this terminal's marked
claude-auto-resume cancel            # cancels this terminal's job (or the only one)
claude-auto-resume cancel <id>       # cancels a specific job (id shown by status)
claude-auto-resume cancel all        # cancels every pending job
```

### Multiple terminals, tabs, and tmux windows/panes

Each terminal can have its own pending resume at the same time — jobs are
keyed per terminal (tmux pane / X11 window) + working directory, so
scheduling in one terminal never touches another terminal's job.
Re-running `claude-auto-resume` from the same terminal+directory replaces
only that terminal's job.

- **tmux**: fully supported at any granularity — every pane in every
  window/session is a distinct target (`$TMUX_PANE`), and `send-keys`
  reaches it even when it isn't the active pane. This is the most reliable
  setup for many concurrent sessions.
- **X11 terminal windows** (xdotool): each *window* is a distinct target.
- **Tabs inside one X11 terminal window**: X11 sees the whole window, not
  individual tabs — at fire time the window is activated and the keystrokes
  land in whichever tab is *currently selected*. If you run several Claude
  sessions in tabs of the same window, prefer tmux (or separate windows);
  otherwise make sure the right tab is selected at fire time, or use
  `--offline`.

## Notes & limitations

- Give a time a few minutes **after** the stated reset time, to be safe.
- With the tmux/xdotool backends, the terminal window must still be open at
  fire time (it does not need to be focused — it gets re-activated
  automatically). If it is gone, the tool falls back to offline mode.
  Don't lock the screen: X11 key injection can't reach a locked session.
- `xdotool` is X11 only (it cannot type into Wayland windows). On Wayland,
  run Claude inside tmux — the tmux backend needs no display at all — or
  rely on offline mode.
- Offline mode runs `claude` non-interactively (`--print`), so tools that
  need interactive permission approval won't be usable in that run. It is
  best for "continue where you left off" instructions; reattach with
  `claude --continue` to review and keep going. Extra CLI args can be
  passed via `AUTO_RESUME_CLAUDE_ARGS`.
- State/log live in `~/.claude/auto-resume/`.

---

## Session Guardian — automatic progress notes + auto-resume

`claude-session-guardian` is a **Stop hook** (fires after every Claude Code
turn) that watches for the "You've hit your session limit · resets HH:MM"
banner itself, so you don't have to notice it and run `claude-auto-resume`
by hand. When it sees one, it:

1. Appends a short progress note to `PROGRESS.md` in the project directory
   (timestamp, the reset banner, the scheduled resume time, and your last
   instruction — so picking the thread back up is easy).
2. Automatically runs `claude-auto-resume` for the stated reset time (+2 min
   safety buffer).

On every normal turn (the overwhelming majority) it's a fast no-op: it reads
only the tail of the current transcript and exits immediately if no limit
was hit — no visible delay, nothing written anywhere.

### How it works

- Claude Code fires the `Stop` hook after each turn and passes it JSON on
  stdin, ideally including `transcript_path`. `session-guardian.sh` falls
  back to scanning `~/.claude/projects/<project>/` for the newest `.jsonl`
  if that field is missing.
- It hands the last ~40 lines of that transcript to `detect_limit.py`, which
  checks whether the most recent assistant message is a 429 rate-limit
  error (or contains "session limit" / "resets"), and if so extracts the
  stated time and your last message.
- If a limit was hit, it dedupes against the last-seen banner (so retries
  while still blocked don't spam `PROGRESS.md` or reschedule repeatedly),
  appends the progress note, and invokes `claude-auto-resume` in the
  background. The dedup marker is kept **per session** (keyed by transcript),
  so several Claude sessions in different terminals/tabs can each hit their
  limit and each still gets its own note and scheduled resume.
- The hook runs `async: true` with a 20s timeout, so it can never stall the
  UI even briefly.

### What it can't do

Claude Code doesn't expose a hook for an early "95% of your limit" warning
— only the hard stop is a reliably observable, scriptable signal (the 429
error / "session limit" banner). This hook acts on that hard stop, which is
also the only point at which there's a concrete reset time to schedule
around.

### Install

```bash
./install-guardian.sh
```

This symlinks `session-guardian.sh` → `~/.local/bin/claude-session-guardian`
(resolving its own symlink to find `detect_limit.py` next to it) and merges
a `Stop` hook into `~/.claude/settings.json` (existing settings and other
hooks are preserved — nothing is overwritten).

Requires `jq` (to merge settings.json) and `python3` (to run the detector).
Install `claude-auto-resume` too (`./install.sh`) — without it, the hook
still writes progress notes but has nothing to call to auto-resume.

Takes effect in **new** Claude Code sessions immediately. In an already
running session, run `/hooks` once (or restart) to pick it up — Claude Code
only watches settings directories that existed when the session started.

### Uninstall

```bash
./uninstall-guardian.sh
```

Removes the symlink and the `Stop` hook entry from `~/.claude/settings.json`
(only that entry — other hooks/settings are untouched). Any `PROGRESS.md`
notes already written are left in place.

### Configuration

Environment variables, set before Claude Code starts (e.g. in your shell
profile) or per-hook via managed settings:

| Variable | Default | Purpose |
|---|---|---|
| `SESSION_GUARDIAN_PROGRESS_FILE` | `<project dir>/PROGRESS.md` | where the note is appended |
| `SESSION_GUARDIAN_BUFFER_SECONDS` | `120` | how long past the stated reset time to schedule the resume |
| `SESSION_GUARDIAN_STATE_DIR` | `~/.claude/auto-resume` | where the dedup marker is kept |
| `SESSION_GUARDIAN_DISABLE` | unset | set to `1` to no-op the hook without uninstalling |

### Notes & limitations

- Depends on `claude-auto-resume`'s own limitations for the actual resume
  (needs tmux or X11/xdotool for terminal injection; falls back to
  headless `claude --continue` otherwise — see above).
- The progress note's project directory is `$CLAUDE_PROJECT_DIR` if Claude
  Code sets it, else the hook's working directory at Stop time.
- Detection is text-pattern-based (429 status + "session limit"/"resets" in
  the banner). If Claude Code ever changes that wording, the regex in
  `detect_limit.py` (`resets?\s+(\d{1,2}:\d{2}\s*(?:am|pm)?)`) may need a
  matching update.
