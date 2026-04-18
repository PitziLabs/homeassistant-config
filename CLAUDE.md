# CLAUDE.md — Home Assistant Configuration (PitziLabs/homeassistant-config)

## Project Overview

Git-controlled Home Assistant OS deployment on Proxmox VM at `192.168.139.172`. All configuration is YAML-driven — no UI-based config where avoidable. The HA UI is used only for integration setup (ESPHome device adoption, weather, Sonos, Hue, Kasa, etc.) which HA stores in `.storage/` (excluded from git).

**Config directory:** `/homeassistant/` on the VM, accessible as `/config/` from the SSH add-on.

**Owner:** Chris Pitzi (GitHub: cpitzi, org: PitziLabs)

---

## Architecture

### Alarm System (Konnected + ESPHome + Manual Alarm Platform)

Two Konnected ESP8266 alarm panels running custom ESPHome firmware (fully inlined, no remote package dependencies):

**Main Panel (56ac70)** — `192.168.139.40`
- MAC: `2C:F4:32:56:AC:70`
- ESPHome config: `/config/esphome/konnected-56ac70.yaml`
- Zones:
  - GPIO5 → Front Door (door contact, NC)
  - GPIO4 → Garage Door (door contact, NC)
  - GPIO14 → Basement Door (door contact, NC)
  - GPIO12 → Sliding Door (door contact, NC)
  - GPIO13 → Office Motion
  - GPIO3 → Family Room Motion
  - GPIO15 → Siren/Bell (ALRM terminal)

**Secondary Panel (56a4fa)** — `192.168.139.175`
- MAC: `2C:F4:32:56:A4:FA`
- ESPHome config: `/config/esphome/konnected-56a4fa.yaml`
- Zone 1 (GPIO5) → Piezo buzzer (PWM output via RTTTL)
- Zones 2-6 → Not connected
- Provides RTTTL play/stop services for alarm tones

**Alarm behavior:**
- `alarm_control_panel.home_alarm` — manual platform
- `code_arm_required: false` — arming is code-free, disarming requires code
- Alarm code: stored in `/config/secrets.yaml` as `alarm_code`
- Exit delay: 30s (away), 10s (home)
- Entry delay: 30s (away), 15s (home)
- Trigger time: 240s (4 minutes)
- All 4 doors are entry-delay (no instant zones)
- Motion: active in armed_away only, ignored in armed_home

### Automations (`/config/automations.yaml`)

7 alarm automations + 1 door chime:

| ID | Description |
|----|-------------|
| `alarm_door_trigger` | Any door open while armed → alarm_trigger |
| `alarm_motion_trigger` | Motion while armed_away → alarm_trigger |
| `alarm_exit_delay_beep` | Piezo tick every 1.5s while arming |
| `alarm_entry_delay_beep` | Piezo tick every 0.7s while pending |
| `alarm_triggered_siren` | Pending expired → siren ON |
| `alarm_disarmed` | Disarm → siren OFF, triple tick confirmation |
| `alarm_armed_confirmation` | Armed → double tick confirmation |
| `door_chime` | Door opens while disarmed → double tick |

**RTTTL tone formula:** `d=32,o=4,b=100` — short ticks at octave 4. Differentiation by tick count (1=delay, 2=armed/chime, 3=disarm) and repeat interval.

### Template Sensors (`/config/configuration.yaml`)

**Sonos group-aware sensors** (6 total):
- `binary_sensor.sonos_{office,kitchen,dining_room,master_bedroom,basement,roam}_leader`
- ON only when speaker is `playing` AND is first in its own `group_members` list (i.e., the group coordinator)
- Used by dashboard conditional cards to show only the coordinator's media card when speakers are grouped

**Per-room light activity sensors** (7 total):
- `binary_sensor.{kitchen,office,play_room,family_room,entry,outdoor}_lights_on`
- `binary_sensor.any_switch_on`
- ON when any light/switch in the room is on
- Used by the Home (mobile) view for per-room "All off" indicators

---

## Entity Reference

### Alarm & Sensors
| Entity ID | Type |
|-----------|------|
| `alarm_control_panel.home_alarm` | Manual alarm panel |
| `binary_sensor.main_panel_front_door` | Door contact |
| `binary_sensor.main_panel_garage_door` | Door contact |
| `binary_sensor.main_panel_basement_door` | Door contact |
| `binary_sensor.main_panel_sliding_door` | Door contact |
| `binary_sensor.main_panel_office_motion` | Motion sensor |
| `binary_sensor.main_panel_family_room_motion` | Motion sensor |
| `switch.alarm_panel_56ac70_siren` | Siren output (GPIO15) |

### ESPHome Services
| Service | Description |
|---------|-------------|
| `esphome.konnected_56a4fa_play_rtttl` | Play RTTTL tone on piezo (data: song_str) |
| `esphome.konnected_56a4fa_stop_rtttl` | Stop piezo playback |

### Lights
| Room | Entities |
|------|----------|
| Kitchen | `light.kitchen_main`, `light.kitchen_island`, `light.kitchen_table`, `light.kitchen_sink` |
| Office | `light.office`, `light.office_lamp`, `light.office_bookcase`, `light.office_corner`, `light.office_back_corner`, `light.office_door`, `light.desk_lamp`, `light.desk_lamp_2` |
| Play Room | `light.play_room`, `light.play_room_1`, `light.play_room_2`, `light.play_room_3`, `light.play_room_4` |
| Family Room | `light.family_room`, `light.family_room_2`, `light.floor_lamp` |
| Entry/Upstairs | `light.entry_1`, `light.entry_2`, `light.downstairs_hallway`, `light.upstairs_hallway_light` |
| Outdoor | `light.front_door`, `light.front_lantern`, `light.garage_front`, `light.garage_side`, `light.shed` |

### Switches
| Entity ID | Description |
|-----------|-------------|
| `switch.family_room_outlets` | Powers floor lamp (dependency) |
| `switch.back_porch` | Outdoor |
| `switch.garden` | Outdoor |
| `switch.play_room_outlet` | Indoor |
| `switch.bonus_room` | Indoor (often unavailable) |
| `switch.basement_1` | Indoor (often unavailable) |

### Sonos Media Players
| Entity ID | Location |
|-----------|----------|
| `media_player.office` | Office |
| `media_player.kitchen` | Kitchen |
| `media_player.dining_room` | Dining Room |
| `media_player.master_bedroom` | Master Bedroom |
| `media_player.basement` | Basement |
| `media_player.roam_2` | Portable |

### Weather
| Entity ID | Source |
|-----------|--------|
| `weather.forecast_home` | Met.no integration |

---

## Dashboard Architecture (`/config/dashboards/home.yaml`)

Registered as a named YAML dashboard in `configuration.yaml`:
```yaml
lovelace:
  dashboards:
    dashboard-home:
      mode: yaml
      filename: dashboards/home.yaml
      title: Home
      icon: mdi:home
      show_in_sidebar: true
```

### Two Views

**Home view** (`/dashboard-home/home`) — Mobile/tablet control dashboard
- Masonry layout (standard, not panel mode)
- Room-grouped vertical-stacks with conditional lights (show only when ON)
- Per-room "All off" indicators using template sensors
- Conditional Sonos media cards (playing coordinators only)
- Alarm panel with permanent sensor grid (always visible)
- Activity-driven: lights/switches appear when on, vanish when off

**Kiosk view** (`/dashboard-home/kiosk`) — 65-inch 1080p wall display
- CSS Grid layout via `layout-card` with `grid-template-areas` and `height: 100vh`
- Theme: `Noctis Kiosk` (custom theme extending Noctis with card-mod overrides)
- No scrolling — everything fits 1080p
- Always-visible: alarm card, sensor chips, all lights by room, weather
- Conditional: Sonos at bottom of Column 4, unavailable entities hidden
- Kiosk-mode hides sidebar/header for "Kiosk" user
- Alarm chip animation: pulsing glow based on alarm state (blue=armed_away, green=armed_home, red=triggered, amber=arming)

### Grid Layout (Kiosk)
```
"alarm alarm alarm alarm"
"sensors sensors sensors sensors"
"col1 col2 col3 col4"
```
- Row 1: Mushroom alarm card (compact, no keypad, `show_keypad: false`)
- Row 2: Mushroom chips bar (alarm status + door/motion sensors)
- Row 3: Four columns:
  - Col1: Kitchen + Play Room
  - Col2: Office
  - Col3: Family Room + Entry/Upstairs + Switches
  - Col4: clock-weather-card + Outdoor + conditional Sonos

### HACS Cards Installed
- `mushroom` (lovelace-mushroom) — light cards, entity cards, chips, alarm card, title cards
- `clock-weather-card` — animated weather with clock and forecast
- `mini-media-player` — compact Sonos display with album art
- `layout-card` (lovelace-layout-card) — CSS Grid layout engine
- `card-mod` (lovelace-card-mod) — CSS styling and Jinja2 templates
- `kiosk-mode` — hides sidebar/header for kiosk user

### Theme Files
- `/config/themes/noctis_kiosk.yaml` — Custom theme: Noctis colors + global card-mod
  - Lights ON: warm amber background `rgba(255, 180, 50, 0.20)`
  - Switches ON: cool blue background `rgba(72, 130, 194, 0.20)`
  - OFF: fades to `var(--card-background-color)`
  - 0.4s CSS transition between states
  - Applied globally via `card-mod-card` — no per-card styling needed
- `/config/themes/kiosk_dark.yaml` — Original custom dark theme (deprecated, replaced by Noctis Kiosk)
- Noctis base theme installed via HACS

### Kiosk Mode Config (top of dashboards/home.yaml)
```yaml
kiosk_mode:
  non_admin_settings:
    hide_header: true
    hide_sidebar: true
  user_settings:
    - users:
        - "Kiosk"
      kiosk: true
```
The "Kiosk" person/user (Settings → People) is a non-admin local account used on the wall display.

---

## File Structure

```
/config/
├── configuration.yaml          # Core config: alarm panel, template sensors, frontend, prometheus
├── automations.yaml            # 8 alarm/chime automations
├── groups.yaml                 # Door and motion sensor groups
├── scripts.yaml                # Empty
├── scenes.yaml                 # Empty
├── secrets.yaml                # WiFi, alarm code, API keys (gitignored)
├── secrets.yaml.example        # Documents required secrets
├── .gitignore                  # Excludes .storage/, db, deps, tts, secrets, etc.
├── .HA_VERSION                 # Tracks HA version (currently 2026.4.1)
├── dashboards/
│   └── home.yaml               # Two-view dashboard (Home + Kiosk)
├── themes/
│   ├── noctis_kiosk.yaml       # Active kiosk theme with card-mod overrides
│   └── kiosk_dark.yaml         # Deprecated custom theme
├── esphome/
│   ├── konnected-56ac70.yaml   # Main alarm panel firmware config
│   ├── konnected-56a4fa.yaml   # Secondary panel (piezo buzzer) firmware config
│   ├── secrets.yaml            # ESPHome WiFi + API keys (gitignored)
│   ├── secrets.yaml.example    # Documents required ESPHome secrets
│   └── .esphome/               # Build artifacts (gitignored)
└── blueprints/                 # Stock HA automation/script blueprints
```

---

## Frontend Resource Loading

In `configuration.yaml`:
```yaml
frontend:
  themes: !include_dir_merge_named themes
  extra_module_url:
    - /hacsfiles/kiosk-mode/kiosk-mode.js
    - /hacsfiles/card-mod/card-mod.js
```

Other HACS cards (mushroom, clock-weather-card, mini-media-player, layout-card) are loaded automatically by HACS — do NOT add them to `extra_module_url` or they'll double-register and throw "already been used with this registry" errors.

---

## Key Patterns & Conventions

- **Git is source of truth.** All YAML config is committed. `.storage/` is runtime state excluded from git.
- **Secrets pattern:** Real values in `secrets.yaml` (gitignored), documented keys in `secrets.yaml.example` (committed). Same pattern in `esphome/` directory.
- **ESPHome configs are fully inlined.** No `github://` remote package references. Every pin, sensor, and setting is explicit in the local YAML.
- **Entity IDs retain original adoption names.** The siren is `switch.alarm_panel_56ac70_siren` (not `switch.main_panel_siren`) because ESPHome entity IDs are set at first adoption and don't change when the device is renamed.
- **Conditional cards filter unavailable.** Every Mushroom card in the Kiosk view is wrapped in `type: conditional` with `state_not: unavailable` so offline devices silently disappear.
- **Sonos group awareness.** Template sensors detect group coordinators. Only the coordinator's media card is shown — prevents duplicate cards when speakers are grouped.
- **Global styling via theme.** The `noctis_kiosk.yaml` theme uses `card-mod-card` with `config.type` checks to automatically apply state-based backgrounds to all Mushroom cards. No per-card `card_mod` blocks in the dashboard YAML.
- **fill_container: true** on all Mushroom cards in the Kiosk view for full grid-cell color coverage.
- **Alarm animation** is on the Mushroom alarm chip in the sensor bar, using card-mod CSS `@keyframes` with Jinja2 state checks. Blue=armed_away, green=armed_home, amber=arming, red=pending/triggered.
- **PR creation includes arming auto-merge.** When implementation is complete,
  open a pull request as the final step — do not stop at "pushed the branch."
  PR title should match or clearly refine the issue title. PR body must include
  `Closes #<number>` so merge closes the issue, plus a short summary of what
  changed and why. Immediately after opening the PR, arm auto-merge with the
  number returned from `gh pr create` (or `gh pr view --json number -q .number`):

```bash
    gh pr merge PR_NUMBER --auto --squash --delete-branch
```

Auto-merge is a per-PR action, not a repo-wide default — without this command
  the PR will wait for a human click forever. Do not merge the PR yourself with
  a non-`--auto` merge; let the required status checks (`YAML Lint`,
  `claude-review`) gate the merge and fire it when green. Skip auto-merge only
  if the PR is a draft — it won't arm on drafts and will error.

---

## Infrastructure Context

- **Proxmox VM:** HA OS at `192.168.139.172`
- **Firewalla Gold SE:** `192.168.139.1` — network firewall, Zeek logs, device inventory
- **Grafana/Loki stack:** LXC `192.168.139.20` — `firewalla-grafana-stack` repo
- **Kiosk display:** 65-inch TCL 1080p TV, Chromium kiosk mode, pointed at `/dashboard-home/kiosk`
- **ESPHome Device Builder:** HA add-on, compiles and flashes firmware OTA to Konnected boards

---

## Upcoming Work

- **Firewalla HA integration** — Toggle kids' internet rules, show active rulesets, time remaining on scheduled blocks
- **Roblox activity detector** — Query Loki for Zeek DNS logs matching `roblox.com`/`rbxcdn.com`, surface as conditional tile on dashboard showing which child's device is playing
- **`firewalla-network-guardian`** — Anomaly detection module (planned PitziLabs repo)
- **Roku integration** — Two Rokus unreachable (possible Firewalla Smart Protect interference)
- **Dashboard iteration** — Ongoing polish of Kiosk view layout, colors, card sizing
