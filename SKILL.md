---
name: progress-beacon
description: Use during any non-trivial turn (multi-file edits, multi-step research, planning + implementation, dispatching subagents, or anything you'd ballpark at >2 minutes wall-clock). Periodically emits a `<progress-beacon>` JSON block in the assistant message text so the user's status line can render an ETA. On material drift, surfaces a loud in-line note and continues working — does NOT block the turn for user confirmation.
---

# progress-beacon — agent self-pacing for non-trivial turns

Your user can't tell how long a turn will take. They want a single visible
answer to "can I close my laptop?" — anchored to wall clock. This skill
makes that possible by having you emit a small machine-readable progress
beacon at key moments. The status line parses it and shows the figure plus
a calibrated estimate from historical sessions.

## First action requirement (DEFAULT-ON)

For any non-trivial turn — defined by the criteria below — your VERY FIRST
substantive action is emitting a `<progress-beacon> {"kind": "begin", ...}`
block in your assistant message text. Not after a few tool calls. Not "once
I have a clearer estimate." First.

If you've already dispatched a tool call without emitting a begin beacon
and the turn is non-trivial, emit the begin beacon in your NEXT assistant
message before further tool calls. Recovery is fine; silent omission is not.

The skill is silent ONLY for turns that are *clearly* trivial — one-line
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

```
<progress-beacon>
{"kind": "begin", "eta_seconds": 180, "summary": "running tests then committing", "drift": "nominal"}
</progress-beacon>
```

Required fields:
- `kind`: `"begin"` | `"report"` | `"end"`.
- `eta_seconds`: wall-clock seconds remaining. Use 0 for `kind: "end"`.
- `summary`: one-line human description, ≤80 chars.
- `drift`: `"nominal"` | `"moderate"` | `"material"`.

Optional:
- `beats_left`: discrete steps remaining (when you have a confident count).

Do NOT include `tokens_left`, `tasks`, or other fields — they're reserved
for future use.

## Lifecycle

- **First substantive action of the turn** → emit `kind: "begin"` with
  your initial estimate. This anchors the original ETA that drift is
  measured against.
- **Periodically during work** → emit `kind: "report"` beacons. Cadence
  is fuzzy ("every so often"), with a HARD BACKSTOP: never let more than
  ~5 minutes of wall-clock pass without a beacon. If you notice you've
  been working without emitting a beacon for what feels like a long
  time, that's the moment to come up for air NOW, not at some later
  "natural" break point.
- **End of substantive work** → emit `kind: "end"` with final summary.
  Status line clears the figure.

## Drift judgement

You decide the drift state, not math. Defaults:

- `nominal`: current `eta_seconds` within 1.5× the original `begin`
  estimate AND total elapsed under 30min.
- `moderate`: 1.5×–2× the original, OR approaching 30min.
- `material`: >2× the original, OR >30min absolute.

When entering `material` drift FROM A NON-MATERIAL STATE
(`nominal → material` or `moderate → material`), prepend a loud in-line
note in your same assistant message:

```
🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨

ETA CREEP — was 15min, now looking like 45min.

I'm continuing. **Press ESC and tell me to wrap up** if you'd rather
I call it here and write a handoff.

🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
```

While drift stays `material` on consecutive beacons, do NOT re-flash the
loud note. If drift recovers to `nominal`/`moderate` and later returns to
`material`, the loud note fires again — that's a genuinely new event
worth surfacing.

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
> ```
> <progress-beacon>
> {"kind": "begin", "eta_seconds": 720, "summary": "auth middleware JWT refactor", "drift": "nominal"}
> </progress-beacon>
> ```
>
> [reads files, writes new code, runs tests]"
>
> Agent (5 minutes later, after writing new middleware): "Tests are running.
>
> ```
> <progress-beacon>
> {"kind": "report", "eta_seconds": 240, "summary": "tests running, ~4 min left", "drift": "nominal"}
> </progress-beacon>
> ```"
>
> Agent (final): "Done. Tests pass.
>
> ```
> <progress-beacon>
> {"kind": "end", "eta_seconds": 0, "summary": "JWT refactor complete, all tests green", "drift": "nominal"}
> </progress-beacon>
> ```"
