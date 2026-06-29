# Home Layout v4 — Hard-Placed Grid (FINAL)

**Status:** Approved, to be implemented in follow-up PR

**Target:** 65" TCL 1920×1080, Chromium display, read-only wall display

**Architecture:** CSS Grid with `grid-template-areas`, every card explicitly placed via `view_layout`. No `vertical-stack` wrappers. No auto-flow within columns.

---

## Design decisions

| Decision | Answer |
|----------|--------|
| Column count | 6 |
| Status cluster placement | Top-right (universal UX convention) |
| Infra gauges placement | Top-left (hero position, portfolio priority) |
| Sonos | Vertical right-edge strip, 1 column × 7 rows, with album art |
| Pipeline reservation | 3 cols × 2 rows |
| Pipeline placeholder | Ambient GitHub activity panel (portfolio-adjacent) |
| Entry handling | Merged with Outdoor into unified "Exterior" block on right |

## Semantic structure

- **LEFT** (col 1) — interior house controls
- **CENTER** (cols 2–4) — infrastructure + data viz (portfolio content)
- **RIGHT** (cols 5–6) — exterior/ambient + media (Sonos)

Mental model: *inside, hub, outside*.

## Grid definition

```yaml
grid-template-columns: repeat(6, 1fr)
grid-template-rows: auto auto 1fr 1fr 1fr 1fr auto
grid-template-areas:
  "infra     infra     weather   weather   alarm     sonos"
  "infra     infra     weather   weather   sensors   sonos"
  "kitchen   pipeline  pipeline  pipeline  exterior  sonos"
  "playroom  pipeline  pipeline  pipeline  exterior  sonos"
  "family    weight    weight    weight    exterior  sonos"
  "office    weight    weight    weight    exterior  sonos"
  "office    infostrip infostrip infostrip exterior  sonos"
```

## Row height budget (1920×1080)

- Row 1 (alarm / infra-top / weather-top / sonos-top): ~100px
- Row 2 (sensors / infra-bot / weather-bot / sonos-2): ~80px
- Rows 3–6 (main content): ~140px each = 560px
- Row 7 (infostrip / office-bot / exterior-bot / sonos-bot): ~60px
- Total content: ~800px
- Padding + gaps: ~64px
- **Grand total: ~864px (216px headroom under 1080p)**

## Block inventory

### `infra` (2×2, top-left)
6 radial gauges, 3×2 internal grid. Content: NAS CPU, NAS Temp, pve Mem, HAOS Mem, Grafana Mem, NAS Volume. Fix: apexcharts yaxis min/max lives under `apex_config.yaxis`, not `plotOptions.radialBar`.

### `weather` (2×2)
`clock-weather-card`, existing config preserved.

### `alarm` (1×1, top-right)
Mushroom alarm card. Existing glow animation preserved but shadow spread values reduced ~50% to match the smaller cell.

### `sensors` (1×1, below alarm)
Chips bar. Alarm chip (no pulse), 6 door/motion, plus future slots for updates/sun/body battery chips. Wrap to two lines if needed.

### `pipeline` (3×2, center)
Reserved for Phase 3 pipeline viz. Interim content: ambient GitHub activity panel — commits-per-day bar chart (14-day window, `cpitzi/prompts`) + 3 stat tiles (Commits 7d, Open PRs, Stars).

### `weight` (3×1)
Apexcharts weight chart, current config preserved.

### `kitchen` (1×1)
4 lights, 2-col internal grid.

### `playroom` (1×1)
5 lights, 2-col internal grid.

### `family` (1×1)
2 lights + consolidated `light.floor_lamp_composite` (template light wrapping `switch.family_room_outlets` + `light.floor_lamp`). Floor Lamp backlog item folded in.

### `office` (1×2)
7 office lights, 2-col internal grid, double-row.

### `exterior` (1×5)
Merged Outdoor + Entry & Upstairs. 12 entities (Front Door, Front Lantern, Garage Front, Garage Side, Shed, Porch, Garden, Entry 1, Entry 2, Downstairs Hallway, Upstairs Hallway, Meeting Light) in 2-col × 6-row internal grid. Hallways included as transitional spaces.

### `sonos` (1×7, right edge)
Vertical strip. 6 Sonos rooms (Office, Kitchen, Dining Room, Master Bedroom, Basement, Roam 2) as `mini-media-player` cards with:
- Album art (`artwork: cover`)
- Controls hidden via `hide:` keys
- `info: scroll` for long track titles
- Each card ~110px tall

### `infostrip` (3×1, footer)
HA Core version + GitHub repo commit count today. Sensors for uptime and last GitOps sync deferred to follow-up.

## What implementation includes

1. Replace entire Home view in `dashboards/home.yaml`
2. Fix apexcharts radialBar yaxis config bug
3. Create `light.floor_lamp_composite` template light in `configuration.yaml`
4. Switch Sonos from `mushroom-template-card` to `mini-media-player`
5. Scale down alarm glow shadow values
6. Add ambient GitHub activity placeholder in `pipeline` cell
7. Remove deprecated `metrics` grid row

## What implementation does NOT include

- Template sensors for HA uptime, last GitOps sync, or real pipeline data
- Updates chip, Sun chip, Body Battery chip, Solar badge (deferred to sensor-bar follow-ups post-layout)
- Real pipeline visualization (Phase 3)
- Mobile Home view changes
- Homelab Status dashboard changes

## Risks

1. Alarm card at 1-cell width may look small — fallback is 2-col expansion with Sonos narrowing to 1 col.
2. Exterior block at 12 entities in 2×6 may feel cramped — fallback is dropping hallway lights.
3. Pipeline GitHub activity depends on `cpitzi/prompts` sensors which are near-empty — chart may render quiet initially.
4. `mini-media-player` with controls hidden may still have a default tap target — acceptable per "controls okay if they come free" policy.

## Phase plan

- **Phase 1 (this PR):** Commit this spec to `docs/home-layout.md`.
- **Phase 2 (follow-up):** Rewrite Home view against this spec.
- **Phase 3+ (future):** Real pipeline viz, sensor-bar chips, GitHub sensors for `lentago/homeassistant-config`, Firewalla integration extensions.
