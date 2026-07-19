#!/usr/bin/env bash
# claude-auto-resume — schedule an automatic "continue" keystroke into the
# terminal this script was started from, after a delay or at a clock time.
# Built for the case where a Claude Code usage limit pauses your session:
# run this (via /auto-resume or `! claude-auto-resume 3h`), and when the
# limit resets the session continues in the same terminal.
#
# Usage:
#   claude-auto-resume [--offline] <time> [message]
#   claude-auto-resume status
#   claude-auto-resume cancel [<id>|all]
#
# <time> forms:
#   2h30m | 45m | 90s     duration from now
#   90                    bare number = minutes from now
#   19:45 | 7:45pm        clock time (rolls to tomorrow if already past)
#
# [message] is what gets typed into the terminal (default: "continue").
#
# Multiple terminals/tabs/panes can each have their own pending job at the
# same time: jobs are keyed per terminal (tmux pane / X window) + directory.
# Scheduling again from the same terminal+directory replaces only that job.
# `status` lists all jobs; `cancel` with no argument cancels this terminal's
# job (or the only job), `cancel <id>` a specific one, `cancel all` every one.
#
# Backends (chosen at schedule time):
#   tmux    — if running inside tmux (works without X)
#   xdotool — X11: re-activates the terminal window, then types the message
#   offline — neither available (or --offline given): saves the instruction
#             and at the target time runs `claude --continue` headlessly in
#             this directory. Output lands in the state dir; open it later
#             with `claude --continue`. Also used as a fire-time fallback
#             when tmux/xdotool injection fails (e.g. terminal was closed).
#
# Env:
#   AUTO_RESUME_DRY=1          log the injection instead of performing it
#   AUTO_RESUME_CLAUDE_ARGS    extra args for the offline `claude` run

set -euo pipefail

STATE_DIR="${AUTO_RESUME_STATE_DIR:-$HOME/.claude/auto-resume}"
LOG_FILE="$STATE_DIR/auto-resume.log"

usage() {
    awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"
    exit 1
}

log() {
    mkdir -p "$STATE_DIR"
    printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"
}

# ---------- time parsing ----------

parse_target_epoch() {
    local input="$1" now target h=0 m=0 s=0
    now=$(date +%s)

    if [[ "$input" =~ ^([0-9]+h)?([0-9]+m)?([0-9]+s)?$ && -n "$input" ]]; then
        [[ "$input" =~ ([0-9]+)h ]] && h=${BASH_REMATCH[1]}
        [[ "$input" =~ ([0-9]+)m ]] && m=${BASH_REMATCH[1]}
        [[ "$input" =~ ([0-9]+)s ]] && s=${BASH_REMATCH[1]}
        target=$((now + 10#$h * 3600 + 10#$m * 60 + 10#$s))
    elif [[ "$input" =~ ^[0-9]+$ ]]; then
        target=$((now + 10#$input * 60))
    else
        target=$(date -d "$input" +%s 2>/dev/null) || {
            echo "error: cannot parse time '$input'" >&2
            exit 1
        }
        if ((target <= now)); then
            target=$(date -d "tomorrow $input" +%s)
        fi
    fi

    if ((target <= now)); then
        echo "error: '$input' is not in the future" >&2
        exit 1
    fi
    echo "$target"
}

# ---------- backend detection (at schedule time) ----------

detect_backend() {
    if [[ "${FORCE_OFFLINE:-}" != "1" ]]; then
        if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null; then
            BACKEND="tmux"
            # $TMUX_PANE is the pane this shell lives in — correct even when
            # other panes/windows are focused; display-message without -t
            # would report the *active* pane instead.
            TARGET_ID="${TMUX_PANE:-$(tmux display-message -p '#{pane_id}')}"
            return
        elif [[ -n "${DISPLAY:-}" ]] && command -v xdotool >/dev/null; then
            BACKEND="xdotool"
            TARGET_ID="${WINDOWID:-}"
            if [[ -z "$TARGET_ID" ]]; then
                TARGET_ID=$(xdotool getactivewindow)
            fi
            return
        fi
    fi
    # offline mode: no way to type into a terminal — save the instruction
    # and run it through a headless `claude --continue` at fire time.
    if ! command -v claude >/dev/null; then
        cat >&2 <<'EOF'
error: no backend available.
Need one of:
  - tmux (run claude inside a tmux session),
  - xdotool on X11:  sudo apt install xdotool, or
  - the `claude` CLI on PATH (for offline mode)
EOF
        exit 1
    fi
    BACKEND="offline"
    TARGET_ID="$PWD"
}

# ---------- injection (at fire time) ----------

# Resume the most recent Claude session in $workdir headlessly, feeding it
# the saved instruction. The reply is appended to that session, so a later
# interactive `claude --continue` shows the result.
fire_offline() {
    local workdir="$1" message="$2"
    local out="$STATE_DIR/resume-$(date +%Y%m%d-%H%M%S).log"
    log "offline resume: running claude --continue in $workdir"
    if (
        cd "$workdir" 2>/dev/null || cd "$HOME"
        # shellcheck disable=SC2086
        claude --continue --print ${AUTO_RESUME_CLAUDE_ARGS:-} "$message"
    ) >"$out" 2>&1; then
        log "offline resume done — output saved to $out"
    else
        log "offline resume FAILED — see $out"
    fi
}

fire() {
    local backend="$1" target_id="$2" message="$3" workdir="${4:-$HOME}"

    if [[ "${AUTO_RESUME_DRY:-}" == "1" ]]; then
        log "DRY-RUN fire: backend=$backend target=$target_id message='$message'"
        return 0
    fi

    command -v notify-send >/dev/null &&
        notify-send "claude-auto-resume" "Resuming Claude session now" || true

    local failed=0
    case "$backend" in
    tmux)
        tmux send-keys -t "$target_id" "$message" Enter || failed=1
        ;;
    xdotool)
        if ! (
            xdotool windowactivate --sync "$target_id" &&
                sleep 0.5 &&
                xdotool type --clearmodifiers --delay 50 -- "$message" &&
                sleep 0.3 &&
                xdotool key --clearmodifiers Return
        ); then
            failed=1
        fi
        ;;
    offline)
        fire_offline "$target_id" "$message"
        return 0
        ;;
    esac

    if ((failed)); then
        log "injection via $backend failed (terminal gone?)"
        if command -v claude >/dev/null; then
            log "falling back to offline resume"
            fire_offline "$workdir" "$message"
        fi
        return 0
    fi
    log "fired: backend=$backend target=$target_id message='$message'"
}

# ---------- watcher (detached background process) ----------

watch_and_fire() {
    local target_epoch="$1" backend="$2" target_id="$3" message="$4" workdir="${5:-$HOME}" job_file="${6:-}" now remaining
    # Wall-clock loop instead of one long sleep, so suspend/resume can't
    # stretch the wait past the intended time.
    while :; do
        now=$(date +%s)
        remaining=$((target_epoch - now))
        ((remaining <= 0)) && break
        sleep "$((remaining < 30 ? remaining : 30))"
    done
    fire "$backend" "$target_id" "$message" "$workdir"
    [[ -n "$job_file" ]] && rm -f "$job_file"
}

# ---------- job management ----------
# One job file per terminal+directory in $JOBS_DIR, so several terminals,
# tabs, or tmux panes can each have their own pending resume concurrently.

JOBS_DIR="$STATE_DIR/jobs"

job_key() {
    printf '%s:%s:%s' "$1" "$2" "$3" | md5sum | cut -c1-10
}

# A job file from a pre-multi-job version lives at $STATE_DIR/job; adopt it.
migrate_legacy_job() {
    [[ -f "$STATE_DIR/job" ]] || return 0
    mkdir -p "$JOBS_DIR"
    mv "$STATE_DIR/job" "$JOBS_DIR/legacy.job"
}

# Keys (one per line) this terminal+directory could have scheduled under:
# the auto-detected backend and forced-offline mode (a job scheduled with
# --offline has the offline key even when tmux/xdotool are available).
# Subshells so detect_backend's `exit` can't kill us.
current_job_keys() {
    {
        (
            detect_backend >/dev/null 2>&1
            job_key "$BACKEND" "$TARGET_ID" "$PWD"
        ) 2>/dev/null || true
        (
            FORCE_OFFLINE=1 detect_backend >/dev/null 2>&1
            job_key "$BACKEND" "$TARGET_ID" "$PWD"
        ) 2>/dev/null || true
    } | sort -u
}

list_jobs() {
    shopt -s nullglob
    local f
    for f in "$JOBS_DIR"/*.job; do echo "$f"; done
    shopt -u nullglob
}

cancel_job_file() {
    local f="$1"
    (
        # shellcheck disable=SC1090
        source "$f"
        kill "$JOB_PID" 2>/dev/null || true
        echo "cancelled auto-resume [$(basename "$f" .job)] that was set for" \
            "$(date -d "@$JOB_TARGET" '+%H:%M:%S') (dir: ${JOB_CWD:-?})"
    )
    rm -f "$f"
}

cmd_status() {
    migrate_legacy_job
    local jobs f mine
    mapfile -t jobs < <(list_jobs)
    if ((${#jobs[@]} == 0)); then
        echo "no auto-resume scheduled"
        return 0
    fi
    mine=" $(current_job_keys | tr '\n' ' ') "
    for f in "${jobs[@]}"; do
        (
            # shellcheck disable=SC1090
            source "$f"
            id="$(basename "$f" .job)"
            marker=""
            [[ "$mine" == *" $id "* ]] && marker=" (this terminal)"
            if ! kill -0 "$JOB_PID" 2>/dev/null; then
                echo "[$id] stale (watcher no longer running) — clearing"
                rm -f "$f"
            else
                echo "[$id]$marker resumes at $(date -d "@$JOB_TARGET" '+%F %H:%M:%S')" \
                    "($(((JOB_TARGET - $(date +%s)) / 60)) min from now)" \
                    "via $JOB_BACKEND, dir: ${JOB_CWD:-?}, message: '$JOB_MESSAGE'"
            fi
        )
    done
}

cmd_cancel() {
    local arg="${1:-}" jobs f key
    migrate_legacy_job
    mapfile -t jobs < <(list_jobs)
    if ((${#jobs[@]} == 0)); then
        echo "nothing to cancel"
        return 0
    fi

    if [[ "$arg" == "all" ]]; then
        for f in "${jobs[@]}"; do cancel_job_file "$f"; done
        return 0
    fi
    if [[ -n "$arg" ]]; then
        f="$JOBS_DIR/$arg.job"
        if [[ ! -f "$f" ]]; then
            echo "no job with id '$arg' — see: claude-auto-resume status" >&2
            return 1
        fi
        cancel_job_file "$f"
        return 0
    fi

    # No argument: prefer this terminal's own job; if there is exactly one
    # job anywhere, cancel that; otherwise make the user pick.
    while IFS= read -r key; do
        if [[ -n "$key" && -f "$JOBS_DIR/$key.job" ]]; then
            cancel_job_file "$JOBS_DIR/$key.job"
            return 0
        fi
    done < <(current_job_keys)
    if ((${#jobs[@]} == 1)); then
        cancel_job_file "${jobs[0]}"
        return 0
    fi
    echo "multiple auto-resume jobs exist and none belongs to this terminal:"
    cmd_status
    echo "cancel one with: claude-auto-resume cancel <id>   (or: cancel all)"
    return 1
}

cmd_schedule() {
    local time_arg="$1" message="${2:-continue}" target_epoch key job_file

    target_epoch=$(parse_target_epoch "$time_arg")
    detect_backend
    mkdir -p "$JOBS_DIR"
    migrate_legacy_job

    key="$(job_key "$BACKEND" "$TARGET_ID" "$PWD")"
    job_file="$JOBS_DIR/$key.job"

    # replace an existing job for this same terminal+directory only —
    # jobs belonging to other terminals/tabs/panes are left alone
    [[ -f "$job_file" ]] && cancel_job_file "$job_file" >/dev/null

    setsid bash "$0" --watch "$target_epoch" "$BACKEND" "$TARGET_ID" "$message" "$PWD" "$job_file" \
        </dev/null >>"$LOG_FILE" 2>&1 &
    local pid=$!
    disown "$pid" 2>/dev/null || true

    cat >"$job_file" <<EOF
JOB_PID=$pid
JOB_TARGET=$target_epoch
JOB_BACKEND=$BACKEND
JOB_TARGET_ID='$TARGET_ID'
JOB_MESSAGE='$message'
JOB_CWD='$PWD'
EOF

    log "scheduled: job=$key fire at $(date -d "@$target_epoch" '+%F %T') backend=$BACKEND target=$TARGET_ID pid=$pid"
    echo "✔ auto-resume [$key] set for $(date -d "@$target_epoch" '+%H:%M:%S')" \
        "($(((target_epoch - $(date +%s)) / 60)) min from now)."
    if [[ "$BACKEND" == "offline" ]]; then
        echo "  Offline mode: instruction '$message' saved — will run" \
            "'claude --continue' headlessly in $PWD at that time."
        echo "  Afterwards, open the session with: claude --continue"
    else
        echo "  Will type '$message' into this terminal via $BACKEND."
    fi
    echo "  cancel with: claude-auto-resume cancel"
}

# ---------- entry ----------

case "${1:-}" in
"" | -h | --help) usage ;;
--watch) shift; watch_and_fire "$@" ;;
--offline) shift; [[ $# -ge 1 ]] || usage; FORCE_OFFLINE=1 cmd_schedule "$@" ;;
status) cmd_status ;;
cancel) shift; cmd_cancel "$@" ;;
*) cmd_schedule "$@" ;;
esac
