# ADR-0003: Partition automations by authority — UI-owned root file vs git-owned directory

**Status:** Accepted (2026-04-19; reconstructed 2026-08-13)

## Context

Home Assistant has two legitimate ways to create an automation: the Settings
→ Automations UI editor, and hand-written YAML. Both were in active use in
this repo — Chris edited some automations through the HA UI for convenience,
while others were authored as reviewable git YAML. Both write paths target
files HA merges at startup, and the GitOps deploy script
(`scripts/gitops-sync.sh`, added the same week in commits `9ec63a7`/`8c84f7e` — PRs #46/#52)
deploys by running `git reset --hard origin/main` against the live config
directory.

That combination is unsafe without a rule: `git reset --hard` overwrites any
file it tracks with the git version, discarding local changes. If UI-authored
automations lived in a git-tracked file, the next GitOps sync would silently
clobber them the moment `main` next diverged — a UI edit could vanish without
anyone touching git. The GitOps deploy script itself had landed two days
earlier (PRs #46 and #52, 2026-04-17), so the hazard was live, not
hypothetical, by the time PR #63 (2026-04-19, closing issue #62) addressed it
by moving the Meeting Indicator automations that had previously lived inline
in `automations.yaml` into a new `automations/` directory, and splitting
`configuration.yaml`'s automation loading into two labeled keys so HA merges
both sources without a key collision.

## Decision

Automations are partitioned by editing surface, not by feature area:

| Location | Authority | Edit surface |
|---|---|---|
| `automations.yaml` (root) | HA UI editor | Settings → Automations; UI drift is expected and reconciled into git manually |
| `automations/*.yaml` | Git / PR | This directory only — never touched via the HA UI |

`configuration.yaml` loads both under separate keys (`automation ui:
!include automations.yaml`, `automation manual: !include_dir_merge_list
automations/`) so HA merges them at runtime with no collision. The rule that
makes the partition necessary, not just tidy, is explicit in the repo
docs: *"The `git reset --hard origin/main` in the deploy script would
overwrite any UI change to a git-tracked file. The separation makes the
authority explicit."* Reconciling UI drift into git is a manual, occasional
step (SSH in, copy the current `automations.yaml`, open a PR), not an
automated sync in either direction.

## Alternatives

- **Recorded at the time:** the pre-#63 status quo — every automation,
  including UI-editable ones, coexisting in files the GitOps pipeline could
  overwrite. Issue #62 (which PR #63 closes) flagged this risk directly and used it as the
  reason for the split; it wasn't a hypothetical, it was the bug being fixed.
- **Retrospective — not considered at the time:** go fully UI-managed for all
  automations, with periodic export of `automations.yaml` into git as a
  backup rather than a source of truth. This is the mainstream Home
  Assistant pattern for hobbyist installs. Worse for this repo's stated
  design goals specifically: PR-gated review and rebuild survival are load-
  bearing here (see [ADR-0002](0002-three-layer-state-model.md)), and a
  UI-first model with git as a passive export inverts which side is
  authoritative — exactly the ambiguity the partition exists to remove.
- **Retrospective — not considered at the time:** a bidirectional sync tool
  that reconciles `automations.yaml` and `automations/` automatically on
  every GitOps run. Plausibly better ergonomics if it existed reliably, but
  strictly riskier than the manual reconciliation actually chosen — an
  automated merge of UI and git state is exactly the kind of tool that fails
  silently in the one case (concurrent edits to the same automation from
  both sides) where correctness matters most, and this repo has no CI
  coverage that could catch that failure mode before it reached the live
  system.

## Consequences

- Every new git-managed automation must go in `automations/` as its own
  functional-domain file (`automations/README.md`: "Name files by functional
  domain... rather than creating one file per automation"), never appended to
  the root file.
- UI convenience is preserved for automations that don't need review (quick
  Chris-only tweaks), at the cost of a manual, easy-to-forget reconciliation
  step — nothing currently alerts when `automations.yaml` has UI drift worth
  promoting to git.
- The partition is enforced by convention and file-location discipline only;
  there is no CI check that fails a PR for editing the wrong file. The
  `Dashboard Entities` / `check-config` gates validate YAML correctness, not
  which authority a given automation change came from.
