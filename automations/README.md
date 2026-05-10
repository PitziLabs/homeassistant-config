# automations/

Git-managed automations. This directory is the pipeline's exclusive domain — the HA UI editor never writes here. HA merges all `.yaml` files in this directory at startup via `!include_dir_merge_list automations/` in `configuration.yaml`.

## Governance model

Automations in this project are split by authority:

| Location | Authority | Edit surface |
|----------|-----------|-------------|
| `automations.yaml` | HA UI editor | Settings → Automations (UI drift is expected and reconciled manually) |
| `automations/` | Git / PR | This directory only — never touched via the HA UI |

This partition prevents the GitOps pipeline from silently clobbering UI edits. The `git reset --hard origin/main` in the deploy script would overwrite any UI change to a git-tracked file. The separation makes the authority explicit.

## Files

### `meeting.yaml` — Meeting Indicator

Four automations managing a physical meeting-in-progress indicator for Rachel's office. An ESP32 button device drives a hallway light as a visual signal.

| Automation ID | Trigger | Action |
|---------------|---------|--------|
| `meeting_status_on` | Button entity turns `on` | Hallway light → red (RGB 255,0,0, brightness 150) |
| `meeting_status_off` | Button entity turns `off` | Hallway light → off |
| `meeting_button_offline` | Button unavailable for 10 s | Hallway light → off (fail-safe) |
| `meeting_button_reconnect` | Button becomes available | Re-sync hallway light to current button state |

The offline/reconnect pair handles an important edge case: if the ESP32 drops off WiFi while the button is on, the hallway light would remain red indefinitely. The 10-second unavailability trigger clears it; the reconnect trigger restores the correct state without manual intervention.

### `sonoff_button_kitchen_family.yaml` — Sonoff Button 1 (Downstairs)

ZHA device trigger automations for the Sonoff button near the kitchen/family room (IEEE `f0:44:d3:ff:fe:f6:94:01`).

| Automation ID | Trigger | Action |
|---------------|---------|--------|
| `sonoff_button_1_kitchen_family_on` | Single press (`remote_button_short_press`) | Downstairs lights ON full brightness + family room outlets ON |
| `sonoff_button_1_kitchen_family_off` | Double press (`remote_button_double_press`) | Downstairs lights OFF + family room outlets OFF |

Uses `trigger: device` with `domain: zha` for stability across ZHA quirk updates (replaces the old `trigger: event` / `event_type: zha_event` approach that was brittle to `command:` payload changes — see issues #155, #156).

**Required before use:** Replace `device_id: REPLACE_WITH_DEVICE_ID_FOR_SONOFF_BUTTON_1` with the actual HA device registry UUID from Settings → Devices & Services → ZHA → (device).

### `sonoff_button_outdoor.yaml` — Sonoff Button 2 (Outdoor)

ZHA device trigger automations for the Sonoff button controlling outdoor lights (IEEE `18:69:0a:ff:fe:13:a1:01`).

| Automation ID | Trigger | Action |
|---------------|---------|--------|
| `sonoff_button_2_outdoor_on` | Single press (`remote_button_short_press`) | Outdoor lights ON |
| `sonoff_button_2_outdoor_off` | Double press (`remote_button_double_press`) | Outdoor lights OFF |

Same device trigger pattern as Button 1. See issues #155, #156.

**Required before use:** Replace `device_id: REPLACE_WITH_DEVICE_ID_FOR_SONOFF_BUTTON_2` with the actual HA device registry UUID from Settings → Devices & Services → ZHA → (device).

## Adding automations

Create a new `.yaml` file in this directory. HA will pick it up on the next restart or reload. No changes to `configuration.yaml` are needed.

Name files by functional domain (e.g., `lighting.yaml`, `climate.yaml`) rather than creating one file per automation.
