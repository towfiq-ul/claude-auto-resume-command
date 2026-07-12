#!/usr/bin/env bash
# Uninstall claude-session-guardian: removes the PATH symlink and unregisters
# the Stop hook from ~/.claude/settings.json (leaves everything else intact).
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_link="${HOME}/.local/bin/claude-session-guardian"
settings_file="${HOME}/.claude/settings.json"

if [[ -L "$bin_link" ]]; then
  if [[ "$(readlink -f "$bin_link")" == "$(readlink -f "$repo_dir/session-guardian.sh")" ]]; then
    rm "$bin_link"
    echo "✔ removed $bin_link"
  else
    echo "skip: $bin_link points elsewhere, leaving it alone" >&2
  fi
else
  echo "skip: $bin_link not found" >&2
fi

if [[ -f "$settings_file" ]] && command -v jq >/dev/null 2>&1; then
  if jq -e --arg cmd "$bin_link" \
      '(.hooks.Stop // []) | any(.hooks[]?.command == $cmd)' \
      "$settings_file" >/dev/null 2>&1; then
    tmp="$(mktemp)"
    jq --arg cmd "$bin_link" '
      .hooks.Stop = ((.hooks.Stop // []) | map(select((.hooks | map(.command) | index($cmd)) == null)))
    ' "$settings_file" > "$tmp"
    mv "$tmp" "$settings_file"
    echo "✔ removed Stop hook from $settings_file"
  else
    echo "skip: no matching Stop hook found in $settings_file"
  fi
fi

echo "Done. Progress notes already written to any PROGRESS.md files are left in place."
