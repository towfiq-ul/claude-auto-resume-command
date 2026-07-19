#!/usr/bin/env bash
# claude-session-guardian — Stop hook that watches for a Claude Code usage
# limit being hit, and when it happens:
#   1. appends a short progress note to PROGRESS.md (or your configured file)
#   2. automatically schedules claude-auto-resume for the stated reset time
#      (+ a safety buffer), so you don't have to type it in by hand.
#
# It is a fast no-op on every normal turn: it only reads the tail of the
# current session transcript and exits immediately if no limit was hit.
#
# Env overrides:
#   SESSION_GUARDIAN_PROGRESS_FILE   default: <project dir>/PROGRESS.md
#   SESSION_GUARDIAN_BUFFER_SECONDS  default: 120 (schedule this long past
#                                    the stated reset time, for safety)
#   SESSION_GUARDIAN_STATE_DIR       default: ~/.claude/auto-resume
#   SESSION_GUARDIAN_DISABLE=1       no-op the whole hook
set -euo pipefail

[[ "${SESSION_GUARDIAN_DISABLE:-}" == "1" ]] && exit 0

resolve_dir() {
  local src="${BASH_SOURCE[0]}"
  while [ -L "$src" ]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}
script_dir="$(resolve_dir)"

command -v python3 >/dev/null 2>&1 || exit 0

# Read the hook's stdin JSON (may be {} or absent) to try to get an explicit
# transcript_path / session id; fall back to scanning ~/.claude/projects/.
hook_input="$(cat 2>/dev/null || true)"
transcript_path=""
if command -v jq >/dev/null 2>&1 && [[ -n "$hook_input" ]]; then
  transcript_path="$(printf '%s' "$hook_input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
fi

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"

if [[ -z "$transcript_path" || ! -f "$transcript_path" ]]; then
  proj_key="$(printf '%s' "$project_dir" | sed 's/[^a-zA-Z0-9]/-/g')"
  proj_transcript_dir="$HOME/.claude/projects/$proj_key"
  [[ -d "$proj_transcript_dir" ]] || exit 0
  transcript_path="$(ls -t "$proj_transcript_dir"/*.jsonl 2>/dev/null | head -1 || true)"
fi
[[ -n "$transcript_path" && -f "$transcript_path" ]] || exit 0

# Only look at the tail — the transcript can be large, and we only care
# about the most recent turn.
eval "$(tail -n 40 "$transcript_path" | python3 "$script_dir/detect_limit.py")"

[[ "${LIMITED:-0}" == "1" ]] || exit 0
[[ -n "${RESET_TIME:-}" ]] || exit 0

state_dir="${SESSION_GUARDIAN_STATE_DIR:-$HOME/.claude/auto-resume}"
mkdir -p "$state_dir"
# Dedup per session (keyed by transcript path), not globally — several
# terminals/tabs can hit their limits independently and each still gets
# its own progress note + scheduled resume.
session_key="$(printf '%s' "$transcript_path" | md5sum | cut -c1-10)"
dedup_file="$state_dir/session-guardian-last-$session_key"

# Avoid re-acting every retry while still blocked (Stop fires repeatedly).
last_seen=""
[[ -f "$dedup_file" ]] && last_seen="$(cat "$dedup_file" 2>/dev/null || true)"
if [[ "$last_seen" == "$RESET_TEXT" ]]; then
  exit 0
fi
printf '%s' "$RESET_TEXT" > "$dedup_file"

buffer="${SESSION_GUARDIAN_BUFFER_SECONDS:-120}"
target_epoch="$(date -d "$RESET_TIME" +%s 2>/dev/null || true)"
if [[ -n "$target_epoch" ]]; then
  now="$(date +%s)"
  if (( target_epoch <= now )); then
    target_epoch="$(date -d "tomorrow $RESET_TIME" +%s)"
  fi
  target_epoch=$(( target_epoch + buffer ))
  target_arg="$(date -d "@$target_epoch" '+%Y-%m-%d %H:%M:%S')"
else
  target_arg="$RESET_TIME"
fi

progress_file="${SESSION_GUARDIAN_PROGRESS_FILE:-$project_dir/PROGRESS.md}"
{
  echo ""
  echo "## Paused — $(date '+%Y-%m-%d %H:%M:%S') (usage limit hit)"
  echo "- Banner: $RESET_TEXT"
  echo "- Auto-resume scheduled for: $target_arg"
  [[ -n "${LAST_USER_MSG:-}" ]] && echo "- Last instruction: \"$LAST_USER_MSG\""
  echo "- Full transcript: run \`claude-export-session\` in this directory"
} >> "$progress_file"

if command -v claude-auto-resume >/dev/null 2>&1; then
  claude-auto-resume "$target_arg" >/dev/null 2>&1 || true
fi
