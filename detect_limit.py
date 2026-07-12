#!/usr/bin/env python3
"""Check whether the most recent assistant turn in a Claude Code transcript
hit a usage-limit error, and extract the stated reset time and last user
message. Reads transcript lines from stdin (newest-last, as in the .jsonl
file) so the caller can feed it just a tail instead of the whole file.

Prints shell-safe `KEY='value'` lines to stdout for `eval` by the caller:
  LIMITED=0|1
  RESET_TEXT   full banner text (only if LIMITED=1)
  RESET_TIME   the "HH:MM(am|pm)" match, if found
  LAST_USER_MSG  most recent user message text, for the progress note
"""
import json
import re
import sys

RESET_RE = re.compile(r"resets?\s+(\d{1,2}:\d{2}\s*(?:am|pm)?)", re.IGNORECASE)


def esc(s):
    return (s or "").replace("\\", "\\\\").replace("'", "'\\''")


def assistant_text(entry):
    content = entry.get("message", {}).get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    return ""


def user_text(entry):
    content = entry.get("message", {}).get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        for b in content:
            if isinstance(b, dict) and b.get("type") == "text" and b.get("text", "").strip():
                return b["text"]
    return ""


def main():
    lines = sys.stdin.readlines()
    entries = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            continue

    limited = False
    reset_text = ""
    for e in reversed(entries):
        if e.get("type") != "assistant":
            continue
        text = assistant_text(e)
        is_error = e.get("isApiErrorMessage", False)
        status = e.get("apiErrorStatus")
        if is_error and status == 429:
            limited = True
            reset_text = text
        elif "session limit" in text.lower() and "reset" in text.lower():
            limited = True
            reset_text = text
        break  # only the most recent assistant entry decides current state

    if not limited:
        print("LIMITED=0")
        return

    last_user = ""
    for e in reversed(entries):
        if e.get("type") == "user":
            t = user_text(e)
            if t.strip():
                last_user = t.strip()
                break

    print("LIMITED=1")
    print(f"RESET_TEXT='{esc(reset_text.strip())}'")
    m = RESET_RE.search(reset_text)
    print(f"RESET_TIME='{esc(m.group(1).strip()) if m else ''}'")
    print(f"LAST_USER_MSG='{esc(last_user[:200])}'")


if __name__ == "__main__":
    main()
