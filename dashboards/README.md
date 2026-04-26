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

Fixed 1080p wall display on a 65-inch TCL TV running Chromium in kiosk mode.

- **View IS the grid** — the view itself is `type: custom:grid-layout` with `height: 100vh`; no nested panel-mode wrapper
- **Typed cards per cell** — every panel is a typed Lovelace card (`mushroom-light-card`, `button-card`, `mini-media-player`, `clock-weather-card`, `better-thermostat-ui-card`) wrapped in `custom:mod-card` so the ha-card host provides the height cascade
- **State-driven styling** — colors live in per-card `state` blocks (`button-card`) and `card_mod` styles, not Jinja-templated HTML. The alarm hero pulses on triggered.
- **Non-interactive** — every card sets `tap_action: { action: none }`; the wall display ignores touch
- **Unavailable handling** — declared inside each card's `state` list (e.g. a `value: unavailable` block on a button-card), not via wrapper conditionals

**Grid structure:**
```
grid-template-columns: 1fr 1fr 1.4fr 1fr
grid-template-rows:    130px 1fr
grid-template-areas:
  "weather weather alarm   alarm"
  "climate sensors lights  media"
```

| Cell | Contents |
|------|----------|
| weather | `clock-weather-card` with 4-day forecast (top-left, spans 2 cols) |
| alarm | `button-card` hero (top-right, spans 2 cols) |
| climate | 2 `better-thermostat-ui-card` dials stacked + heater `button-card` |
| sensors | 10 `button-card` tiles in a 2×5 internal grid (6 doors + 2 garage covers + 2 motion) |
| lights | 21 `mushroom-light-card` tiles in a 3×7 internal grid |
| media | 6 `mini-media-player` cards (album art via `artwork: full-cover-fit`) in a 2×3 internal grid + TVs row |

### Kiosk Mode

`kiosk_mode` block at the top of `kiosk.yaml` hides header and sidebar for the `Kiosk` user (a non-admin local account used on the wall display).

## `homelab-status.yaml` — Homelab Status

Scrollable infrastructure overview dashboard (`/dashboard-homelab-status`). Seven sections covering the full homelab stack:

| Section | What's surfaced |
|---------|----------------|
| Neptune NAS (UGREEN DXP2800) | RAID pool health, disk temps and SMART power-on hours, CPU/RAM/fan, LAN throughput |
| Proxmox (pve) | Node CPU/memory/disk, HAOS and grafana-stack VM status, backup schedule |
| Smart Home Coordinators | ZWA-2 (Z-Wave), ZBT-2 (Zigbee), both Konnected alarm panels — WiFi RSSI and uptime |
| Battery Health | 8-device grid with amber (<40%) and red (<20%) color thresholds |
| Printer (HP M477fdw) | CMYK toner levels with color-coded warnings |
| GitHub | cpitzi/prompts repo stats via REST sensor (commits, issues, PRs, stars, forks) |
| Meeting Indicator | ESP32 device state, WiFi signal quality, uptime |

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
