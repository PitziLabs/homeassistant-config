# Cowork → Claude Code Dashboard Workflow

A runbook for collaboratively designing HA dashboards with Cowork (live iteration), then handing off the finished spec to Claude Code (implementation).

## The mental model

Three phases, two actors, one canonical record.

```
┌──────────────────────┐   ┌──────────────────────┐   ┌──────────────────────┐
│ PHASE 1: DESIGN      │   │ PHASE 2: HANDOFF     │   │ PHASE 3: IMPLEMENT   │
│                      │   │                      │   │                      │
│ Actor:   Chris+Cowork│   │ Actor:   Cowork      │   │ Actor:   Claude Code │
│ Surface: HA storage  │   │ Surface: draft PR    │   │ Surface: PR branch   │
│ Output:  approved    │ → │ Output:  PR body w/  │ → │ Output:  commits +   │
│          YAML        │   │          @claude     │   │          ready PR    │
└──────────────────────┘   └──────────────────────┘   └──────────────────────┘
         live                  spec frozen              CI → auto-merge
       (mutable)              (immutable)             → gitops-sync deploys
```

The PR is the canonical record from Phase 2 forward — matches the convention adopted in PR #248 ("PR carries the canonical record of intent"). No GitHub issues are created at any point.

---

## State layers — where work lives at each phase

| Phase | Where the design lives | Why |
|-------|------------------------|-----|
| 1. Design | `/lovelace-draft` storage-mode dashboard (gitignored, scratchpad) | Live preview against real renderer with real entities; zero risk to production dashboards |
| 1.5. Lock-in | Cowork extracts YAML from `context/dashboards-storage.json` after snapshot dump | Ground truth for what was approved — not Cowork's recollection |
| 2. Handoff | Draft PR branch `cowork/<slug>` with the final YAML committed | Spec is now frozen and reviewable |
| 3. Implement | Same PR branch, additional commits from `@claude` | Continuity — one PR, one history |
| Deploy | `main` after merge → `/config/dashboards/<name>.yaml` via gitops-sync | Production source of truth |
| Cleanup | Storage-mode draft deleted via `ha_config_delete_dashboard` | Snapshot stops capturing it; no drift |

---

## Phase 1: Live design loop

**Cowork steps:**

1. Confirm intent with Chris (1–2 AskUserQuestion rounds for scope).
2. Run `ha_get_skill_home_assistant_best_practices` and read `dashboard-guide.md` + `dashboard-cards.md`. (REQUIRED per CLAUDE.md.)
3. Query `context/entities.json` for any entities the dashboard will reference; verify they exist.
4. Generate initial YAML for a storage-mode dashboard.
5. `ha_config_set_dashboard` with `url_path: lovelace-draft`, `title: "Cowork Draft — <feature>"`, `icon: mdi:test-tube`, `show_in_sidebar: true`, `mode: storage`.
6. Tell Chris: "Open Home Assistant → sidebar → 'Cowork Draft — <feature>' on the device that matters (TV, phone, laptop)."
7. Iterate: Chris reacts, Cowork edits via `ha_config_set_dashboard` (full-replace) or surgical updates. Optionally drive Chrome MCP to view the dashboard from Cowork's side for sanity checks.
8. When Chris says "ship it":
   - Press `input_button.ha_context_dump_now` so the snapshot captures the final state.
   - Wait ~30 sec for the dump script.
   - Read the final config from `context/dashboards-storage.json` — this is the canonical source for the next phase.

**Failure modes:**

- *Entity 404 at render*: snapshot may be stale; ask Chris to press the context-dump button, re-verify in `entities.json`.
- *Card-mod or HACS card not loading*: storage-mode dashboards inherit the same resource registry as YAML dashboards, so this means the resource is genuinely missing. Fall back to a built-in card or HACS-install the missing resource first (separate PR).
- *Chris hates it on the TV but liked it on the phone*: the kiosk has its own theme (`Kiosk Polish`) and a different viewport. Confirm which surface this dashboard targets before iterating further.

---

## Phase 2: Handoff (Cowork opens the draft PR)

**Cowork steps:**

1. Create a branch: `git checkout -b cowork/<short-slug>` (via Desktop Commander, in `~/repos/homeassistant-config`).
2. Write the YAML file: `dashboards/<name>.yaml` with the final config from `context/dashboards-storage.json`. Translate the storage-mode `views` array directly — they're the same schema.
3. Edit `configuration.yaml` to register the dashboard under `lovelace.dashboards`. Use the same conventions as the existing four dashboards (file path, mode: yaml, title, icon, sidebar).
4. Commit with a proper message including `Prompt-Origin:` trailer summarizing the Cowork conversation (per CLAUDE.md PR Authoring section).
5. Push the branch.
6. Open a **draft** PR with the body template below. Include `@claude` mention as the last line so the `claude.yml` workflow picks it up. Do **not** arm auto-merge yet — wait until CC marks ready-for-review.

**PR body template:**

```markdown
## Origin

<Two-to-four sentence narrative summary of the Cowork conversation. What was
asked for, what constraints were specified, what trade-offs Cowork flagged
during live design. Link to the storage-mode draft URL if still live.>

## What this PR does

- Adds `dashboards/<name>.yaml`
- Registers it in `configuration.yaml` under `lovelace.dashboards.<key>`
- <Any helper/template/group additions also required>

## Acceptance criteria for @claude

- [ ] The YAML file added matches the live storage-mode draft at `/lovelace-draft` (verify via `ha_config_get_dashboard`).
- [ ] All entity_ids referenced exist in `context/entities.json`.
- [ ] `ha-config-check` passes.
- [ ] No new HACS resources required (or, if any, they're documented as
      a separate follow-up PR).
- [ ] After merge, manually delete the storage-mode draft via
      `ha_config_delete_dashboard(url_path="lovelace-draft")` so the
      snapshot stops capturing it.

## Validation steps (run by @claude before marking ready)

1. Read the PR diff.
2. `ha_eval_template` any Jinja in the new YAML.
3. Cross-check entity_ids against `context/entities.json`.
4. If anything fails the checklist, comment on the PR with what's wrong
   and leave it in draft. Do not mark ready.

@claude please review the checklist above, perform validation steps,
and if all green: mark the PR ready for review.
```

7. Tell Chris the PR URL + summary of what was committed.

---

## Phase 3: Claude Code implements

This phase is mostly automated. CC reacts to the `@claude` mention via the existing `.github/workflows/claude.yml`.

**What CC does:**

1. Reads the PR body and the diff.
2. Runs validation steps from the checklist (template eval, entity verification, lint).
3. If anything is wrong: comments on the PR with specifics, leaves it in draft. Chris or Cowork addresses, pushes more commits, CC re-reviews.
4. If all green: marks PR ready for review, arms auto-merge (`gh pr merge <num> --auto --squash --delete-branch`).
5. Required status checks fire: `YAML Lint`, `check-config`, `claude-review`.
6. On all-green, GitHub auto-merges to main.
7. Within 5 min, `gitops-sync` automation polls, fetches main, validates via Supervisor API, smart-reloads (lovelace.reload_resources for dashboard-only changes — no full restart needed).

**Cleanup (Cowork or Chris, after PR merges):**

- `ha_config_delete_dashboard(url_path="lovelace-draft")` to remove the scratch dashboard.
- Next 6-hour context dump captures the cleanup; `context/dashboards-storage.json` no longer references it.

---

## When to NOT use this workflow

- **Trivial single-line YAML edits** to existing dashboards. Just have Chris (or Cowork directly) open a PR. The storage-mode draft adds overhead that's not worth it.
- **Theme-only changes** (CSS variable tweaks in `themes/kiosk_polish.yaml`). Faster to iterate in-file and ask Chris to reload.
- **Non-dashboard work** (automations, packages, ESPHome firmware). This workflow is dashboard-shaped. Other surfaces may want a similar pattern with different live-preview tools (e.g., automation traces for automation work).

---

## Capability prerequisites

| Capability | Status as of <date> | How to verify |
|------------|---------------------|---------------|
| HA MCP write access (storage-mode dashboards) | ✅ confirmed | `ha_config_set_dashboard` returns success |
| Chrome MCP with browser connected | ✅ confirmed | `list_connected_browsers` returns ≥1 local browser |
| Desktop Commander shell on Chris's box | ✅ confirmed | Can `cd ~/repos/homeassistant-config` |
| `gh` CLI authenticated | ⚠️ needs `gh auth login` once | `gh auth status` shows valid token |
| Repo has `.github/workflows/claude.yml` | ✅ confirmed | File exists, references `anthropics/claude-code-action` |
| `gitops-sync` automation running | ✅ confirmed | `automation.gitops_sync_poll` in `on` state |

If any prerequisite is broken, Cowork should fail loudly at the start of Phase 1 rather than discover it at the handoff.

---

## Open questions for refinement

These came up during workflow design and are worth pinning down on first real run:

1. **PR base branch convention.** Always `main`? Or do we want a `cowork-staging` branch for batching multiple Cowork-originated PRs before they hit main?
2. **CC's auto-merge authority.** The CLAUDE.md PR Authoring section says PR author arms auto-merge. If CC marks the PR ready for review, does CC also arm auto-merge, or is that Chris's call?
3. **Storage-mode draft naming collisions.** If two Cowork sessions overlap, both could try to use `/lovelace-draft`. Should we suffix with timestamp or session ID?
4. **Failure recovery.** If CC's `claude.yml` workflow fails (rate limit, API issue), how does Cowork notice? Polling the PR state via `gh pr view`?
5. **Where this doc lives.** Add a section in CLAUDE.md? Drop in `docs/workflows/`? Split: short reference in CLAUDE.md, full runbook in `docs/workflows/cowork-cc-handoff.md`.

---

## Try-it checklist for first real run

When ready to exercise this end-to-end:

- [ ] Verify all prerequisites (table above)
- [ ] Pick a small but real dashboard change (e.g., add one new card to `command-deck.yaml`)
- [ ] Walk Phase 1 → Phase 2 → Phase 3
- [ ] After merge, write down the rough edges you hit
- [ ] Update this runbook with the lessons
- [ ] After two or three real runs, promote the stabilized version into CLAUDE.md
