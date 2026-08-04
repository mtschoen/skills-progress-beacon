---
name: progress-beacon
description: Use during any non-trivial turn (multi-file edits, multi-step research, planning + implementation, dispatching subagents, or anything you'd ballpark at over 2 minutes wall-clock). Periodically emits a progress-beacon JSON block in the assistant message text so the user's status line can render an ETA. On material drift, surfaces a loud in-line note and continues working - does NOT block the turn for user confirmation.
---

# progress-beacon - agent self-pacing for non-trivial turns

Your user can't tell how long a turn will take. They want a single visible
answer to "can I close my laptop?" - anchored to wall clock. This skill
makes that possible by having you emit a small machine-readable progress
beacon at key moments. The status line parses it and shows the figure plus
a calibrated estimate from historical sessions.

## First action requirement (DEFAULT-ON)

For any non-trivial turn - defined by the criteria below - your VERY FIRST
substantive action is emitting a `<progress-beacon> {"kind": "begin", ...}`
block in your assistant message text. Not after a few tool calls. Not "once
I have a clearer estimate." First.

**This applies to every non-trivial turn, not just the first turn of the
session.** A "turn" = one user prompt + the agent's response to it. If the
previous turn ended with `kind=end` (or had no beacon at all), the next
non-trivial turn opens a brand new lifecycle with a fresh `begin`. Do NOT
skip straight to `report` thinking the work is "continuing" - the status
line treats `end` as a hard lifecycle terminator and will render a loud
red `⏱ no begin` until you emit one. The UserPromptSubmit hook reminds
you when the prior turn closed with an end; act on it.

If you've already dispatched a tool call without emitting a begin beacon
and the turn is non-trivial, emit the begin beacon in your NEXT assistant
message before further tool calls. Recovery is fine; silent omission is not.

The skill is silent ONLY for turns that are *clearly* trivial - one-line
answers, simple Q&A, single-file lookups, exploratory dialog like
brainstorming. Borderline → emit. The cost of an unneeded `begin` is one
fenced block; the cost of a missing one is a user staring at a blank
status line for 20 minutes.

## Non-trivial turn criteria

A turn meets the threshold if ANY of these hold:

- The task involves multi-file edits.
- The task involves multi-step research or planning.
- You will dispatch subagents.
- You'd ballpark the turn at >2 minutes of wall-clock work.

Trivial-skip applies only when NONE of these hold AND the turn is plainly
a one-shot. Don't talk yourself out of a beacon by reframing a multi-step
task as "really just one thing."

## Beacon format

Every beacon is a fenced block in your assistant message text:

```text
<progress-beacon>
{"kind": "begin", "eta_seconds": 180, "summary": "running tests then committing"}
</progress-beacon>
```

Required fields:

- `kind`: `"begin"` | `"report"` | `"end"`.
- `eta_seconds`: wall-clock seconds remaining. Use 0 for `kind: "end"`.
- `summary`: one-line human description, ≤80 chars.

Optional:

- `beats_left`: discrete steps remaining (when you have a confident count).

Do NOT include `tokens_left`, `tasks`, or other fields - they're reserved
for future use.

## Lifecycle

Each non-trivial turn is its own self-contained lifecycle: `begin` →
zero-or-more `report`s → `end`. The next turn opens a fresh lifecycle.
Don't carry an old `begin` across turn boundaries.

- **First substantive action of the turn** → emit `kind: "begin"` with
  your initial estimate. This anchors the ETA for THIS turn. Drift is
  measured against this anchor, not any earlier turn's begin.
- **Periodically during work** → emit `kind: "report"` beacons. Cadence
  is fuzzy ("every so often"), with a HARD BACKSTOP: never let more than
  ~5 minutes of wall-clock pass without a beacon. If you notice you've
  been working without emitting a beacon for what feels like a long
  time, that's the moment to come up for air NOW, not at some later
  "natural" break point.
- **End of substantive work** → emit `kind: "end"` with final summary.
  Status line clears the figure. The lifecycle is now closed; the NEXT
  non-trivial turn requires a new `begin`. A `report` emitted after an
  `end` with no intervening `begin` will render as `⏱ no begin` - the
  status line is telling you to fix the omission, not retroactively
  reuse the previous turn's anchor.

## Surfacing ETA creep loudly

When your own work has clearly blown past its original estimate, flash a
loud in-line note so the user notices without having to stare at the
status line.

Compute the trigger explicitly; don't self-assess a vibe. On each beacon,
let `elapsed` = wall-clock seconds since THIS turn's `begin` and `eta` =
your current `eta_seconds`. The turn has crossed the **material**
threshold when:

```text
(elapsed + eta) / original_begin_eta >= 2     OR     elapsed > 1800
```

When you cross that threshold FROM BELOW IT (the previous beacon was
under it), prepend a loud in-line note in the same assistant message:

```text
🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨

ETA CREEP - was 15min, now looking like 45min.

I'm continuing. **Press ESC and tell me to wrap up** if you'd rather
I call it here and write a handoff.

🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
```

Once you're over the threshold, do NOT re-flash the note on consecutive
beacons. If your estimate recovers back under it and later crosses again,
the loud note fires again - that's a genuinely new event worth surfacing.

## Hooks

Two optional shell hooks reinforce this skill from outside the model
context - see the repo README's "Hook configuration" section for how to
register them:

- `hooks/prompt-reminder.sh` (`UserPromptSubmit`) - reminds you of the
  trigger criteria at the start of each prompt, unless a live beacon is
  already visible.
- `hooks/recency-nudge.sh` (`PostToolUse`) - nudges when the transcript
  shows no beacon, or a stale one, past a grace period.

Both require external tooling this skill does not bundle: the
agent-walker CLI (`agent-walker beacons-latest --session-id <id>`,
returning JSON shaped like `{"beacon": {"kind": "..."}, "age_seconds":
N}`; the project is [agent-walker](https://github.com/mtschoen/agent-walker/))
and `jq`.

The two dependencies fail differently, and the two hooks don't degrade
the same way when agent-walker is missing or erroring (that call is
wrapped in `|| true`, so it never crashes either hook):
`hooks/recency-nudge.sh` falls through to `{}` and exit 0 right away -
a genuine silent no-op, it just stops nudging.
`hooks/prompt-reminder.sh` loses its only signal for "a beacon is
already active" and instead emits the reminder unconditionally on
every prompt - noisy, not silent. There is no other fallback for
either hook.

A missing `jq` is not silent in either hook - both scripts run under
`set -euo pipefail`, so an unwrapped `jq` call exits the hook non-zero
instead of emitting `{}`. Install `jq` before enabling either hook.

Neither hook is required for the beacon behavior itself: the "First
action requirement" above comes from this skill body, not from the
hooks. Treat the hooks as a backstop reminder, not the mechanism that
makes beacons happen.

## What this skill does NOT do

- Does not stop and ask "keep going or wrap?" as a blocking question.
  ETA creep is inform-and-continue. The user's override path is ESC +
  verbal request, not a yes/no prompt.
- Does not prescribe how to compute `eta_seconds`. Honest approach:
  estimate remaining steps × rough seconds/step. Calibration math in
  the status line corrects for systematic bias.
- Does not differentiate orchestrator vs. subagent. Whichever agent
  reads this skill applies it to its own work; the per-row vs. main-bar
  render is a status-line concern, not a skill-body concern.

## Examples

**Trivial turn (no beacon):**
> User: "what does this function do?"
> Agent: [reads file, answers]
> No beacon emitted.

**Non-trivial turn (begin → report → end):**
> User: "refactor the auth middleware to use JWTs"
>
> Agent: "Plan: read existing middleware, draft new version, update tests, run.
>
> ```text
> <progress-beacon>
> {"kind": "begin", "eta_seconds": 720, "summary": "auth middleware JWT refactor"}
> </progress-beacon>
> ```
>
> [reads files, writes new code, runs tests]"
>
> Agent (5 minutes later, after writing new middleware): "Tests are running.
>
> ```text
> <progress-beacon>
> {"kind": "report", "eta_seconds": 240, "summary": "tests running, ~4 min left"}
> </progress-beacon>
> ```"
>
> Agent (final): "Done. Tests pass.
>
> ```text
>
> <progress-beacon>
> {"kind": "end", "eta_seconds": 0, "summary": "JWT refactor complete, all tests green"}
> </progress-beacon>
> ```"
