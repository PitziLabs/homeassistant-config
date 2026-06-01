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
| `scripts.json` | `.storage/script` | Sorted JSON array of storage-mode script definitions. Empty (`[]`) when the script integration is YAML-mode (UI editor writes to `/config/scripts.yaml`). Populated when ha-mcp prototypes scripts into `.storage/`. |
| `scenes.json` | `.storage/scenes` | Sorted JSON array of storage-mode scene definitions. Empty (`[]`) when the scene integration is YAML-mode (`/config/scenes.yaml`). |
| `helpers.json` | `.storage/{input_boolean,input_number,input_text,input_select,input_datetime,timer,counter,schedule}` | Object keyed by helper domain, each value a sorted JSON array of helper items. Missing-domain values are `[]` so the shape is presence-stable across instances. |
| `dashboards-storage.json` | `.storage/lovelace_dashboards`, `.storage/lovelace`, `.storage/lovelace.*` | Object with `dashboards` (registry of storage-mode dashboards) and `configs` (per-dashboard config keyed by storage filename). YAML-mode dashboards under `dashboards/*.yaml` are NOT captured here — they're already source-of-truth in git. |
| `kiosk-latest.png` | `snapshot-server` on pve2 (HTTP GET) | Live frame of the household kiosk monitor at dump time. Best-effort: if pve2 is down or `snapshot-server` is unreachable, the previous file is retained and the rest of the dump proceeds. Use for visual reference in collaborative dashboard design — shows the *real* rendered state (alarm color, current Sonos art, active media tile), not a fresh re-render. See `kiosk-host/README.md` for the producer. |

## Refresh cadence

- **Manual:** press `input_button.ha_context_dump_now` in the HA UI.
- **Periodic:** every 6 hours via the `ha_context_dump_periodic` automation.
- **On registry change (debounced):** the `ha_context_dump_on_registry_change`
  automation fires a dump 15 minutes after the last entity/device/area
  registry change (`mode: restart` coalesces a burst into one dump), so the
  snapshot tracks material changes without waiting for the 6-hour cycle.

Snapshots that match the current `main` content produce no PR (silent no-op).
