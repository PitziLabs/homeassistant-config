# Cross-Layer Changes — a stacking runbook

**Status:** Active runbook

A companion to the *Three-Layer State Model* in `CLAUDE.md`. That section
describes what the three layers **are**; this one describes how to **mutate
across them** without leaving a window of inconsistency.

## The hazard

A single logical change ("rename the office Sonos", "add a UPS dashboard
section") fans out across layers that have different latencies and different
durability:

| Layer | Write path | Propagation | Durable? |
|---|---|---|---|
| **LIVE** (`.storage`) | MCP (`ha_set_entity`, `ha_config_set_*`, …) | immediate | no — gitignored runtime state |
| **INTENT** (git YAML) | PR → merge → `gitops-sync` | ~5 min after merge | yes — source of truth |
| **SNAPSHOT** (`context/`) | `ha-context-dump.sh` | 6 h, or on `input_button.ha_context_dump_now` | derived, read-only |

The failure mode is **any moment where a consuming layer references state the
providing layer doesn't have** — yet, or anymore:

- Rename the LIVE entity before INTENT is updated → the deployed dashboards
  dangle on the old id until the YAML PR merges and deploys.
- Merge INTENT referencing a new id before the LIVE entity exists → the new
  YAML refs are broken until you create the entity.
- Either way, the SNAPSHOT lags both and the `Dashboard Entities` gate reads
  the (stale) snapshot, not live state.

## Order depends on the change type

There is no single safe order — it depends on whether the change adds, removes,
or renames the thing other layers consume:

| Change type | Safe order | Why |
|---|---|---|
| **Add** (new entity + YAML that uses it) | LIVE → SNAPSHOT → INTENT | the consumer (YAML) must land *after* the entity exists. The `Dashboard Entities` gate enforces this: it checks refs against the snapshot, so YAML can't merge referencing an entity the snapshot doesn't yet have. |
| **Remove** (drop an entity and its refs) | INTENT → deploy → LIVE | remove the consumers *before* the thing they consume, so nothing ever dangles. |
| **Modify in place** (retune a value, no id change) | INTENT only | nothing else references a new identity. |
| **Rename** (atomic remove+add on the LIVE side) | the hard one — see below | the old id vanishes the instant you rename; old and new can't coexist. |

## Rename recipe (the hard case)

HA's entity rename is atomic — there's no moment where both ids exist — so some
window is unavoidable. Minimise it:

1. **Prepare INTENT first, green but unmerged.** Open the YAML PR with *every*
   consumer edited (find them with `grep` over git + `ha_deep_search` for
   UI-managed automations/scripts + a `context/` check). Get CI green.
   - The `Dashboard Entities` gate will fail because the new id isn't in the
     snapshot yet. **Temporarily add the new id to
     `dashboards/entity-allowlist.txt` with a `# pending rename` note** — the
     allowlist is the coordination ledger for in-flight ids.
2. **Execute the LIVE change, verify.** `ha_set_entity new_entity_id=…`, then
   `ha_get_state` to confirm the new id resolves and the old one is gone.
3. **Merge INTENT and force the deploy.** Merge the green PR, then run
   `scripts/force-sync.sh` (or call `shell_command.gitops_sync`) instead of
   waiting on the 5-minute poll. Post-deploy, `ha_check_config` + an
   error-log scan. The window shrinks from "5+ min" to "seconds".
4. **Reconcile the SNAPSHOT.** `force-sync.sh` also presses
   `input_button.ha_context_dump_now`; the drift PR updates `context/`. Once the
   new id is in the snapshot, the checker's **"can be removed"** note flags the
   temporary allowlist entry — prune it.

## The machinery already exists

Most of the pieces are already in the repo; the discipline is the ordering:

- **Coordination ledger** — `dashboards/entity-allowlist.txt`. A "pending rename"
  or "pending integration" id lives here until the snapshot catches up;
  `scripts/check-dashboard-entities.py` emits a "can be removed" note when it
  becomes redundant, which is the burn-down signal.
- **Window collapse** — `scripts/force-sync.sh` triggers an immediate gitops
  deploy + context dump so you don't wait on the 5-min / 6-h timers.
- **Deploy + validate** — `scripts/gitops-sync.sh` (validates via `/core/check`,
  rolls back on failure).
- **Snapshot reconcile** — `ha-context-dump.sh` + the `ha-context-sync.yml`
  drift PR.

## Worked example — renaming the office Sonos (PR #328)

The office speaker carried `media_player.basement` (stale adoption name) while an
orphaned `media_player.office` ghost occupied the desired id.

1. Mapped consumers: `configuration.yaml` (leader template), `home.yaml`,
   `command-deck.yaml`, `home.yaml`; `ha_deep_search` confirmed no UI
   automations referenced either id.
2. LIVE: removed the ghost, renamed `media_player.basement` →
   `media_player.office`, verified with `ha_get_state`.
3. INTENT: dropped the duplicate `sonos_basement_leader` template and the
   "Basement" cards (the `sonos_office_leader` / "Office" cards became correct).
4. **Ordering miss to learn from:** the LIVE rename was done *before* the INTENT
   PR merged, so the deployed dashboards rendered a few Sonos cards
   `unavailable` until merge + deploy. Next time, prepare-INTENT-green-first and
   `force-sync.sh` immediately after merge to close that window.
