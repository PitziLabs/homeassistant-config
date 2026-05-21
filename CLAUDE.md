# CLAUDE.md — Home Assistant Configuration (PitziLabs/homeassistant-config)

## Project Overview

Git-controlled Home Assistant OS deployment running on Proxmox. All configuration is YAML-driven — no UI-based config where avoidable. The HA UI is used only for integration setup (ESPHome device adoption, weather, Sonos, Hue, Kasa, etc.) which HA stores in `.storage/` (excluded from git).

**Config directory:** `/homeassistant/` on the VM, accessible as `/config/` from the SSH add-on.

**Owner:** Chris Pitzi (GitHub: cpitzi, org: PitziLabs)

---

## Three-Layer State Model

This repo treats Home Assistant state as three coordinated layers. Each has a
distinct job, and intent flows from right to left:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ LIVE (MCP)      │     │ SNAPSHOT        │     │ INTENT (YAML)   │
│ ha-mcp server   │  →  │ context/*.json  │  ←  │ /config/*.yaml  │
│ read + write    │     │ 6h dump, RO     │     │ git, PR-gated   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

**1. Intent (YAML, this repo)** — `/config/*.yaml` is the durable source of
truth for everything that should survive a rebuild: `automations/`, `packages/`,
`dashboards/`, `themes/`, `configuration.yaml`, ESPHome firmware, shell
scripts. Changes land via PR; the GitOps loop deploys merged main commits
within 5 minutes. **If a feature should survive a rebuild, it lives here.**

**2. Snapshot (`context/`)** — A generated artifact dumped from the live HA
instance every 6 hours (or on `input_button.ha_context_dump_now`) via
`scripts/ha-context-dump.sh`. Captures the entity/device/area registries,
the UI-managed `automations.yaml`, and storage-mode scripts/scenes/helpers/
dashboards. **Read-only** — `.claude/hooks/block-context-writes.sh` rejects
tool calls that would mutate it. The `ha-context-sync.yml` workflow opens
an auto-merging PR when the snapshot drifts from main, so the registry
state in git is never more than ~6 hours stale.

**3. Live (HA-MCP)** — The HA MCP server (`homeassistant-ai/ha-mcp` HACS
integration, running inside HA) exposes the REST and WebSocket APIs as
`mcp__*__ha_*` tools. State is current to the second; history, logs, and
service calls are accurate. Writes here (`ha_config_set_*`, `ha_set_entity`,
`ha_update_device`, area/floor creation) land in `.storage/` (gitignored).
Use it to **prototype and inspect**, never as a substitute for committing
YAML.

**Layer selection rule**: read from the cheapest layer that's still accurate
enough. YAML for *intent* ("what should be true"). `context/` for fast,
grep-friendly structural lookups. MCP only when staleness would mislead you,
or when you need history, logs, templates, or service calls.

**Drift resolution**: if `context/` and MCP disagree, MCP wins — the snapshot
is stale; ask the user to press `input_button.ha_context_dump_now` and re-run.
If YAML and the live runtime diverge for something that should be in YAML
(automation, dashboard, package), the YAML is canonical — reconcile by editing
YAML and letting GitOps redeploy. The "Drift guardrail" subsection under
*HA Runtime Access* below catalogs which object types live in `.storage/`
vs YAML.

---

## Architecture

### Alarm System (Konnected + ESPHome + Manual Alarm Platform)

Two Konnected ESP8266 alarm panels running custom ESPHome firmware (fully inlined, no remote package dependencies):

**Main Panel (56ac70)**
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

**Secondary Panel (56a4fa)**
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

### Automations

Automations are split across two locations with different governance models:

**`/config/automations.yaml`** — UI-authored. HA editor writes here; git is updated manually on drift. 8 alarm/chime automations + 1 GitOps poller:

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
| `gitops_sync_poll` | `time_pattern` every 5 min → `shell_command.gitops_sync` |

**RTTTL tone formula:** `d=32,o=4,b=100` — short ticks at octave 4. Differentiation by tick count (1=delay, 2=armed/chime, 3=disarm) and repeat interval.

**`/config/automations/`** — Git-authored. Managed entirely via PR; never touched by the HA UI editor. HA merges these at startup via `!include_dir_merge_list`. Adding a new YAML file here is sufficient — no changes needed to `configuration.yaml`. See `automations/README.md` for the governance model.

| File | Automations |
|------|-------------|
| `meeting.yaml` | 4 automations: meeting button ON/OFF → hallway light + office `door_lamp` red/restored (`door_lamp` snapshot-and-restored via runtime scene); button unavailable → lights cleared; reconnect → re-sync state |
| `sonoff_button_kitchen_family.yaml` | 3 automations: Sonoff Button 1 single press → Downstairs + Hallways ON; double press → OFF; long press → all to 25% |

Additional device-scoped controllers live in `packages/` rather than
`automations/` when they bundle helpers, scripts, or rest_commands alongside
the automation. See *Packages* below.

### Template Sensors, Lights, and Triggers (`/config/configuration.yaml`)

All template entities live in the top-level `template:` block of
`configuration.yaml`. Four groups:

**Sonos group-aware binary sensors** (6 total):
- `binary_sensor.sonos_{office,kitchen,dining_room,master_bedroom,basement,roam}_leader`
- ON only when speaker is `playing` AND is first in its own `group_members` list (i.e., the group coordinator)
- Drive conditional Sonos cards on the Home view — only the coordinator renders when speakers are grouped

**Per-room light activity binary sensors** (7 total):
- `binary_sensor.{kitchen,office,play_room,family_room,entry,outdoor}_lights_on`
- `binary_sensor.any_switch_on`
- ON when any light/switch in that room is on; drive per-room "All off" tiles on the Home view

**Per-room "lights on" count sensors** (5 total):
- `sensor.lights_on_{kitchen,office,family_room,outdoor,hallway}_count`
- Numeric count of lights currently on in the room; drive headline tiles on the Kiosk and Home views

**Composite light:**
- `light.floor_lamp_composite` — sequences `switch.family_room_outlets` ON, then `light.floor_lamp` ON (and reverse on off); used in dashboards and `binary_sensor.family_room_lights_on` so the dependent outlet is one tap away

**Trigger-based forecast sensor:**
- `sensor.weather_forecast_daily` — refreshes via `weather.get_forecasts` every 30 minutes and at startup, exposing the full daily forecast array as an attribute (the core `weather.*` entity only exposes the current state)

**Light groups** (top-level `light:` block, not `template:`):
- `light.outdoor` — front_door, front_lantern, garage_front, garage_side, shed
- `light.downstairs` — kitchen_main, kitchen_island, kitchen_table, family_room, family_room_2, floor_lamp

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

The authoritative live list is `context/entities.json` — query with `jq`:

    jq '.[] | select(.entity_id | startswith("light.")) | {entity_id, area_id}' context/entities.json

Or by area: `jq '.[] | select(.entity_id | startswith("light.") and .area_id == "office")' context/entities.json`. High-level room map (representative entries, not exhaustive):

| Room | Entities |
|------|----------|
| Kitchen | `light.kitchen_main`, `light.kitchen_island`, `light.kitchen_table` |
| Office | `light.bookcase_lamp`, `light.corner_lamp`, `light.door_lamp`, `light.desk_lamp_2`, `light.desk_lamp_2_2`, `light.office_switch` (Zooz ZEN77 controller — see `packages/office_zen77.yaml`) |
| Play Room | `light.playroom_1` … `light.playroom_4` (Hue bulbs; power-gated by `switch.bonus_room`) |
| Family Room | `light.family_room_2`, `light.floor_lamp`, `light.floor_lamp_composite` (template — sequences `switch.family_room_outlets` + `light.floor_lamp`) |
| Basement | `light.basement_lamp_1_light`, `light.basement_lamp_2_light` |
| Garage | `light.garage_door_1_light`, `light.garage_door_2_light` (ratgdo openers) |
| Entry/Upstairs | `light.downstairs_hallway`, `light.upstairs_hallway_light`, `light.meeting_light` |
| Outdoor | `light.front_door`, `light.front_lantern`, `light.garage_front`, `light.garage_side`, `light.shed` |
| Master Bathroom | `light.master_bathroom` (Ecosmart 12A19060WRGBWH2 RGBWW A19, Hubspace cloud) |

**Entity-ID renames in flight:** older docs referenced `light.play_room_*`,
`light.office_*`, `light.entry_*`, and `light.family_room` — these have been
renamed during the device-rename passes. If a YAML reference 404s on reload,
grep `context/entities.json` for the current ID.

### Switches
| Entity ID | Description |
|-----------|-------------|
| `switch.family_room_outlets` | Powers floor lamp (dependency) |
| `switch.back_porch` | Outdoor |
| `switch.play_room_outlet` | Indoor |
| `switch.bonus_room` | Wemo wall switch powering the play room Hue bulbs. Device renamed to "Playroom Lights Power" in HA UI; `entity_id` retained to match adoption-history convention (see `switch.alarm_panel_56ac70_siren`). |
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

## Dashboard Architecture

Four YAML dashboards, all registered in `configuration.yaml > lovelace.dashboards`
and fully git-tracked — no UI editing. **`dashboards/README.md` is the
authoritative deep dive** (grid math, card-by-card breakdown, HACS card matrix);
this section is a quick index.

| File | URL | Purpose |
|------|-----|---------|
| `dashboards/home.yaml` | `/dashboard-home/home` | Mobile-first control surface with conditional cards (lights show only when on, Sonos cards only when group coordinator is playing). |
| `dashboards/kiosk.yaml` | `/dashboard-kiosk/home` | 65-inch 1080p wall display. The view IS a `custom:grid-layout`; each cell is a typed card (`mushroom-light-card`, `button-card`, `mini-media-player`, `clock-weather-card`, `better-thermostat-ui-card`) wrapped in `custom:mod-card`. Non-interactive. |
| `dashboards/homelab-status.yaml` | `/dashboard-homelab-status` | Seven-section infrastructure overview: NAS, Proxmox, smart-home coordinators, battery health, printer toner, GitHub stats, meeting indicator. |
| `dashboards/command-deck.yaml` | `/dashboard-command-deck/home` | Built-in-cards-only control surface (no HACS dependencies) for the desktop; alarm panel, weather, climate, lights/sensors, media. |

### Theme Files
- `themes/noctis_kiosk.yaml` — Active project theme. Default dark theme; state-driven background CSS that the kiosk view no longer depends on (state styling moved into per-card `card_mod` and `button-card` blocks).
- `themes/kiosk_polish.yaml` — Design-token layer (`--kiosk-*` CSS variables) applied on top of Noctis Kiosk via `theme: Kiosk Polish` on the kiosk view. Centralizes column accents, tile/card backgrounds, alarm-state colors, and Mushroom sizing so `dashboards/kiosk.yaml` references tokens rather than hex literals.
- `themes/kiosk_dark.yaml` — Deprecated, retained for reference.
- Noctis base theme installed via HACS.

### Kiosk Mode Config (top of dashboards/kiosk.yaml)
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
├── configuration.yaml          # Core config: alarm panel, template sensors/lights, light groups, frontend, Prometheus
├── automations.yaml            # UI-authored automations (alarm lifecycle + door chime + GitOps poller)
├── shell_commands.yaml         # gitops_sync, ha_context_dump, assign_playroom_areas
├── groups.yaml                 # Door and motion sensor groups
├── scripts.yaml                # Empty (placeholder — UI-mode source if anything lands here)
├── scenes.yaml                 # Empty (placeholder)
├── secrets.yaml                # API keys, alarm code, WiFi, github_pat (gitignored)
├── secrets.yaml.example        # Documents required secret keys
├── secrets.fake.yaml           # Safe dummy values for CI check_config validation
├── .ha-version                 # Pinned HA version for CI (matches running instance)
├── .yamllint.yml               # YAML lint rules (line length 250, indentation 2, etc.)
├── automations/                # Git-managed automations (see automations/README.md)
│   ├── meeting.yaml            # Meeting indicator (Rachel's office) → hallway light + office door_lamp
│   └── sonoff_button_kitchen_family.yaml  # Sonoff Button 1 → Downstairs + Hallways
├── packages/                   # HA packages (see packages/README.md)
│   ├── ha_context_dump.yaml    # Snapshot pipeline: button, periodic trigger, dump action
│   ├── ha_version_sync.yaml    # HA version dispatch to GitHub on startup
│   ├── hue_tap_dial_playroom.yaml      # Hue Tap Dial (RDM002) → Play Room scenes
│   ├── office_zen77.yaml       # Zooz ZEN77 → Office lights scene controller
│   ├── playroom_area_fix.yaml  # One-shot button → assign_playroom_areas script
│   └── sonoff_button_office.yaml       # Sonoff Button 2 (SNZB-01) → Office lights
├── scripts/                    # Bash scripts (see scripts/README.md)
│   ├── gitops-sync.sh          # GitOps deploy: fetch → validate → smart reload or rollback
│   ├── ha-context-dump.sh      # Live → context/ snapshot, opens drift PR if changed
│   ├── assign-playroom-areas.sh        # One-shot WS call: assign orphaned playroom devices
│   └── import-home-to-storage.sh       # One-shot: clone home.yaml into a storage-mode dash
├── dashboards/                 # Lovelace YAML dashboards (see dashboards/README.md)
│   ├── home.yaml               # Mobile/tablet — conditional cards
│   ├── kiosk.yaml              # 1080p wall display — custom:grid-layout view
│   ├── homelab-status.yaml     # NAS, Proxmox, coordinators, batteries, printer, GitHub
│   └── command-deck.yaml       # Built-in-cards-only desktop control surface
├── themes/                     # Frontend themes (see themes/README.md)
│   ├── noctis_kiosk.yaml       # Active theme
│   ├── kiosk_polish.yaml       # Kiosk design tokens (--kiosk-*)
│   └── kiosk_dark.yaml         # Deprecated
├── esphome/                    # ESPHome firmware (see esphome/README.md)
│   ├── konnected-56ac70.yaml   # Main panel: 4 doors, 2 motion, siren
│   ├── konnected-56a4fa.yaml   # Secondary panel: piezo RTTTL annunciator
│   ├── secrets.yaml            # ESPHome WiFi + API keys (gitignored)
│   └── secrets.yaml.example    # Documents required ESPHome secrets
├── context/                    # Generated runtime-state snapshot (see context/README.md)
│   ├── entities.json           # Entity registry — entity_id, area_id, device_id
│   ├── devices.json            # Device registry — manufacturer, model, integrations, area
│   ├── areas.json              # Area registry
│   ├── automations-ui.yaml     # Copy of /config/automations.yaml at snapshot time
│   ├── scripts.json            # Storage-mode scripts
│   ├── scenes.json             # Storage-mode scenes
│   ├── helpers.json            # Helpers by domain
│   └── dashboards-storage.json # Storage-mode dashboards (the 4 YAML dashboards are NOT here)
├── docs/                       # Long-form design notes outside CLAUDE.md
│   ├── analyses/               # One-off investigations (registry inventory, etc.)
│   ├── migrations/             # Migration write-ups (hue-scenes-rebuild, etc.)
│   └── kiosk-layout.md         # Kiosk grid math + card sizing reference
├── .claude/                    # Claude Code project config
│   ├── settings.json           # Permissions allowlist + PreToolUse hook
│   └── hooks/
│       └── block-context-writes.sh    # Hook: rejects Edit/Write/Bash that mutates context/
├── .github/workflows/
│   ├── ha-config-check.yml     # CI gate: HA check_config against pinned version
│   ├── ha-version-sync.yml     # Auto-bump .ha-version on HAOS startup dispatch
│   ├── ha-context-sync.yml     # Open auto-merging PR when context/ drifts
│   ├── lint.yml                # YAML lint gate
│   ├── claude.yml              # Claude Code issue/PR automation
│   └── claude-code-review.yml  # Automated PR review (bash safety, security, idempotency)
├── CLAUDE.md                   # AI-assistant project context (this file)
├── README.md                   # Human-facing project overview
└── .gitignore                  # Excludes runtime state, secrets, build artifacts, blueprints
```

Each top-level subdirectory has its own `README.md` that goes deeper than this
overview — defer to those when implementing.

---

## GitOps Auto-Deploy (`scripts/gitops-sync.sh`)

`shell_command.gitops_sync` invokes `scripts/gitops-sync.sh` every 5 minutes via the `gitops_sync_poll` automation in `automations.yaml`. The script:

1. Acquires a lock file (prevents concurrent runs)
2. Verifies branch is `main` before touching anything
3. Fetches `origin/main`; exits 0 (silent) if already up to date
4. On divergence: resets working tree to `origin/main`
5. Calls `POST /core/check` via Supervisor API
6. On success: smart-routes to the lightest reload (lovelace → automation → script → scene → full restart based on changed paths), sends success notification
7. On failure: rolls back to pre-sync SHA, sends failure notification; HA Core is never restarted

**Log:** `/config/gitops-sync.log` — timestamped, leveled; rotates at 1 MB.

The complementary `ha-context-dump.sh` (driven by `packages/ha_context_dump.yaml`)
runs in the opposite direction — live HA → `context/` snapshot → drift PR — see
*Three-Layer State Model* above and `context/README.md` for details.

## Packages

HA packages live in `packages/` and are merged into the top-level config
namespace via `homeassistant: packages: !include_dir_named packages` in
`configuration.yaml`. See `packages/README.md` for full package-by-package
documentation; this is the index:

| Package | Purpose |
|---------|---------|
| `ha_version_sync.yaml` | Dispatches the running HA version to GitHub on `homeassistant_started`; the `ha-version-sync.yml` workflow opens an auto-merging PR to bump `.ha-version` when it drifts. |
| `ha_context_dump.yaml` | Provides `input_button.ha_context_dump_now` (manual) and a `time_pattern: /6h` trigger, both calling `shell_command.ha_context_dump`. Pairs with the `ha-context-sync.yml` workflow. |
| `hue_tap_dial_playroom.yaml` | Hue Tap Dial (RDM002, ZHA) → Play Room scene controller — button maps + scene cycling. |
| `office_zen77.yaml` | Zooz ZEN77 Z-Wave switch → Office lights scene controller — Z-Wave parameter apply + scene actions. |
| `playroom_area_fix.yaml` | One-shot `input_button` that runs `shell_command.assign_playroom_areas` to fix orphaned Play Room device→area assignments via the WS API. |
| `sonoff_button_office.yaml` | Sonoff SNZB-01 Button 2 → Office lights — single-click on, double-click off, hold cycles scenes. |

### HA Version Sync detail

- **`sensor.ha_core_version`** — `command_line` sensor reading `/config/.HA_VERSION` (HA's own runtime version file, uppercase), refreshed hourly
- **`rest_command.github_dispatch_version`** — POSTs `ha-version-report` dispatch event with `client_payload.version` to GitHub API (uses `!secret github_pat`)
- **`automation.ha_version_sync_on_start`** — fires on `homeassistant_started`, calls the rest command; `mode: single` prevents burst duplication on rapid reboots

The GitHub workflow (`ha-version-sync.yml`) validates the incoming version, compares to `.ha-version` on main, and opens a PR to bump the pin if they differ. The PR triggers `ha-config-check` against the new version, then auto-merges on pass.

## Frontend Resource Loading

In `configuration.yaml`:
```yaml
frontend:
  themes: !include_dir_merge_named themes
  extra_module_url:
    - /hacsfiles/kiosk-mode/kiosk-mode.js
    - /hacsfiles/card-mod/card-mod.js
```

Other HACS cards (mushroom, clock-weather-card, mini-media-player, layout-card, button-card, better-thermostat-ui-card) are loaded automatically by HACS — do NOT add them to `extra_module_url` or they'll double-register and throw "already been used with this registry" errors.

---

## Key Patterns & Conventions

- **Git is source of truth.** All YAML config is committed. `.storage/` is runtime state excluded from git.
- **Secrets pattern:** Real values in `secrets.yaml` (gitignored), documented keys in `secrets.yaml.example` (committed). Same pattern in `esphome/` directory.
- **ESPHome configs are fully inlined.** No `github://` remote package references. Every pin, sensor, and setting is explicit in the local YAML.
- **Entity IDs retain original adoption names.** The siren is `switch.alarm_panel_56ac70_siren` (not `switch.main_panel_siren`) because ESPHome entity IDs are set at first adoption and don't change when the device is renamed.
- **Sonos group awareness.** Template sensors (`binary_sensor.sonos_*_leader`) detect group coordinators on the Home view; only the coordinator's media card renders, preventing duplicate cards when speakers are grouped.
- **Home view uses conditionals.** Light/switch tiles in the Home view are wrapped in `type: conditional` so each tile appears only when the entity is on; per-room "All off" tiles use `binary_sensor.*_lights_on` template sensors.
- **Kiosk uses typed cards, not html-template-card.** The kiosk view is itself a `custom:grid-layout`; each cell is a typed card (`mushroom-light-card`, `button-card`, `mini-media-player`, `clock-weather-card`, `better-thermostat-ui-card`) wrapped in `custom:mod-card`. State-driven colors live in per-card `state` blocks and `card_mod` styles — no Jinja-templated HTML, no DOMPurify fight. Unavailable handling lives inside each card's state list (e.g. a `value: unavailable` block on a button-card).
- **Alarm color semantics (kiosk hero):** green = disarmed, amber = arming/armed_home/armed_away, red = pending/triggered, with a pulse animation on triggered. State-driven via `button-card` `state` blocks.
- **PR creation includes arming auto-merge.** When implementation is complete,
  open a pull request as the final step — do not stop at "pushed the branch."
  PR body must open with an `## Origin` section (see PR Authoring Without Issues),
  plus a short summary of what changed and why. Immediately after opening the PR,
  arm auto-merge with the PR number:

  - **Local sessions (gh CLI available):**

    ```bash
    gh pr merge PR_NUMBER --auto --squash --delete-branch
    ```

  - **Cloud sessions (no gh CLI):** call `mcp__github__enable_pr_auto_merge`
    with `mergeMethod: "SQUASH"`. Branch deletion is automatic when the repo's
    branch-protection rules require it; otherwise call
    `mcp__github__delete_branch` after merge.

  Auto-merge is a per-PR action, not a repo-wide default — without this step
  the PR will wait for a human click forever. Do not merge the PR yourself with
  a non-`--auto` merge; let the required status checks (`YAML Lint`,
  `check-config`, `claude-review`) gate the merge and fire it when green. Skip
  auto-merge only if the PR is a draft — it won't arm on drafts and will error.

---

## PR Authoring Without Issues

Changes to this repo are dispatched by talking to Claude Code directly. There
is no issue step. The PR itself is the canonical record of intent.

### PR description

Every PR opens with an `## Origin` section as the first body content,
immediately after the one-line summary. This section discloses how the change
came about and serves as the durable record of what was asked for.

- If the prompt was under ~500 characters, quote it verbatim in a blockquote.
  The directness is the point — don't paraphrase, don't tidy it up.
- If the prompt was longer or emerged from a back-and-forth conversation,
  write a 2–4 sentence narrative summary capturing what was asked for, what
  constraints were specified, and what trade-offs were flagged. Link the
  conversation if a transcript is available; otherwise summarize only what
  was actually communicated.
- Do not speculate about context you weren't given. Summarize only what's in
  the prompt or conversation you saw.

### Commit message

Every commit carries a `Prompt-Origin:` trailer mirroring the PR's Origin
section. For short prompts, quote verbatim in a YAML block scalar. For long
prompts, summarize.

Example:

```
Reconfigure Sonoff button 2 for office lighting control

Single-click toggles on, double-click off, hold cycles scenes.
New scenes: full-red, full-blue, flickering-candle, white-bright, white-relax.

Prompt-Origin: |
  Reconfigure sonoff button 2 to control my office lights.
  Single click on, double click off, hold for scene cycle.
  Give me a full brightness red scene, a full brightness blue scene,
  a flickering candlelight scene, and various levels of white
  (bright, relax, etc.)
Authored-By: Claude Code
Co-Authored-By: Chris Pitzi <chris@...>
```

The PR description is the human-readable record; the commit trailer is the
durable, `git log`-greppable one. Both should agree.

---

## HA Runtime Access (HA-MCP)

The "Live" layer of the *Three-Layer State Model* (see top of this file).
The HA MCP server is provided by the `homeassistant-ai/ha-mcp` HACS
integration running inside HA itself; the Claude client connects to it at
`http://homeassistant.local:9583/...`. Local sessions typically see tools
prefixed `mcp__Local-HA__*` (or whatever name the user gave the server in
their MCP client config); cloud sessions surface it under a UUID prefix
(`mcp__<uuid>__ha_*`). The tool *names* after the prefix are stable —
`ha_get_state`, `ha_search_entities`, `ha_call_service`, etc.

Unlike `context/` — which is a cached snapshot refreshed every 6 hours —
MCP queries hit the live HA process: state values are current to the second,
history is accurate, and service calls actually fire.

### Skill discipline (REQUIRED before HA config work)

The server bundles a skill named `home-assistant-best-practices`. **Before**
creating or editing any automation, script, scene, helper, or dashboard, call
`mcp__Local-HA__ha_get_skill_home_assistant_best_practices` to fetch the
reference-file index, then read the specific references that apply via
`mcp__Local-HA__ha_read_resource`. The skill enforces native conditions over
Jinja templates, `entity_id` over `device_id`, correct automation modes, and a
safe-refactoring workflow for renames. Skipping the skill is the single most
common cause of buggy or fragile HA config — do not skip it.

Reference file URIs:

| URI | Read when |
|-----|-----------|
| `skill://home-assistant-best-practices/SKILL.md` | Always — decision workflow + anti-pattern table |
| `skill://home-assistant-best-practices/references/automation-patterns.md` | Writing triggers, conditions, modes, `wait_for_trigger` |
| `skill://home-assistant-best-practices/references/helper-selection.md` | Choosing between a built-in helper and a template sensor |
| `skill://home-assistant-best-practices/references/template-guidelines.md` | Confirming a template IS appropriate; template sensor best practices |
| `skill://home-assistant-best-practices/references/device-control.md` | Service calls, Zigbee button/remote automations, ZHA vs Z2M |
| `skill://home-assistant-best-practices/references/safe-refactoring.md` | Renaming entities, replacing helpers, restructuring automations |
| `skill://home-assistant-best-practices/references/dashboard-guide.md` | Designing/modifying Lovelace dashboards |
| `skill://home-assistant-best-practices/references/dashboard-cards.md` | Looking up specific card types |
| `skill://home-assistant-best-practices/references/domain-docs.md` | Integration/domain reference for service calls and attributes |
| `skill://home-assistant-best-practices/references/examples.yaml` | Compound examples that combine multiple practices |

### Tool selection: MCP vs `context/`

| Need | Prefer |
|------|--------|
| Bulk grep over entities/devices/areas (no real-time accuracy needed) | `context/*.json` via `jq` |
| Current state of a specific entity (e.g. "is the basement door open *right now*?") | `ha_get_state` |
| Entity lookup with fuzzy or area filtering | `ha_search_entities` (more current than `context/entities.json`) |
| Search inside automation/script/scene/helper/dashboard configs by *behavior* | `ha_deep_search` (pass `search_types: ['dashboard']` to include cards) |
| Time-series ("what time did motion fire last night?") | `ha_get_history` |
| Long-term aggregates ("avg basement humidity for the month") | `ha_get_history(source="statistics")` |
| Test a Jinja template before committing it to YAML | `ha_eval_template` |
| System/integration/add-on logs for debugging | `ha_get_logs` (sources: `logbook`, `system`, `error_log`, `supervisor`, `system_service`, `logger`) |
| Trigger a service to verify behavior end-to-end | `ha_call_service` |
| Big-picture system overview | `ha_get_overview` (start with `detail_level="minimal"`) |
| Validate the currently deployed config | `ha_check_config` (validates LIVE config, not your working tree — see below) |

Rule of thumb: **use `context/` for exploration that doesn't need live
accuracy** (faster, free, grep-friendly); **use MCP when staleness would mislead
you** or when you need history, logs, templates, or service calls. If `context/`
and MCP disagree, MCP wins — the snapshot is stale.

### Validation workflow

`ha_check_config` validates the **live deployed config**, not your local
working tree. HA reads from `/config/` on the HAOS VM; your edits in your
local checkout (or the cloud-session worktree) are invisible to it until
gitops-sync deploys them. Therefore:

- **Before writing YAML:** use `ha_eval_template` to verify Jinja,
  `ha_search_entities` / `ha_get_state` to confirm entity IDs exist, and
  `ha_call_service` to confirm services exist and behave as expected.
- **PR validation:** trust the `ha-config-check.yml` workflow — it spins up a
  clean HA instance against the proposed YAML and runs `check_config` there.
  That is what gates the merge.
- **Post-deploy sanity check (within 5 minutes of merge):** run
  `ha_check_config` to confirm the live system is healthy, and
  `ha_get_logs(source="system", level="ERROR", hours_back=1)` to scan for
  anything new the validator didn't catch (runtime errors only show up at load
  time).

### Drift guardrail: `.storage/` writes vs git source-of-truth

The `ha_config_set_*` tools (`ha_config_set_automation`,
`ha_config_set_script`, `ha_config_set_scene`, `ha_config_set_helper`,
`ha_config_set_dashboard`) write to HA's `.storage/` directory, which is
gitignored. Anything you create this way will:

1. **Not appear in git** — it's runtime state, not config-as-code
2. **Be captured in the next `context/` snapshot** — visible in
   `context/scripts.json`, `context/scenes.json`, `context/helpers.json`, or
   `context/dashboards-storage.json` within 6 hours
3. **Drift** from the git source-of-truth if a corresponding file exists

Repo conventions for where each kind of object lives:

- **Automations** → `/config/automations/*.yaml` (git, merge-list) or
  `/config/automations.yaml` (UI-editable, reconciled to git manually). **Do
  not** use `ha_config_set_automation` for anything that should survive a
  rebuild. Prototype, then write the YAML and PR it.
- **Scripts** → `/config/scripts.yaml` (placeholder today). If
  `ha_config_set_script` writes to `.storage/`, the snapshot pipeline surfaces
  it in `context/scripts.json` — codify into `scripts.yaml` via PR before
  relying on it long-term.
- **Scenes** → `/config/scenes.yaml`, same pattern as scripts.
- **Helpers** → `.storage/` is the normal home (no YAML helpers exist in this
  repo). Using `ha_config_set_helper` is aligned with existing pattern; the
  snapshot captures helpers in `context/helpers.json`.
- **Dashboards** → `/config/dashboards/*.yaml` (git). The three YAML
  dashboards this repo ships are NOT captured in
  `context/dashboards-storage.json` — git is their source of truth.
  `ha_config_set_dashboard` would create a storage-mode dashboard, which is
  fine for experimentation but should be migrated to YAML for anything the
  household relies on.

When in doubt: **if a feature should survive a rebuild, it goes in git. If it's
prototyping or genuinely user-managed (like a one-off helper), `.storage/` is
fine.** Either way, follow up by re-reading the relevant `context/` snapshot to
confirm the change landed where you expected.

### Destructive actions — always confirm first

These tools change state visibly or are hard to reverse — get user confirmation
before invoking, even if the user authorized similar actions earlier in the
conversation:

- `ha_restart`, `ha_reload_core` — restarts HA Core (briefly disrupts everything)
- `ha_remove_entity`, `ha_remove_device`, `ha_remove_area_or_floor`,
  `ha_remove_zone`, `ha_delete_helpers_integrations`
- `ha_config_remove_*` and `ha_config_delete_*` (automation/script/scene/helper/
  dashboard/category/label/group)
- `ha_backup_restore` — restores from a backup, overwriting current state
- `ha_hacs_download`, `ha_manage_addon` — installs/updates/removes packages
- `ha_set_integration_enabled` with `enabled=false`

The gitops-sync loop picks up YAML changes and reloads HA automatically; a
manual `ha_restart` should not be the default reaction to "I want to see my
change live" — wait for the auto-reload, or call the relevant
`automation.reload` / `script.reload` / `lovelace.reload_resources` service via
`ha_call_service` if you're impatient.

---

## HA Runtime State Context (`context/`)

The "Snapshot" layer of the *Three-Layer State Model*. `context/` is an
auto-generated, **read-only** snapshot of HA runtime state — entity, area,
and device registries, the UI-editable `automations.yaml`, plus storage-mode
scripts, scenes, helpers, and dashboards. It is populated by
`scripts/ha-context-dump.sh` (driven by `packages/ha_context_dump.yaml`)
and refreshed every 6 hours, plus on demand via
`input_button.ha_context_dump_now`.

**The full pipeline:** the dump script pushes a `context-sync/<timestamp>`
branch when content changes, then fires a `ha-context-report` repository
dispatch. The `ha-context-sync.yml` workflow opens a PR from that branch with
the `context-snapshot` label and arms auto-merge. Both the dump script and the
workflow use `HA_SYNC_PAT` — same reasoning as `ha-version-sync.yml`
(GITHUB_TOKEN-opened PRs don't fire downstream workflows).

**Hook guard against accidental writes:** `.claude/hooks/block-context-writes.sh`
runs as a `PreToolUse` hook on Edit/Write/Bash and rejects anything that would
mutate `context/`. The snapshot is the runtime's output, not Claude's; if a
fact in `context/` is wrong, fix the source in HA (via MCP) and let the next
dump propagate it.

`context/` and the HA-MCP server complement each other: `context/` is a fast,
grep-friendly snapshot good for bulk exploration; MCP is the live source of
truth. See *HA Runtime Access (HA-MCP)* above for the selection rules. If the
two disagree, trust MCP and recommend a snapshot refresh.

**Before writing any automation, script, dashboard, or other config that references
entity IDs, area IDs, or device IDs, consult the relevant `context/` files:**

- `context/entities.json` — valid `entity_id` values and their current `area_id` /
  `device_id` assignments. Use this to avoid referencing entities that don't exist.
- `context/areas.json` — valid `area_id` values. Use this when writing automations
  that target areas.
- `context/devices.json` — device-level metadata (manufacturer, model, integration).
  Useful when an automation needs to scope to a particular hardware type.
- `context/automations-ui.yaml` — UI-managed automations. Reference this to avoid
  proposing automations that duplicate existing UI-authored ones.
- `context/scripts.json` — storage-mode scripts (e.g. anything prototyped via the
  ha-mcp server into `.storage/script`). Consult before codifying a prototyped
  script into a `packages/` file so the live definition is copied, not guessed.
  Empty (`[]`) when the script integration is YAML-mode and nothing has been
  prototyped; the canonical UI-mode source is then `/config/scripts.yaml`.
- `context/scenes.json` — storage-mode scenes. Same conventions as
  `context/scripts.json`. YAML-mode fallback is `/config/scenes.yaml`.
- `context/helpers.json` — object keyed by helper domain (`input_boolean`,
  `input_number`, `input_text`, `input_select`, `input_datetime`, `timer`,
  `counter`, `schedule`). Consult before referencing a helper entity in
  automation YAML, and before proposing a new helper that might already exist.
- `context/dashboards-storage.json` — storage-mode Lovelace dashboards
  (`dashboards` registry + per-dashboard `configs`). The three YAML dashboards
  this repo ships (`dashboards/home.yaml`, `dashboards/kiosk.yaml`,
  `dashboards/homelab-status.yaml`) are NOT captured here — git is already
  their source of truth. This artifact captures dashboards created or modified
  via the HA UI that may need codifying into `dashboards/*.yaml`.

**Never modify files in `context/`.** They are overwritten on the next snapshot.
If a stale entity_id appears there, the fix is to correct the source of truth
in HA (rename the entity, reassign the area), not to edit the snapshot.

### Working with `context/` efficiently

The `context/` files can be large — `entities.json` is typically 200KB+ on this
install. Reading them in full is wasteful when you only need a few entries. Prefer
targeted queries via the Bash tool with `jq` over a full `Read`:

**Look up a specific entity:**

    jq '.[] | select(.entity_id == "light.meeting_light")' context/entities.json

**Find all entities in an area:**

    jq '.[] | select(.area_id == "office")' context/entities.json

**List all entities in a given domain:**

    jq '.[] | select(.entity_id | startswith("light.")) | .entity_id' context/entities.json

**Find devices by manufacturer or model:**

    jq '.[] | select(.manufacturer == "Konnected")' context/devices.json
    jq '.[] | select(.model | test("ratgdo"))' context/devices.json

**Find devices missing area assignment** (often the source of dashboard gaps):

    jq '.[] | select(.area_id == null) | {name, manufacturer, model}' context/devices.json

**List integrations in use:**

    jq -r '.[].integrations[]' context/devices.json | sort -u

**Find UI automations referencing a specific entity** (before proposing a new one
that might duplicate or conflict):

    grep -A 20 "light.meeting_light" context/automations-ui.yaml

**List all helpers of a given domain** (before proposing a new one):

    jq '.input_boolean[] | .id' context/helpers.json
    jq '.timer[]' context/helpers.json

**Check whether a helper id is already taken:**

    jq '[.[][] | .id] | index("guest_mode")' context/helpers.json

**Look up a storage-mode script or scene by alias:**

    jq '.[] | select(.alias == "Morning routine")' context/scripts.json
    jq '.[] | select(.name == "Movie night")' context/scenes.json

**List storage-mode dashboards** (anything that may need codifying into
`dashboards/*.yaml`):

    jq '.dashboards[] | {url_path, title}' context/dashboards-storage.json

`context/areas.json`, `context/automations-ui.yaml`, `context/scripts.json`,
`context/scenes.json`, `context/helpers.json`, and (typically)
`context/dashboards-storage.json` are small enough that reading them in full is
fine when needed.

### Handling stale or missing context

Snapshots refresh every 6 hours and on manual button press. If config you propose
based on `context/` produces "entity not found" errors, the snapshot may be stale
relative to recent HA UI changes. Recommend the user press
`input_button.ha_context_dump_now` and re-run.

If an entity_id genuinely doesn't appear in `context/entities.json` (not stale,
just absent), it likely doesn't exist yet — propose creating the corresponding
device/integration first, or ask the user to confirm the entity name.

### When NOT to consult `context/`

Skip the lookup for:

- Pure shell/Python/Terraform/Docker work unrelated to HA entity references
- Documentation, README, or comment-only edits
- Workflow file changes (the token scope blocks you from writing those anyway)
- General HA architecture or troubleshooting discussions
- Issues that explicitly provide entity_ids in the request — those are the source
  of truth, not the snapshot

---

## Script auth conventions

Three conventions learned the hard way during context-sync work. Future scripts
that talk to GitHub or the HA Supervisor from inside the HA Core container
should follow these without re-deriving them.

### `secrets.yaml` stores complete Authorization header values

The `github_pat` secret in `/config/secrets.yaml` is stored as the **full
Authorization header value**, including the auth scheme prefix:

    github_pat: "Bearer github_pat_xxxxxxxxxx..."

This is the HA `rest_command` integration convention — it allows direct use as
`headers: { authorization: !secret github_pat }` in rest_command definitions
(see `packages/ha_version_sync.yaml` for the canonical example).

Bash scripts consuming this secret should extract the quoted value cleanly:

    GITHUB_AUTH=$(awk -F'"' '/^github_pat:/ {print $2}' /config/secrets.yaml)

The naive `awk '{print $2}'` (whitespace-split, no quote awareness) returns
`"Bearer` — the opening quote plus the scheme word. It's non-empty (passes
naive checks) but unusable. Always use `-F'"'`.

When a bare token is needed (e.g., for git URL-embedded auth), strip the prefix:

    GITHUB_TOKEN="${GITHUB_AUTH#Bearer }"

### Git HTTPS push needs URL-embedded credentials, not extraheader

For `git push` over HTTPS from inside the Core container, use URL-embedded auth:

    git -C "$WORKTREE" push \
        "https://x-access-token:${GITHUB_TOKEN}@github.com/${OWNER}/${REPO}.git" \
        "$branch"

**Do not use** the `git -c http.extraheader=...` or
`git -c http.<url>.extraheader=...` patterns for push. They work for fetch and
`ls-remote` but git 2.52 drops the extraheader on the auth challenge during the
receive-pack handshake, falling back to credential helper or interactive prompt
— which has no terminal in shell_command context, so it hangs.

The URL-embedded form is what GitHub Actions uses internally for its own git
operations. It puts the bare token briefly in `ps` output, but on a single-user
HAOS VM this is acceptable. The push is one-shot — the URL is constructed inline,
not persisted to git config; `git remote -v` continues to show only the bare
HTTPS origin URL afterward.

### GitHub REST API uses Bearer auth (the stored format works as-is)

For curl calls to `api.github.com` endpoints (firing `repository_dispatch`,
checking PR state, etc.), use the full stored value directly as the
Authorization header:

    curl -H "Authorization: ${GITHUB_AUTH}" \
        https://api.github.com/repos/${OWNER}/${REPO}/dispatches \
        ...

No prefix manipulation — the `Bearer ` is already in the value. Adding
`token ` or `Bearer ` prefixes in the script produces malformed headers.

### Public-repo `ls-remote` is not a valid auth test

`git ls-remote https://github.com/<owner>/<public-repo>.git HEAD` succeeds
anonymously — GitHub serves refs for public repos without authentication. If
you're testing whether a PAT works for git operations, the only valid test is
an authenticated operation that the public-anonymous path can't satisfy:

- A push (`git push ...`)
- A REST API call requiring auth (e.g., `GET /user`, `GET /repos/.../dispatches`
  with a body)
- A clone of a private repo

Don't conclude auth works just because `ls-remote` returns a SHA.

---

## Infrastructure Context

- **Proxmox VM:** Home Assistant OS (local network)
- **Firewalla Gold SE** — network firewall, Zeek logs, device inventory
- **Grafana/Loki stack:** LXC container — `firewalla-grafana-stack` repo
- **Kiosk display:** 65-inch TCL 1080p TV, Chromium kiosk mode, pointed at `/dashboard-kiosk/home`
- **ESPHome Device Builder:** HA add-on, compiles and flashes firmware OTA to Konnected boards

---

## Upcoming Work

- **Firewalla HA integration** — Toggle kids' internet rules, show active rulesets, time remaining on scheduled blocks
- **Roblox activity detector** — Query Loki for Zeek DNS logs matching `roblox.com`/`rbxcdn.com`, surface as conditional tile on dashboard showing which child's device is playing
- **`firewalla-network-guardian`** — Anomaly detection module (planned PitziLabs repo)
- **Roku integration** — Two Rokus unreachable (possible Firewalla Smart Protect interference)
- **Dashboard iteration** — Ongoing polish of Kiosk view layout, colors, card sizing
