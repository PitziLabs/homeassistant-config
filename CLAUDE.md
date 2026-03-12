# CLAUDE.md — Home Assistant Configuration Repo

## Project Overview

This repository contains the YAML-based configuration for a Home Assistant (HASS) instance managing a residential smart home. Home Assistant runs as a VM on a Proxmox server (Intel NUC). The config is version-controlled here and deployed to the HA config directory.

## Repository Structure

```
hass/
├── config/                    # Home Assistant configuration directory
│   ├── configuration.yaml     # Main HA config — primary entry point
│   ├── automations.yaml       # Automation rules (alarm, door alerts, TTS)
│   ├── scripts.yaml           # Reusable scripts (light flash loops, Sonos grouping, siren)
│   ├── scenes.yaml            # Lighting scenes (Red Alert, Alarm Armed, Alarm Triggered)
│   ├── groups.yaml            # Entity groups (motion sensors, door sensors)
│   └── .gitignore             # Whitelists *.yaml, *.md, .gitignore; blocks secrets
├── Jenkinsfile                # CI pipeline (placeholder)
├── CLAUDE.md                  # This file — context for Claude Code
└── README.md                  # Project documentation and resurrection plan
```

## Key Conventions

- **All configuration is YAML.** Home Assistant uses YAML for declarative config.
- **Secrets are never committed.** `secrets.yaml` is gitignored. Reference secrets with `!secret key_name` in YAML files.
- **`configuration.yaml` is the root.** It uses `!include` directives to pull in automations, scripts, scenes, and groups.
- **Themes are loaded from a `themes/` directory** via `!include_dir_merge_named themes`.
- **Device IDs are hardware-specific.** After reinstall, device IDs (e.g., `38bfe615ddaea006e02cfb786649eddd` for Konnected) will change and must be updated in automations and scripts.
- **Entity IDs should be stable** if devices are named the same way during setup (e.g., `binary_sensor.front_door`).

## Integrated Hardware & Services

### Currently Configured
- **Konnected** — Wired alarm panel (door/window contact sensors, motion sensors, siren actuator)
- **Philips Hue** — Hue Go, color downlights (5–8), Hue Bridge
- **Sonos** — Multi-room speakers (kitchen, office, master bedroom)
- **Google Translate TTS** — Text-to-speech announcements
- **Mobile App** — Push notifications (entity: `notify.mobile_app_sm_g998u1`)

### Commented Out / Previously Used
- **MyQ** — Garage door opener (commented out in configuration.yaml)
- **Nest** — Thermostat via Google Device Access API (commented out)
- **Spotify** — Music integration (commented out)
- **Google Wifi** — Network sensor at 192.168.86.1

### New Hardware (Not Yet Configured)
- **Firewalla** — Network firewall/router (has a HA integration)
- **Rachio** — Smart sprinkler controller (has a native HA integration)

## Alarm System Architecture

The alarm is a `manual` alarm control panel with these states:
- **disarmed** — trigger_time: 0 (no alarm response)
- **armed_home** — 5s arming, 5s delay (doors only, no motion)
- **armed_away** — 30s arming, 20s delay (doors + motion)

When triggered:
1. Hue Go flashes red (recursive script loop)
2. Konnected siren activates (10s on/off loop)
3. Push notification sent to mobile
4. Persistent notification in HA UI

## Sensor Groups

- **`group.doors`**: front_door, basement_door, garage_door, sliding_door, side_door (Ecolink)
- **`group.motion`**: family_room_motion, office_motion

## Common Tasks

### Editing Automations
Edit `config/automations.yaml`. Each automation has: `id`, `alias`, `trigger`, `condition`, `action`. After editing, reload automations in HA (Developer Tools > YAML > Reload Automations) or restart HA.

### Adding a New Device
1. Add the integration via HA UI (Settings > Devices & Services)
2. If YAML config is needed, add it to `configuration.yaml`
3. Reference new entity IDs in automations/scripts as needed
4. Update `groups.yaml` if the device belongs to a sensor group

### Adding Secrets
Add the key-value pair to `config/secrets.yaml` (not tracked in git), then reference it in YAML config with `!secret key_name`.

## Build / Validation

- **YAML validation**: `hass --script check_config -c config/` (requires HA CLI)
- **Jenkinsfile**: Currently a placeholder. Could be extended to run config validation on push.

## Important Warnings

- Never commit `secrets.yaml`, `.storage/`, `.cloud/`, or `.google.token`
- Device IDs change on reinstall — grep for hardcoded `device_id` values and update them
- The `notify.mobile_app_sm_g998u1` entity ID is tied to a specific phone; re-register the mobile app to get the new entity ID
- Google Wifi sensor assumes the router is at `192.168.86.1` — update if network topology changed
