# Hue Scenes Rebuild Reference

## After the Hue Bridge Migration

These scenes were provided by the Hue Bridge integration and will be removed when the bridge is uninstalled. They are **not** defined in `scenes.yaml` — they existed only as integration-provided entities in HA's runtime state.

**To re-enable scenes after rebuilding:** Search the repo for `TODO(hue-rebuild): scene.<name>` and uncomment the corresponding blocks. As of this audit, no such blocks exist (see note below).

---

## Audit Result

Audit performed: 2026-05-10
Files searched: all `.yaml`, `.yml`, `.json`, `.md`, `.jinja`, `.j2` files in the repository

**Result: No references found.** None of the 20 at-risk scene entity IDs are referenced in any automation, script, dashboard card, or template in this repo. There are no `TODO(hue-rebuild):` comment blocks to uncomment.

---

## Pre-Migration Scene Entity IDs

These entity IDs will vanish once the Hue Bridge integration is uninstalled:

| Entity ID | References in Repo |
|-----------|-------------------|
| `scene.family_room_read` | _(none)_ |
| `scene.office_concentrate` | _(none)_ |
| `scene.office_energize` | _(none)_ |
| `scene.office_high_red` | _(none)_ |
| `scene.office_low_red` | _(none)_ |
| `scene.office_nightlight` | _(none)_ |
| `scene.office_office_candle` | _(none)_ |
| `scene.office_office_prism` | _(none)_ |
| `scene.office_read` | _(none)_ |
| `scene.office_relax` | _(none)_ |
| `scene.play_room_alexa_scene` | _(none)_ |
| `scene.play_room_concentrate` | _(none)_ |
| `scene.play_room_dimmed` | _(none)_ |
| `scene.play_room_energize` | _(none)_ |
| `scene.play_room_high_red` | _(none)_ |
| `scene.play_room_natural_light` | _(none)_ |
| `scene.play_room_nightlight` | _(none)_ |
| `scene.play_room_read` | _(none)_ |
| `scene.play_room_relax` | _(none)_ |
| `scene.play_room_rest` | _(none)_ |

---

## Rebuild Checklist

For each scene you wish to restore after the ZHA migration:

1. Configure the lights to the desired state (brightness, color temp, color).
2. In HA UI → **Settings → Scenes**, create a new scene and snapshot the current light states.
   - Alternatively: call `scene.create` with `snapshot_entities` to capture the live state.
3. Note the new scene entity ID (it will differ from the Hue-provided IDs above).
4. Update any automations, scripts, or dashboard cards that should call the new scene.
