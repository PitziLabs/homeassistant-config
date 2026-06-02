# dashboards/

YAML-managed Lovelace dashboards. All three are registered in `configuration.yaml` under `lovelace.dashboards` and are fully git-tracked — no UI editor involvement. Changes deploy automatically via the GitOps pipeline.

## `home.yaml` — Home view (`/dashboard-home/home`)

Mobile-first control interface. Design principle: show only what's active.

- **Masonry layout** — standard scrollable column layout
- **Conditional lighting cards** — each light appears only when on; all-off rooms show an "All off" chip using template sensors from `configuration.yaml`
- **Sonos group-awareness** — 6 media player cards, each gated on a `binary_sensor.sonos_*_leader` template sensor; only the group coordinator shows when speakers are grouped
- **Alarm panel** — always visible at top, with a 3×2 sensor grid showing all door/motion contacts
- **Weather forecast** — daily summary from Met.no

## `kiosk.yaml` — Kiosk view (`/dashboard-kiosk/home`)

Primary 2560x1440 monitor display driven by mouse + keyboard.

- **View IS the grid** — the view itself is `type: custom:grid-layout` with `height: 100vh`; no nested panel-mode wrapper
- **Typed cards per cell** — every panel is a typed Lovelace card (`mushroom-light-card`, `button-card`, `mini-media-player`, `clock-weather-card`, `better-thermostat-ui-card`) wrapped in `custom:mod-card` so the ha-card host provides the height cascade
- **State-driven styling** — colors live in per-card `state` blocks (`button-card`) and `card_mod` styles, not Jinja-templated HTML. The alarm hero pulses on triggered.
- **Interactive** — light tiles toggle on tap (hold = more-info); sensors, alarm, TVs, and the climate standby tiles open more-info dialogs; BTUI thermostat dials expose +/- and menu controls; mini-media-player tiles show play/pause, prev/next, volume, progress, and power overlaid on the artwork; the meeting indicator card toggles `switch.meeting_button_in_meeting` on tap
- **Unavailable handling** — declared inside each card's `state` list (e.g. a `value: unavailable` block on a button-card), not via wrapper conditionals

**Grid structure:**
```
grid-template-columns: 1fr 1fr 1.4fr 1fr
grid-template-rows:    300px 1fr
grid-template-areas:
  "weather weather alarm   meeting"
  "climate sensors lights  media"
```

| Cell | Contents |
|------|----------|
| weather | `clock-weather-card` with 3-row forecast (top-left, spans 2 cols) |
| alarm | `button-card` hero for `alarm_control_panel.home_alarm` (top, third col) |
| meeting | `button-card` for the `light.meeting_light` indicator; taps `switch.meeting_button_in_meeting` (top, fourth col) |
| climate | 2 `better-thermostat-ui-card` dials stacked, each with a `mushroom-chips-card` strip (humidity, setpoint, HVAC action); standby mode swaps the dial for a large current-temp tile |
| sensors | 8 `button-card` tiles in a 2×4 internal grid (4 doors + 2 garage covers + 2 motion) |
| lights | 18 `mushroom-light-card` tiles grouped into 5 room sections (Family, Kitchen, Office, Hallways, Outdoor) with per-section header markdown cards |
| media | 6 `mini-media-player` cards (album art via `artwork: full-cover-fit`, controls overlaid) in a 2×3 internal grid + TVs row |

### Kiosk Mode

The `kiosk_mode` block at the top of `kiosk.yaml` hides header and sidebar **only for the `Kiosk` non-admin user** (used historically on the wall-display kiosk). The desktop session logs in as the normal admin user, so the sidebar/header remain available for navigation between dashboards.

## `homelab-status.yaml` — Homelab Status (mental-map fleet view)

Multi-tab dashboard at `/dashboard-homelab-status/`. Built as a **manifest of `!include`d view files** so each "lens" lives in its own file and can be evolved, added, or retired independently.

```
dashboards/
├── homelab-status.yaml          ← manifest: just a list of !include lines
└── homelab-views/
    ├── hardware.yaml            ← Lens 1: physical fleet
    ├── repos.yaml               ← Lens 2: PitziLabs/* commit / PR / issue activity
    ├── smart_home.yaml          ← Lens 3: rooms as objects, alarm hero
    ├── networks.yaml            ← Lens 4: Zigbee / Z-Wave / WiFi / LAN meshes
    ├── automations.yaml         ← Lens 5: silent-failure detection
    ├── backups.yaml             ← Lens 6: PVE jobs, NAS scrub, HAOS backup
    ├── issues.yaml              ← Lens 7: queue (alarms + GitHub + depletion)
    └── details/
        ├── neptune.yaml         ← drill-down subview from Hardware
        ├── pve.yaml             ← (one per fleet member that has detail)
        ├── pve2.yaml … pve5.yaml
        ├── haos.yaml
        ├── grafana-stack.yaml
        └── ups.yaml
```

### Lens model

Each lens answers a single "what am I looking at?" question. The user can have many lenses without their content fighting for canvas — switching lenses is a tab click. Lenses can be added, refined, or obsoleted over time without dashboard-wide refactoring; each lens is one file.

### Drill-down pattern (subviews)

Files under `homelab-views/details/` set `subview: true`, which hides them from the top tab strip and adds an automatic back-arrow. Tiles in a lens use `tap_action: navigate, navigation_path: /dashboard-homelab-status/<view-path>` to drill in. `hold_action: more-info` keeps HA's built-in entity dialog one long-press away.

Add a drill-down by dropping a new file under `details/` with a unique `path:`, then add it to the include list in `homelab-status.yaml`.

### Iteration workflow

The whole structure is designed for live iteration via `kiosk-host/kiosk-preview` — see `kiosk-host/README.md § "Design session protocol for non-kiosk dashboards"` for the pause-gitops / redirect-pve2 / restore-at-end protocol. Key flag: pass `--dashboard-root dashboards/homelab-status.yaml` when iterating any `homelab-views/**` file so HA's yaml-mode cache (keyed off the manifest's mtime, not the !include child's) gets busted on each push.

## HACS Dependencies

| Card | Used by |
|------|---------|
| [Mushroom](https://github.com/piitaya/lovelace-mushroom) | Home view light/entity/alarm cards; `mushroom-light-card` per light on kiosk |
| [mini-media-player](https://github.com/kalkih/mini-media-player) | Sonos cards on Home view; kiosk media cells with `artwork: full-cover-fit` |
| [layout-card](https://github.com/thomasloven/lovelace-layout-card) | `custom:grid-layout` — used as the kiosk VIEW type (not nested) |
| [card-mod](https://github.com/thomasloven/lovelace-card-mod) | Theme-level CSS + `custom:mod-card` cell wrapper |
| [button-card](https://github.com/custom-cards/button-card) | Sensor tiles, alarm hero, heater, TVs row in kiosk view |
| [better-thermostat-ui-card](https://github.com/KartoffelToby/better-thermostat-ui-card) | Circular thermostat dial in kiosk view |
| [kiosk-mode](https://github.com/NemesisRE/kiosk-mode) | Sidebar/header hiding for wall display |
| [clock-weather-card](https://github.com/pkissling/clock-weather-card) | Combined clock + 4-day forecast on kiosk top strip |
