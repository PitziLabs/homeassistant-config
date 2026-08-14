# ADR-0002: Three-layer state model — intent (YAML), snapshot (context/), live (MCP)

**Status:** Accepted (2026-05-18; reconstructed 2026-08-13)

## Context

By mid-May 2026 this repo had accumulated three genuinely different ways to
know or change Home Assistant state, each with its own latency and
durability, and `CLAUDE.md` did not name the distinction explicitly. PR #248
("Documentation pass: refresh drift, highlight three-layer state model")
was prompted directly: *"do a documentation pass... highlight the
mcp+context dump+intent store (yaml) layers."* At that point the repo already
had all three mechanisms in place — git-tracked YAML deployed by
`gitops-sync.sh`, a 6-hourly `context/` snapshot dump, and the
`homeassistant-ai/ha-mcp` HACS integration for live access — but nothing
tied them together with rules for which one to trust when they disagreed.

Two prior, narrower decisions fed into this one. PR #237 had already
established MCP skill discipline and a "drift guardrail" distinguishing
`.storage/`-backed live writes from git-tracked config. And the repo had, up
to that point, maintained a hand-written entity reference table directly in
`CLAUDE.md` — which went stale every time an entity was renamed or added,
because nothing regenerated it.

## Decision

`CLAUDE.md` names and diagrams three coordinated layers, with intent flowing
right to left:

- **Intent (YAML, git)** — `/config/*.yaml`, PR-gated, deployed by GitOps
  within 5 minutes of merge. The durable source of truth for anything that
  should survive a rebuild.
- **Snapshot (`context/`)** — a generated, read-only dump refreshed every 6
  hours (or on demand). Fast, grep-friendly structural lookups; never a write
  target. `.claude/hooks/block-context-writes.sh` (PR #215, 2026-05-13)
  enforces the read-only property mechanically — a `PreToolUse` hook that
  rejects Edit/Write/Bash operations that would mutate `context/`, on the
  reasoning that "the snapshot is the runtime's output, not Claude's."
- **Live (HA-MCP)** — the `ha-mcp` HACS integration's REST/WebSocket surface.
  Current-to-the-second state, history, logs, and service calls; writes here
  land in `.storage/` (gitignored), not git.

**Layer-selection rule:** read from the cheapest layer that's still accurate
enough — YAML for intent, `context/` for cheap structural lookups, MCP only
when staleness would mislead or history/logs/service calls are needed.

**Drift-resolution rules:** if `context/` and MCP disagree, MCP wins (the
snapshot is stale, not wrong — refresh it). If YAML and the live runtime
diverge for something that belongs in YAML, YAML is canonical — reconcile by
editing YAML and letting GitOps redeploy.

A companion runbook, `docs/cross-layer-changes.md` (PR #329, 2026-06-01),
extends the model to changes that span layers: it orders operations by
change type (add / remove / modify / rename) and gives a rename recipe for
the hard case where an entity ID can't exist under two names at once.

## Alternatives

- **Recorded at the time:** keep a hand-maintained entity reference table in
  `CLAUDE.md`. This was the actual prior state, retired by PR #267
  ("`context/entities.json` is the grep-friendly authoritative version") —
  worse in practice because nothing forced the table to stay in sync with
  entity renames, and it silently drifted between edits.
- **Recorded at the time (narrower predecessor):** treat MCP config-write
  tools (`ha_config_set_*`) as a normal path for creating automations,
  scripts, and scenes that should persist. The drift guardrail demotes this
  to prototyping only — anything written via `ha_config_set_*` lands in
  `.storage/` (gitignored) and must be hand-migrated to YAML before it's
  considered durable, specifically because a `.storage/`-only object doesn't
  survive a rebuild and isn't PR-reviewed.
- **Retrospective — not considered at the time:** treat `context/` as
  writable and let Claude patch it directly when a fact looks wrong, instead
  of only ever regenerating it from HA. Worse — it would turn a derived
  artifact into a second source of truth that could disagree with the system
  it's derived from, exactly the inconsistency the model exists to prevent;
  the hook that blocks this was in fact already merged five days before this
  model was formally written up (#215 vs #248), suggesting the "snapshot is
  read-only" instinct predated its explicit naming.

## Consequences

- Every future HA-config task in this repo has a documented answer to "which
  layer do I trust here" instead of relying on the assistant's judgment call
  each time.
- `context/` staleness has a defined remediation (`input_button.ha_context_dump_now`
  + re-run) rather than being an ambiguous "results may be out of date"
  caveat.
- The model creates an ongoing maintenance obligation: any new object type
  that can be created via MCP needs an explicit ruling on which repo
  convention (git YAML vs `.storage/`) it belongs to, or the drift guardrail
  table in `CLAUDE.md` goes stale the same way the old entity table did.
- PR #267 (2026-05-26) later confirmed the three-layer model and the MCP
  discipline block were the two sections judged too load-bearing to trim
  during a 873→438-line `CLAUDE.md` reduction — direct evidence this decision
  held up under a fleet-wide documentation audit five weeks after being made.
