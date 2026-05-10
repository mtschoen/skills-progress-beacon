#!/usr/bin/env bash
# PostToolUse hook: nudge the agent if no beacon has been emitted recently.
# Reads hook stdin (Claude Code provides JSON), shells out to claude-walker,
# decides whether to inject additionalContext.
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
    kind="$(printf '%s' "$beacon" | jq -r '.kind')"
    # Only nudge live beacons; an end-beacon means the agent has already
    # closed out and a stale-end is just inactivity, not under-trigger.
    if [[ "$kind" != "end" ]]; then
        # Bash float comparison via awk.
        if awk -v a="$age" 'BEGIN{exit !(a > 300)}'; then
            minutes=$(awk -v a="$age" 'BEGIN{printf "%d", a/60}')
            needs_nudge=1
            nudge_msg="No progress beacon emitted in ${minutes}+ minutes. If this turn is non-trivial, please emit a <progress-beacon> 'report' now."
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
