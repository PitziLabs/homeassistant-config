# ADR-0001: PRs, not issues, dispatch changes — with an explicit carve-out for latent problems

**Status:** Accepted (2026-05-12; reconstructed 2026-08-13)

## Context

Through early May 2026 this repo followed the conventional GitHub flow: a
change was requested by opening an issue (often `@claude`-mentioned), and a
PR closed it. Issue #200 (2026-05-12) proposed dropping that step: "From the
next PR forward, I dispatch work by talking to Claude Code directly, and the
PR itself carries the canonical record of intent," and stated plainly that it
was "intentionally the last issue-driven change for this repo."

Nineteen days later, issue #308 (2026-05-31) surfaced a case the new
convention didn't anticipate: a kiosk-display OOM that Chris noticed only by
accident, with no PR in flight to record it against. The follow-up decision,
codified in PR #309 the same day, drew a boundary the original convention had
left implicit — "no issues" was about *change dispatch*, not about issues as
a mechanism at all.

## Decision

**Two paired rules, not one:**

1. **No issues for change dispatch.** Changes are requested by talking to
   Claude Code directly; the PR body is the durable record of what was asked
   for and why. There is no `@claude`-on-issue step in the loop.
2. **Do file issues for incidentally-observed latent problems.** When Claude
   (or anyone) notices a silent failure, a leak, a degrading component, or a
   stale reference while doing unrelated work, it gets a GitHub issue with
   the symptom, relevant logs/measurements, and candidate fixes — not just a
   verbal heads-up in chat, which vanishes. The issue is the durable triage
   queue for follow-up work that has no attached fix yet.

Because rule 1 removes the issue-per-PR habit, the PR summary carries more
weight here than in repos where a linked issue also captures the ask —
skipping the who/what/why in a PR body loses information nowhere else records
it.

## Alternatives

- **Recorded at the time:** continue the issue-then-PR flow that predated
  #200. This was the actual status quo being replaced; it added a
  now-redundant round trip once Claude Code could be dispatched directly.
- **Retrospective — not considered at the time:** lightweight auto-opened
  issues for every change (e.g. a bot-filed issue per prompt, closed by the
  PR that implements it). Worse for this repo's stated goal: it duplicates
  the PR body's who/what/why in a second location that itself needs
  upkeep, and the PR summary already carries that weight precisely because
  there's no issue backing it — a shadow issue would just create two records
  that can drift from each other.

## Consequences

- Every PR here must stand alone as the record of intent — there is no issue
  to fall back on for context. This repo's `## PR summary voice` convention
  (later neutralized fleet-wide by PR #489, which dropped the `## Origin`
  section and `Prompt-Origin:` trailer in favor of a neutral action-oriented
  summary) exists partly to keep that record legible without the narrative
  scaffolding an issue would have provided.
- The two-rule split (#309) means "no issues" was never absolute; a session
  that stays quiet about an observed latent bug because "we don't do issues
  here" is misapplying the convention. #308 is the canonical example of when
  to file one.
- This repo carries no issue backlog for planned work — `ROADMAP.md` fills
  that role instead.
