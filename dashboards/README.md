# dashboards/

YAML-managed Lovelace dashboards. All three are registered in `configuration.yaml` under `lovelace.dashboards` and are fully git-tracked — no UI editor involvement. Changes deploy automatically via the GitOps pipeline.

## `home.yaml` — Home view (`/dashboard-home/home`)

Mobile-first control interface. Design principle: show only what's active.

- **Masonry layout** — standard scrollable column layout
- **Conditional lighting cards** — each light appears only when on; all-off rooms show an "All off" chip using template sensors from `configuration.yaml`
- **Sonos group-awareness** — 6 media player cards, each gated on a `binary_sensor.sonos_*_leader` template sensor; only the group coordinator shows when speakers are grouped
- **Alarm panel** — always visible at top, with a 3×2 sensor grid showing all door/motion contacts
- **Weather forecast** — daily summary from Met.no

- **Native `sections` view — no hard layout** — the view is `type: sections` (`max_columns: 3`). Cards size to their content, sections reflow responsively, and the page scrolls if content exceeds the screen. There is **no** `custom:grid-layout`, no `custom:mod-card` height-cascade wrapper, and no fixed-pixel "fit 2560x1440 without a scrollbar" math. The previous pixel-fit grid-layout design was retired 2026-06-11 — the size-fit requirement was deliberately abandoned.
- **Typed cards per section** — every tile is a typed Lovelace card (`button-card`, `mushroom-light-card`, `mushroom-chips-card`, `mini-media-player`, `clock-weather-card`, `thermostat` dial). Multi-tile rows use nested `type: grid` cards.
- **State-driven styling** — colors live in per-card `state` blocks (`button-card`) + theme tokens, not Jinja-templated HTML. The alarm hero pulses on triggered.
- **Interactive** — light tiles toggle on tap (hold = more-info); sensors, alarm, TVs, and the climate standby tiles open more-info dialogs; thermostat dials expose +/- and menu controls; mini-media-player tiles show transport + volume overlaid on artwork; the meeting indicator toggles `switch.meeting_button_in_meeting` on tap.
- **Unavailable handling** — declared inside each card's `state` list (e.g. a `value: unavailable` block on a button-card), not via wrapper conditionals.

**Sections** (reflow across `max_columns: 3`, each introduced by a native `heading` card):

| Section | Contents |
|------|----------|
| Weather | single `clock-weather-card` (clock + current conditions + 5-row forecast) |
| Security | `button-card` alarm hero for `alarm_control_panel.home_alarm` + arm/disarm row (3 buttons) + front-door camera (`picture-entity`, snapshot) |
| Openings | 8 `button-card` tiles in a 2-col grid (4 doors + 2 garage covers + 2 motion) |
| Presence | meeting-indicator `button-card` (taps `switch.meeting_button_in_meeting`) + Chris/Rachel presence tiles |
| Climate | 2 `thermostat` dials (Upstairs/Downstairs), each with a `mushroom-chips-card` strip (humidity, setpoint, HVAC action); standby mode swaps the dial for a large current-temp tile |
| Lights | 18 `mushroom-light-card` tiles grouped into 5 room sub-grids (Family, Kitchen, Office, Hallways, Outdoor) under `heading` subtitles |
| Media | 5 `mini-media-player` cards (album art via `artwork: full-cover-fit`) in a 2-col grid + a TV `button-card` |

### kiosk-mode (third-party HACS card)

The `kiosk_mode` block at the top of `home.yaml` hides header and sidebar **only for the `Kiosk` non-admin user**. The pve2 wall display that used the Kiosk account was retired 2026-06-23; the block remains in place so it takes effect if a kiosk user is ever re-added. Normal admin sessions see the sidebar and header as usual.

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

Edit any `homelab-views/**` file and push. The GitOps loop deploys within 5 minutes. Key flag to know: HA's yaml-mode cache is keyed off the manifest's mtime (not the `!include` child's), so changing only a child view won't bust the cache. Touch `homelab-status.yaml` (or use `scripts/force-sync.sh`) to force a reload.

## HACS Dependencies

| Card | Used by |
|------|---------|
| [Mushroom](https://github.com/piitaya/lovelace-mushroom) | Home view light/entity/alarm cards; `mushroom-light-card` per light on home dashboard |
| [mini-media-player](https://github.com/kalkih/mini-media-player) | Sonos cards on Home view; home dashboard media cells with `artwork: full-cover-fit` |
| [layout-card](https://github.com/thomasloven/lovelace-layout-card) | No longer used by the home dashboard (it moved to native `type: sections` 2026-06-11); retained as a HACS dep for other views |
| [card-mod](https://github.com/thomasloven/lovelace-card-mod) | Theme-level CSS (`card-mod-root`) + per-card `card_mod` (e.g. the home media-tile group-dimming) |
| [button-card](https://github.com/custom-cards/button-card) | Sensor tiles, alarm hero, heater, TVs row in home view |
| [better-thermostat-ui-card](https://github.com/KartoffelToby/better-thermostat-ui-card) | No longer used by the home dashboard (native `thermostat` dial since #354); retained as a HACS dep |
| [kiosk-mode](https://github.com/NemesisRE/kiosk-mode) | Sidebar/header hiding for the Kiosk non-admin user |
| [clock-weather-card](https://github.com/pkissling/clock-weather-card) | Combined clock + 4-day forecast on home dashboard top strip |
