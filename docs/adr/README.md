# Architecture decision records

Reconstructed 2026-08-13 from this repo's commit history, issues/PRs, and
`CLAUDE.md`. These decisions were made and acted on at the time but never
written up as ADRs; this index and the records below fill that gap after the
fact. The date in each record's Status line is the *original* decision date,
not the reconstruction date. Each record's Alternatives section separates
what was actually weighed at the time (with the issue/PR that shows it) from
options marked *"retrospective — not considered at the time"* — those are
this reconstruction's own honest assessment, not something argued over at the
time.

| ADR | Decision | Date |
|---|---|---|
| [0001](0001-pr-canonical-record-no-issue-dispatch.md) | PRs, not issues, dispatch changes — with a carve-out for latent problems | 2026-05-12 |
| [0002](0002-three-layer-state-model.md) | Three-layer state model: intent (YAML) / snapshot (`context/`) / live (MCP) | 2026-05-18 |
| [0003](0003-automation-governance-partition.md) | Partition automations by authority — UI-owned root file vs git-owned directory | 2026-04-19 |
| [0004](0004-pull-based-gitops-deploy.md) | Pull-based GitOps deploy, validated and rolled back locally | 2026-04-17 |
| [0005](0005-native-sections-retire-pixel-fit-dashboard.md) | Retire the pixel-fit wall-display layout for HA-native `sections` | 2026-06-11 |
