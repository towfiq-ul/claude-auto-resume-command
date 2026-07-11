# /auto-resume — continue a Claude Code session when your usage limit resets

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
claude-auto-resume status
claude-auto-resume cancel
```

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
