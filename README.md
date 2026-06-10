# skills-progress-beacon

Agent-emitted progress beacons during non-trivial Claude Code turns, plus
a calibrated "when can I close my laptop?" status-line render.

## What it is

The skill (`SKILL.md`) tells the agent to periodically emit a small
machine-readable JSON block in its assistant message text:

```text
<progress-beacon>
{"kind": "begin", "eta_seconds": 720, "summary": "auth refactor"}
</progress-beacon>
```

`claude-walker` (separate repo) parses these from the active session
transcript on demand. The status line (`schoen-claude-status`, separate
repo) renders the live beacon plus a calibrated ETA derived from a
7-day median of `actual_elapsed / begin_eta` ratios.

Two hooks keep the agent honest (see "Nudge paths and rate limiting"
below): a UserPromptSubmit reminder of the trigger criteria at the
start of each prompt, and a PostToolUse recency nudge when the
transcript shows no recent beacon.

For the user-facing render — what each field on line 3 of the status
line means, and how to read the wall-clock anchors, drift colors, and
error states — see the **Line 3 (beacon)** section of the
[schoen-claude-status README](https://github.com/mtschoen/schoen-claude-status#what-you-see).

## Installation (3 components)

1. **The skill itself** — installed by skills-dev's installer:

   ```bash
   ~/skills-dev/install-skills.sh progress-beacon
   ```

   Lands at `~/.claude/skills/progress-beacon/`.

2. **`claude-walker`** — install the production C++ binary:

   ```bash
   cd ~/claude-walker && bash install.sh   # or install.bat on Windows
   ```

   Puts `claude-walker(.exe)` at `~/.local/bin/`. Add that dir to PATH
   if it isn't there.

3. **`schoen-claude-status` patches** — already merged on `main`; the
   helpers `format_beacon` and `format_calibrated_eta` activate
   automatically once `claude-walker` is on PATH.

## Hook configuration

Add these entries to `~/.claude/settings.json` so the prompt reminder
fires on each user prompt and the recency nudge after tool calls:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/skills/progress-beacon/hooks/prompt-reminder.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/skills/progress-beacon/hooks/recency-nudge.sh"
          }
        ]
      }
    ]
  }
}
```

If the `hooks` block already exists, merge carefully — preserve the
other entries.

## Nudge paths and rate limiting

`hooks/prompt-reminder.sh` (UserPromptSubmit) injects a one-line
reminder of the trigger criteria on each user prompt, unless the
session's latest visible beacon is a live `begin`/`report` (mid-turn
prompt while the agent is already pacing).

`hooks/recency-nudge.sh` (PostToolUse) has two paths:

- **Stale path:** the latest visible beacon is a live (non-`end`)
  beacon older than 10 minutes. An `end` beacon silences it - the
  lifecycle is closed.
- **Missing path:** no beacon is visible at all and the session is
  older than a 5-minute grace period.

Both paths share a per-session cooldown (5 minutes, stamp file under
`$TMPDIR/progress-beacon-nudge/`), so one stale window produces one
nudge, not a burst on every tool call of a parallel batch.

Two facts of life shape those thresholds (learned from the 2026-06
false-nudge incidents):

- Claude Code persists mid-turn assistant messages to the session
  JSONL with multi-minute lag - sometimes never, for text-only
  mid-turn messages. A beacon the agent just emitted can be invisible
  to `claude-walker` for minutes, so sub-5-minute thresholds nag about
  beacons that were in fact emitted.
- `end` beacons must be visible for the stale path to stand down.
  `claude-walker` (>= the 2026-06-10 build) treats `eta_seconds` as
  optional on `kind: "end"` (defaulting to 0), because agents
  routinely omit it there; older walker builds silently dropped such
  end beacons, leaving lifecycles permanently open and the stale
  nudge firing forever with a growing minutes counter.

## Beacon format

Required fields: `kind` (`"begin"` | `"report"` | `"end"`),
`eta_seconds` (number), `summary` (string ≤80 chars).

Optional: `beats_left`. All other fields are reserved.

## Layout

- `SKILL.md` — the skill body the agent reads.
- `hooks/prompt-reminder.sh` — UserPromptSubmit trigger-criteria reminder.
- `hooks/recency-nudge.sh` — PostToolUse staleness backstop (rate-limited).
- `evals/` — v1 scaffolding; live grader is a v2 follow-up.
- `workspace/` — gitignored; per-iteration scratch.

## Status

v1 ships in 2026-05. Real-session shake-down is tracked in the author's
cross-project memory, outside this repo.
