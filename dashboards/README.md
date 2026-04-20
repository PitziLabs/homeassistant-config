# dashboards/

YAML-managed Lovelace dashboards. Both are registered in `configuration.yaml` under `lovelace.dashboards` and are fully git-tracked — no UI editor involvement. Changes deploy automatically via the GitOps pipeline.

## `home.yaml` — Home + Kiosk

Two views in a single file, each solving a distinct display context.

### Home view (`/dashboard-home/home`)

Mobile-first control interface. Design principle: show only what's active.

- **Masonry layout** — standard scrollable column layout
- **Conditional lighting cards** — each light appears only when on; all-off rooms show an "All off" chip using template sensors from `configuration.yaml`
- **Sonos group-awareness** — 6 media player cards, each gated on a `binary_sensor.sonos_*_leader` template sensor; only the group coordinator shows when speakers are grouped
- **Alarm panel** — always visible at top, with a 3×2 sensor grid showing all door/motion contacts
- **Weather forecast** — daily summary from Met.no

### Kiosk view (`/dashboard-home/kiosk`)

Fixed 1080p wall display on a 65-inch TCL TV running Chromium in kiosk mode.

- **CSS Grid layout** via `layout-card` with `grid-template-areas`; `height: 100vh` — no scrolling at any content state
- **Theme:** `Noctis Kiosk` (see `themes/`) applies state-based backgrounds to all cards globally — no per-card styling in this file
- **`fill_container: true`** on all Mushroom cards so background color fills the grid cell
- **Unavailable filtering** — every card is wrapped in `type: conditional` with `state_not: unavailable`; offline devices disappear silently
- **Alarm chip animation** — card-mod CSS `@keyframes` with Jinja2 state checks: blue = armed_away, green = armed_home, amber = arming/pending, red = triggered

**Grid structure:**
```
"alarm   alarm   alarm   alarm"
"sensors sensors sensors sensors"
"col1    col2    col3    col4"
```

| Column | Contents |
|--------|----------|
| Col 1 | Kitchen + Play Room lights |
| Col 2 | Office lights |
| Col 3 | Family Room + Entry/Upstairs + Switches |
| Col 4 | clock-weather-card + Outdoor + conditional Sonos |

### Kiosk Mode

`kiosk_mode` block at the top of `home.yaml` hides header and sidebar for the `Kiosk` user (a non-admin local account used on the wall display).

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
| [Mushroom](https://github.com/piitaya/lovelace-mushroom) | Light, entity, alarm cards, chips, title cards |
| [mini-media-player](https://github.com/kalkih/mini-media-player) | Sonos cards with album art |
| [layout-card](https://github.com/thomasloven/lovelace-layout-card) | CSS Grid engine (kiosk view) |
| [card-mod](https://github.com/thomasloven/lovelace-card-mod) | Theme-level CSS + Jinja2 templates |
| [kiosk-mode](https://github.com/NemesisRE/kiosk-mode) | Sidebar/header hiding for wall display |
| [clock-weather-card](https://github.com/pkissling/clock-weather-card) | Animated weather + clock widget |
