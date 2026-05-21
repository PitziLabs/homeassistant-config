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

Four automations managing a physical meeting-in-progress indicator for Rachel's office. An ESP32 button device drives two lights as a visual signal: `light.meeting_light` (a dedicated hallway indicator) and `light.door_lamp` (an office lamp).

| Automation ID | Trigger | Action |
|---------------|---------|--------|
| `meeting_status_on` | Button `off` → `on` | Snapshot `door_lamp`, then hallway + office lamp → red (RGB 255,0,0, brightness 255) |
| `meeting_status_off` | Button `on` → `off` | Hallway light → off; office lamp → restored to its pre-meeting state |
| `meeting_button_offline` | Button unavailable for 10 s | Hallway light → off; office lamp → restored (fail-safe) |
| `meeting_button_reconnect` | Button becomes available | Re-sync hallway + office lamp to current button state |

**Hallway vs. office lamp.** The hallway light is a dedicated indicator — it is simply turned red or off. The office lamp is a general-purpose light that may already be in use, so instead of being turned off when the meeting ends it is **restored to its pre-meeting state**. `meeting_status_on` captures that state into a runtime scene (`scene.meeting_office_door_lamp_snapshot`) via `scene.create` immediately before going red; the OFF/offline/reconnect handlers reapply it with `scene.turn_on`.

The restore steps gate on `light.meeting_light` being on — it is the proxy for "the indicator is currently showing." This prevents a button blip while no meeting is active from clobbering `door_lamp` with a stale snapshot.

The offline/reconnect pair handles an important edge case: if the ESP32 drops off WiFi while the button is on, the lights would remain red indefinitely. The 10-second unavailability trigger clears them (hallway off, office lamp restored); the reconnect trigger restores the correct state without manual intervention.

## Adding automations

Create a new `.yaml` file in this directory. HA will pick it up on the next restart or reload. No changes to `configuration.yaml` are needed.

Name files by functional domain (e.g., `lighting.yaml`, `climate.yaml`) rather than creating one file per automation.
