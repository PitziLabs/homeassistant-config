# themes/

Custom Lovelace themes. Loaded via `!include_dir_merge_named themes` in `configuration.yaml`. The Noctis base theme (installed via HACS) is a prerequisite for `noctis_kiosk.yaml`.

## `noctis_kiosk.yaml` — Active theme

Extends the Noctis dark palette with a `card-mod-card` block that applies state-based backgrounds to all Mushroom cards globally, without any per-card `card_mod` configuration in the dashboard YAML.

### State-based backgrounds

| Card type | State | Background |
|-----------|-------|------------|
| `mushroom-light-card` | `on` | Warm amber `rgba(255, 180, 50, 0.20)` + `box-shadow: 0 0 12px rgba(255, 160, 40, 0.15)` |
| `mushroom-light-card` | `off` | `var(--card-background-color)` |
| `mushroom-entity-card` | `on` | Cool blue `rgba(72, 130, 194, 0.20)` + `box-shadow: 0 0 12px rgba(72, 130, 194, 0.15)` |
| `mushroom-entity-card` | `off` | `var(--card-background-color)` |
| `mushroom-alarm-control-panel-card` | any | Neutral border only |

All transitions: `0.4s ease` on both `background` and `box-shadow`.

### How it works

The `card-mod-card` key injects a CSS + Jinja2 block evaluated in the browser for every card on load and on state change. The `config.type` check routes to the correct rule without any dashboard-side configuration. Adding a new light entity to the dashboard requires zero theme changes — it inherits automatically.

This approach trades one design decision for a runtime dependency: every card evaluation hits the Jinja2 template engine. For a single-display kiosk with a bounded entity count, this is not a practical concern.

### Color palette

| Variable | Value | Usage |
|----------|-------|-------|
| `primary-color` | `#4882c2` | Accent (Noctis blue) |
| `primary-background-color` | `#0b0c0f` | Page background |
| `card-background-color` | `#171a21` | Card resting state |
| `state-icon-active-color` | `#f0b429` | Active entity icons |

## `kiosk_polish.yaml` — Kiosk design tokens

Layered on top of `Noctis Kiosk` via the `theme: Kiosk Polish` key on the kiosk view in `dashboards/kiosk.yaml`. Defines `--kiosk-*` CSS custom properties for the 1920x1080 wall-display dashboard so colors, accents, and Mushroom sizing tokens are edited in one place instead of search-and-replace across `kiosk.yaml`.

### Tokens

| Token | Value | Usage |
|-------|-------|-------|
| `--kiosk-bg-page` | `#0e1117` | Page background (forced via `card-mod-root`) |
| `--kiosk-bg-card` | `#161b22` | Outer column wrappers (climate/sensors/lights/media/alarm hero) |
| `--kiosk-bg-tile` | `#1a1f27` | Inner tile backgrounds (per-sensor, per-thermostat, TV row) |
| `--kiosk-bg-tile-active-media` | `#14283f` | Reserved for active-media tinting |
| `--kiosk-text-primary` | `#e6edf3` | Reserved for headline text |
| `--kiosk-text-secondary` | `#8b949e` | Card name labels |
| `--kiosk-text-tertiary` | `#6e7681` | Off / unavailable icons |
| `--kiosk-accent-climate` | `#f0883e` | Climate column border-top + heater on |
| `--kiosk-accent-sensors` | `#56d364` | Sensors column border-top + door/cover closed |
| `--kiosk-accent-lights` | `#e3b341` | Lights column border-top + cover transition |
| `--kiosk-accent-media` | `#58a6ff` | Media column border-top + TV on |
| `--kiosk-accent-disarmed` | `#56d364` | Alarm hero, disarmed state |
| `--kiosk-accent-armed` | `#e3b341` | Alarm hero, arming/armed states |
| `--kiosk-accent-triggered` | `#f85149` | Alarm hero pending/triggered + door open + motion |

Mushroom token overrides (`--mush-icon-size`, `--mush-icon-symbol-size`, `--mush-card-primary-font-size`, `--mush-card-secondary-font-size`) propagate to every `mushroom-light-card` in the lights grid.

## `kiosk_dark.yaml` — Deprecated

The original custom dark theme, replaced by Noctis Kiosk. Retained for reference. Not applied to any dashboard or view.
