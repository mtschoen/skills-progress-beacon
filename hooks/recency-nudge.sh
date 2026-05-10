#!/usr/bin/env bash
# PostToolUse hook: nudge the agent if no beacon has been emitted recently,
# OR if no beacon has been emitted at all in a session that's been alive
# past a short grace period.
set -euo pipefail

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
if [[ -z "$session_id" ]]; then
    echo '{}'
    exit 0
fi

walker_out="$(claude-walker beacons-latest --session-id "$session_id" 2>/dev/null || true)"
if [[ -z "$walker_out" ]]; then
    echo '{}'
    exit 0
fi

beacon="$(printf '%s' "$walker_out" | jq -c '.beacon // null')"
age="$(printf '%s' "$walker_out" | jq -r '.age_seconds // empty')"

needs_nudge=0
nudge_msg=""

if [[ "$beacon" != "null" && -n "$age" && "$age" != "null" ]]; then
    # Stale-beacon path: a beacon exists but hasn't been refreshed.
    kind="$(printf '%s' "$beacon" | jq -r '.kind')"
    # Only nudge live beacons; an end-beacon means the agent has already
    # closed out and a stale-end is just inactivity, not under-trigger.
    if [[ "$kind" != "end" ]]; then
        if awk -v a="$age" 'BEGIN{exit !(a > 300)}'; then
            minutes=$(awk -v a="$age" 'BEGIN{printf "%d", a/60}')
            needs_nudge=1
            nudge_msg="No progress beacon emitted in ${minutes}+ minutes. If this turn is non-trivial, please emit a <progress-beacon> 'report' now."
        fi
    fi
else
    # Missing-beacon path: walker reports no beacon at all. Nudge if the
    # session has been alive past a short grace period (~90s) so trivial
    # one-shot turns don't get spammed.
    jsonl=""
    for f in "$HOME"/.claude/projects/*/"$session_id".jsonl; do
        if [[ -f "$f" ]]; then
            jsonl="$f"
            break
        fi
    done
    if [[ -n "$jsonl" ]]; then
        first_ts="$(jq -r 'select(.timestamp) | .timestamp' "$jsonl" 2>/dev/null | head -1 || true)"
        if [[ -n "$first_ts" ]]; then
            first_epoch="$(date -d "$first_ts" +%s 2>/dev/null || echo 0)"
            now_epoch="$(date +%s)"
            session_age=$((now_epoch - first_epoch))
            if [[ "$first_epoch" -gt 0 && "$session_age" -gt 90 ]]; then
                minutes=$((session_age / 60))
                needs_nudge=1
                nudge_msg="ATTENTION: this session has been running for ${minutes}+ minutes with NO progress-beacon emitted. If this turn is non-trivial (multi-file edits, multi-step research, dispatching subagents, or >2 minutes wall-clock), your NEXT assistant message MUST include a <progress-beacon> 'begin' block before any further tool calls. If the turn is genuinely trivial (one-off Q&A, single-file lookup), ignore this nudge."
            fi
        fi
    fi
fi

if [[ "$needs_nudge" -eq 1 ]]; then
    jq -n --arg msg "$nudge_msg" '{
        hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: $msg
        }
    }'
else
    echo '{}'
fi
