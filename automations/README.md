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

## Adding automations

Create a new `.yaml` file in this directory. HA will pick it up on the next restart or reload. No changes to `configuration.yaml` are needed.

Name files by functional domain (e.g., `lighting.yaml`, `climate.yaml`) rather than creating one file per automation.
