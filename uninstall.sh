#!/usr/bin/env bash
# Uninstall claude-auto-resume: removes the PATH symlink and the slash command.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_link="${HOME}/.local/bin/claude-auto-resume"
cmd_link="${HOME}/.claude/commands/auto-resume.md"

remove_if_ours() {
  local link="$1" target="$2"
  if [ -L "$link" ]; then
    if [ "$(readlink -f "$link")" = "$(readlink -f "$target")" ]; then
      rm "$link"
      echo "✔ removed $link"
    else
      echo "skip: $link points elsewhere, leaving it alone" >&2
    fi
  elif [ -e "$link" ]; then
    echo "skip: $link exists but is not a symlink, leaving it alone" >&2
  else
    echo "skip: $link not found" >&2
  fi
}

remove_if_ours "$bin_link" "$repo_dir/auto-resume.sh"
remove_if_ours "$cmd_link" "$repo_dir/commands/auto-resume.md"

if [ -d "${HOME}/.claude/auto-resume" ]; then
  read -r -p "Also delete state/logs in ~/.claude/auto-resume/? [y/N] " reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    rm -rf "${HOME}/.claude/auto-resume"
    echo "✔ removed ~/.claude/auto-resume/"
  fi
fi

echo "Done."
