# skills-progress-beacon

Agent-emitted progress beacons during non-trivial Claude Code turns, plus
a calibrated "when can I close my laptop?" status-line render.

## What it is

The skill (`SKILL.md`) tells the agent to periodically emit a small
machine-readable JSON block in its assistant message text:

```
<progress-beacon>
{"kind": "begin", "eta_seconds": 720, "summary": "auth refactor", "drift": "nominal"}
</progress-beacon>
```

`claude-walker` (separate repo) parses these from the active session
transcript on demand. The status line (`schoen-claude-status`, separate
repo) renders the live beacon plus a calibrated ETA derived from a
7-day median of `actual_elapsed / begin_eta` ratios.

A PostToolUse hook (`hooks/recency-nudge.sh`) injects an
`additionalContext` reminder if the agent goes >5 minutes without a
beacon during a turn that already started one.

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

Add this PostToolUse entry to `~/.claude/settings.json` so the
recency-nudge hook fires after each tool call:

```json
{
  "hooks": {
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

## Beacon format

Required fields: `kind` (`"begin"` | `"report"` | `"end"`),
`eta_seconds` (number), `summary` (string ≤80 chars), `drift`
(`"nominal"` | `"moderate"` | `"material"`).

Optional: `beats_left`. All other fields are reserved.

## Layout

- `SKILL.md` — the skill body the agent reads.
- `hooks/recency-nudge.sh` — PostToolUse hook for the >5 min backstop.
- `evals/` — v1 scaffolding; live grader is a v2 follow-up.
- `workspace/` — gitignored; per-iteration scratch.

## Status

v1 ships in 2026-05. Real-session shake-down lives at
`~/.claude/notes/project_progress_beacon.md`.
