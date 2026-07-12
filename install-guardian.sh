#!/usr/bin/env bash
# Install claude-session-guardian: script on PATH + a Stop hook registered
# in ~/.claude/settings.json (merged in, existing hooks are preserved).
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${HOME}/.local/bin"
settings_file="${HOME}/.claude/settings.json"
hook_cmd="$bin_dir/claude-session-guardian"

command -v jq >/dev/null 2>&1 || {
  echo "error: jq is required to install (used to safely merge settings.json)" >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "warning: python3 is not installed — the hook needs it at run time." >&2
  echo "         install with: sudo apt install python3" >&2
}
command -v claude-auto-resume >/dev/null 2>&1 || {
  echo "warning: claude-auto-resume is not installed — the hook will still" >&2
  echo "         write progress notes, but can't auto-schedule a resume." >&2
  echo "         install it: ./install.sh" >&2
}

mkdir -p "$bin_dir" "$(dirname "$settings_file")"

chmod +x "$repo_dir/session-guardian.sh" "$repo_dir/detect_limit.py"
ln -sf "$repo_dir/session-guardian.sh" "$hook_cmd"
echo "✔ installed $hook_cmd -> $repo_dir/session-guardian.sh"

[[ -f "$settings_file" ]] || echo '{}' > "$settings_file"

if jq -e --arg cmd "$hook_cmd" \
    '(.hooks.Stop // []) | any(.hooks[]?.command == $cmd)' \
    "$settings_file" >/dev/null 2>&1; then
  echo "✔ Stop hook already registered in $settings_file"
else
  tmp="$(mktemp)"
  jq --arg cmd "$hook_cmd" '
    .hooks //= {} |
    .hooks.Stop = ((.hooks.Stop // []) + [{
      "hooks": [{
        "type": "command",
        "command": $cmd,
        "async": true,
        "timeout": 20
      }]
    }])
  ' "$settings_file" > "$tmp"
  mv "$tmp" "$settings_file"
  echo "✔ registered Stop hook in $settings_file"
fi

if ! jq -e --arg cmd "$hook_cmd" \
    '(.hooks.Stop // []) | any(.hooks[]?.command == $cmd)' \
    "$settings_file" >/dev/null 2>&1; then
  echo "error: hook registration did not validate — check $settings_file manually" >&2
  exit 1
fi
echo "✔ $settings_file is valid JSON and the hook is present"

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "warning: $bin_dir is not on your PATH — add it to your shell profile." >&2 ;;
esac

echo ""
echo "Done. This takes effect in NEW Claude Code sessions automatically."
echo "In an already-running session, open /hooks once (or restart) to pick it up —"
echo "settings.json is only watched for directories that existed at session start."
