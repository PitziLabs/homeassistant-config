# CLAUDE.md — Home Assistant Configuration (PitziLabs/homeassistant-config)

## Project Overview

Git-controlled Home Assistant OS deployment running on Proxmox. All configuration is YAML-driven — no UI-based config where avoidable. The HA UI is used only for integration setup (ESPHome device adoption, weather, Sonos, Hue, Kasa, etc.) which HA stores in `.storage/` (excluded from git).

**Config directory:** `/homeassistant/` on the VM, accessible as `/config/` from the SSH add-on.

**Owner:** Chris Pitzi (GitHub: cpitzi, org: PitziLabs)

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

**`/config/automations/`** — Git-authored. Managed entirely via PR; never touched by the HA UI editor. HA merges these at startup via `!include_dir_merge_list`. Adding a new YAML file here is sufficient — no changes needed to `configuration.yaml`.

| File | Automations |
|------|-------------|
| `meeting.yaml` | 4 automations: meeting button ON/OFF → hallway light red/off; button unavailable → light off; reconnect → re-sync state |

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
| Kitchen | `light.kitchen_main`, `light.kitchen_island`, `light.kitchen_table` |
| Office | `light.office`, `light.office_lamp`, `light.office_bookcase`, `light.office_corner`, `light.office_door`, `light.desk_lamp`, `light.desk_lamp_2` |
| Play Room | `light.play_room`, `light.play_room_1`, `light.play_room_2`, `light.play_room_3`, `light.play_room_4` |
| Family Room | `light.family_room`, `light.family_room_2`, `light.floor_lamp` |
| Entry/Upstairs | `light.entry_1`, `light.entry_2`, `light.downstairs_hallway`, `light.upstairs_hallway_light`, `light.meeting_light` |
| Outdoor | `light.front_door`, `light.front_lantern`, `light.garage_front`, `light.garage_side`, `light.shed` |

### Switches
| Entity ID | Description |
|-----------|-------------|
| `switch.family_room_outlets` | Powers floor lamp (dependency) |
| `switch.back_porch` | Outdoor |
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

## Dashboard Architecture

Three YAML dashboards registered in `configuration.yaml`. All are fully git-tracked; no UI editing.

### `dashboards/home.yaml` — Home view

**Home view** (`/dashboard-home/home`) — Mobile/tablet control dashboard
- Masonry layout (standard, not panel mode)
- Room-grouped vertical-stacks with conditional lights (show only when ON)
- Per-room "All off" indicators using template sensors
- Conditional Sonos media cards (playing coordinators only)
- Alarm panel with permanent sensor grid (always visible)
- Activity-driven: lights/switches appear when on, vanish when off

The Home view uses standard HA `tile`, `weather-forecast`, and `media-control` cards plus `mini-media-player` for Sonos.

### `dashboards/kiosk.yaml` — Kiosk view

**Kiosk view** (`/dashboard-kiosk/home`) — 65-inch 1080p wall display
- View type: `custom:grid-layout` (layout-card AS the view, not nested inside a panel)
- Cell wrappers: `custom:mod-card` provides the ha-card host so `height: 100%` cascades through the nested shadow DOM
- Typed cards per panel (no html-template-card):
  - Climate: `custom:better-thermostat-ui-card` with humidity sensor binding
  - Sensors: `custom:button-card` with state-driven backgrounds and pulse animations
  - Lights: `custom:mushroom-light-card` per individual light (20 lights, grouped into 5 room sections inside a vertical-stack)
  - Media: `custom:mini-media-player` with `artwork: full-cover-fit` for album art
  - Weather: `custom:clock-weather-card` (combined clock + 4-day forecast)
  - Alarm: `custom:button-card` hero with state-driven colors and pulse on triggered
  - Meeting: `custom:button-card` driven by `light.meeting_light` — "In Meeting" red+pulse / "Available" green / "Offline" muted
- Non-interactive — every card has `tap_action: { action: none }`
- Kiosk-mode hides sidebar/header for "Kiosk" user
- No camera (handled in a separate cameras dashboard)

### Grid Layout (Kiosk)
```
grid-template-columns: 1fr 1fr 1.4fr 1fr
grid-template-rows: 200px 1fr
grid-template-areas:
  "weather weather alarm   meeting"
  "climate sensors lights  media"
```
- **weather** — clock-weather-card with 4-day forecast (top-left, spans 2 cols)
- **alarm** — button-card hero (top-row, col 3 — 1.4fr)
- **meeting** — button-card driven by `light.meeting_light` (top-row, col 4 — 1fr)
- **climate** — 2 better-thermostat-ui-cards stacked (upstairs + downstairs)
- **sensors** — 8 button-cards in a 2×4 internal grid (4 doors + 2 garage covers + 2 motion)
- **lights** — 20 mushroom-light-cards grouped into 5 room sections (Family Room, Kitchen, Office, Hallways, Outdoor) inside a vertical-stack; each section is a markdown header + 4-col grid. The meeting light is hoisted to the top-right `meeting` cell.
- **media** — 6 mini-media-players in a 2×3 internal grid + TVs row spanning both cols

### HACS Cards Used by Kiosk View
- `layout-card` — provides `custom:grid-layout` (used as the VIEW type, not nested)
- `card-mod` — provides `custom:mod-card` cell wrapper + theme-level CSS
- `button-card` — sensors, alarm hero, heater state, TVs row
- `mushroom` — `mushroom-light-card` for individual lights
- `mini-media-player` — Sonos with album art via `artwork: full-cover-fit`
- `clock-weather-card` — combined clock + forecast in top strip
- `better-thermostat-ui-card` — circular thermostat dial with humidity
- `kiosk-mode` — hides sidebar/header for kiosk user

### Theme Files
- `/config/themes/noctis_kiosk.yaml` — Active theme. Originally provided global state-based backgrounds for Mushroom cards on the kiosk; the kiosk view no longer relies on it (state styling moved into per-card `card_mod` and `button-card` state blocks). Still loaded as the project's default dark theme.
- `/config/themes/kiosk_polish.yaml` — Design-token layer applied on top of Noctis Kiosk via `theme: Kiosk Polish` on the kiosk view. Defines `--kiosk-*` CSS variables for column accents, tile/card backgrounds, text tints, alarm-state colors, and Mushroom sizing — `dashboards/kiosk.yaml` references these tokens instead of inlining hex literals.
- `/config/themes/kiosk_dark.yaml` — Deprecated custom theme (retained for reference).
- Noctis base theme installed via HACS.

### `dashboards/homelab-status.yaml` — Homelab Status

Seven-section infrastructure overview dashboard (sidebar: Homelab Status, icon: `mdi:server-network`):

| Section | Entities surfaced |
|---------|-------------------|
| Neptune NAS (UGREEN DXP2800) | Pool health, disk temps, SMART hours, CPU/RAM/fan, LAN throughput |
| Proxmox (pve) | Node CPU/memory/disk, HAOS + grafana-stack VM status, backup schedule |
| Smart Home Coordinators | ZWA-2, ZBT-2, both Konnected panels — WiFi RSSI, firmware uptime |
| Battery Health | 8-device grid with amber (<40%) / red (<20%) color thresholds |
| Printer (HP M477fdw) | CMYK toner levels with color-coded warnings |
| GitHub (cpitzi/prompts) | Commits, issues, PRs, stars, forks, watchers via REST sensor |
| Meeting Indicator | ESP32 device state, WiFi signal quality, uptime |

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
├── configuration.yaml          # Core config: alarm panel, template sensors, frontend, Prometheus
├── automations.yaml            # UI-authored automations (alarm + door chime + GitOps poller)
├── shell_commands.yaml         # shell_command.gitops_sync → scripts/gitops-sync.sh
├── groups.yaml                 # Door and motion sensor groups
├── scripts.yaml                # Empty (placeholder)
├── scenes.yaml                 # Empty (placeholder)
├── secrets.yaml                # API keys, alarm code, WiFi (gitignored)
├── secrets.yaml.example        # Documents required secret keys
├── secrets.fake.yaml           # Safe dummy values for CI check_config validation
├── .ha-version                 # Pinned HA version for CI (matches running instance)
├── .yamllint.yml               # YAML lint rules (line length 250, indentation 2, etc.)
├── automations/
│   └── meeting.yaml            # Git-managed automations: meeting indicator (Rachel's office)
├── packages/
│   └── ha_version_sync.yaml    # HA version dispatch to GitHub on startup
├── scripts/
│   └── gitops-sync.sh          # GitOps deploy: fetch → validate → reload/restart or rollback
├── dashboards/
│   ├── home.yaml               # Mobile/tablet Home dashboard
│   ├── kiosk.yaml              # 1080p wall-display Kiosk dashboard (custom:grid-layout)
│   └── homelab-status.yaml     # Homelab Status (NAS, Proxmox, coordinators, battery, printer)
├── themes/
│   ├── noctis_kiosk.yaml       # Active theme: global card-mod state-based backgrounds
│   ├── kiosk_polish.yaml       # Kiosk design tokens (--kiosk-*) layered via view-level theme
│   └── kiosk_dark.yaml         # Deprecated custom theme (retained for reference)
├── esphome/
│   ├── konnected-56ac70.yaml   # Main panel firmware: 4 doors, 2 motion, siren
│   ├── konnected-56a4fa.yaml   # Secondary panel firmware: piezo RTTTL annunciator
│   ├── secrets.yaml            # ESPHome WiFi + API keys (gitignored)
│   └── secrets.yaml.example    # Documents required ESPHome secrets
├── .github/workflows/
│   ├── ha-config-check.yml     # CI gate: HA check_config against pinned version
│   ├── ha-version-sync.yml     # Auto-bump .ha-version on HAOS startup dispatch
│   ├── lint.yml                # YAML lint gate
│   ├── claude.yml              # Claude Code issue/PR automation
│   └── claude-code-review.yml  # Automated PR review (bash safety, security, idempotency)
├── CLAUDE.md                   # AI-assistant project context (this file)
└── .gitignore                  # Excludes runtime state, secrets, build artifacts, blueprints
```

---

## GitOps Auto-Deploy (`scripts/gitops-sync.sh`)

`shell_command.gitops_sync` invokes `scripts/gitops-sync.sh` every 5 minutes via a `time_pattern` automation. The script:

1. Acquires a lock file (prevents concurrent runs)
2. Verifies branch is `main` before touching anything
3. Fetches `origin/main`; exits 0 (silent) if already up to date
4. On divergence: resets working tree to `origin/main`
5. Calls `POST /core/check` via Supervisor API
6. On success: smart-routes to the lightest reload (lovelace → automation → script → scene → full restart based on changed paths), sends success notification
7. On failure: rolls back to pre-sync SHA, sends failure notification; HA Core is never restarted

**Log:** `/config/gitops-sync.log` — timestamped, leveled; rotates at 1 MB.

## Packages (`packages/ha_version_sync.yaml`)

HA version tracking and auto-sync on startup. Components:

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
  arm auto-merge with the number returned from `gh pr create` (or
  `gh pr view --json number -q .number`):

```bash
    gh pr merge PR_NUMBER --auto --squash --delete-branch
```

Auto-merge is a per-PR action, not a repo-wide default — without this command
  the PR will wait for a human click forever. Do not merge the PR yourself with
  a non-`--auto` merge; let the required status checks (`YAML Lint`,
  `claude-review`) gate the merge and fire it when green. Skip auto-merge only
  if the PR is a draft — it won't arm on drafts and will error.

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

## HA Runtime State Context (`context/`)

The `context/` directory is an auto-generated, read-only snapshot of HA runtime
state — entity registry, area registry, device registry, and the UI-editable
`automations.yaml`. It is populated by `scripts/ha-context-dump.sh` and refreshed
every 6 hours (or on manual button press) via the autonomous context-sync pipeline.

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

`context/areas.json` and `context/automations-ui.yaml` are small enough (<150KB
combined) that reading them in full is fine when needed.

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
- **Kiosk display:** 65-inch TCL 1080p TV, Chromium kiosk mode, pointed at `/dashboard-home/kiosk`
- **ESPHome Device Builder:** HA add-on, compiles and flashes firmware OTA to Konnected boards

---

## Upcoming Work

- **Firewalla HA integration** — Toggle kids' internet rules, show active rulesets, time remaining on scheduled blocks
- **Roblox activity detector** — Query Loki for Zeek DNS logs matching `roblox.com`/`rbxcdn.com`, surface as conditional tile on dashboard showing which child's device is playing
- **`firewalla-network-guardian`** — Anomaly detection module (planned PitziLabs repo)
- **Roku integration** — Two Rokus unreachable (possible Firewalla Smart Protect interference)
- **Dashboard iteration** — Ongoing polish of Kiosk view layout, colors, card sizing
