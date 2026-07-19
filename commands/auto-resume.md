---
description: Schedule an automatic "continue" in this terminal after a delay (e.g. when your usage limit resets)
argument-hint: <time: 2h30m | 19:45 | 90> [message] | status | cancel [<id>|all]
allowed-tools: Bash(claude-auto-resume:*)
---

Run exactly this command with the Bash tool (if the arguments below are empty, run `claude-auto-resume status` instead):

```
claude-auto-resume $ARGUMENTS
```

Show the user the command's output verbatim. Do not do anything else.

If neither tmux nor xdotool is available, the tool automatically falls back to offline mode: it saves the instruction and at the target time runs a headless `claude --continue` in the current directory (the user reattaches later with `claude --continue`). For terminal injection instead, the user can install xdotool (`sudo apt install xdotool`) or run Claude inside tmux.

Important note to relay if the user asks: once a usage limit is already blocking the model, this slash command cannot run (it needs the model). In that situation the user should type the shell escape directly into Claude Code:

```
! claude-auto-resume <time>
```
