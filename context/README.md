# context/

**Auto-generated. Do not edit. Do not modify files in this directory by hand or
via Claude Code — they will be overwritten on the next snapshot.**

This directory is a read-only follower of HA runtime state, populated by
`scripts/ha-context-dump.sh` and committed via the autonomous context-sync
pipeline (see `.github/workflows/ha-context-sync.yml`).

## Files

| File | Source | Purpose |
|------|--------|---------|
| `entities.json` | `.storage/core.entity_registry` | Sorted JSON array of non-disabled entities with `entity_id`, `friendly_name`, `area_id`, `device_id`, `platform`, `hidden`. Friendly names sourced from registry (`name` → `original_name` → null). |
| `areas.json` | `.storage/core.area_registry` | Sorted JSON array of areas with `area_id`, `name`. |
| `devices.json` | `.storage/core.device_registry` joined with `.storage/core.config_entries` | Sorted JSON array of devices with `device_id`, `name`, `manufacturer`, `model`, `area_id`, `integrations` (array of integration domains). |
| `automations-ui.yaml` | `/config/automations.yaml` | Byte-for-byte snapshot of the UI-editable automations file. |

## Refresh cadence

- **Manual:** press `input_button.ha_context_dump_now` in the HA UI.
- **Periodic:** every 6 hours via the `ha_context_dump_periodic` automation.

Snapshots that match the current `main` content produce no PR (silent no-op).
