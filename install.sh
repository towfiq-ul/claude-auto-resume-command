#!/usr/bin/env bash
# Install claude-auto-resume: script on PATH + Claude Code slash command.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${HOME}/.local/bin"
cmd_dir="${HOME}/.claude/commands"

if ! command -v xdotool >/dev/null 2>&1 && [ -z "${TMUX:-}" ]; then
  echo "note: xdotool is not installed and you're not in tmux." >&2
  echo "      terminal injection needs one of the two; offline mode still works." >&2
  echo "      install with: sudo apt install xdotool" >&2
fi

mkdir -p "$bin_dir" "$cmd_dir"

chmod +x "$repo_dir/auto-resume.sh"
ln -sf "$repo_dir/auto-resume.sh" "$bin_dir/claude-auto-resume"
echo "✔ installed $bin_dir/claude-auto-resume -> $repo_dir/auto-resume.sh"

ln -sf "$repo_dir/commands/auto-resume.md" "$cmd_dir/auto-resume.md"
echo "✔ installed $cmd_dir/auto-resume.md (slash command /auto-resume)"

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "warning: $bin_dir is not on your PATH — add it to your shell profile." >&2 ;;
esac

echo "Done. Type /auto-resume <time> inside Claude Code, or run claude-auto-resume <time> from a shell."
