# progress-beacon evals

## v1: scaffolding only

`runner.py --list` prints the three canonical cases the skill must
handle. The actual grader (live or replayed Claude session, beacon
extraction, drift-state assertion) is a v2 follow-up — v1 ships the
contract so the grader can be wired against stable case IDs.

## v1 cases

- `trigger-trivial` — skill must stay silent on a one-line answer.
- `trigger-nontrivial` — multi-step work; full begin/report/end
  lifecycle expected.
- `drift-engineered` — material scope blow-up; the loud note must fire
  on the `nominal → material` transition, and only on the transition
  (not on consecutive `material` beacons).

## What v2 looks like

Run each case as a `claude -p` invocation against a sandbox cwd, capture
the assistant transcript, regex-extract `<progress-beacon>` blocks,
parse the JSON, and assert on:
- presence/absence of begin/report/end beacons
- summary length, drift state, kind sequence
- recency-nudge hook firing (or not) when the harness fakes wall-clock advancement

Variance: n=3 minimum per case before any iteration on SKILL.md or hook
script (per the user's "don't iterate on n=1" rule).
