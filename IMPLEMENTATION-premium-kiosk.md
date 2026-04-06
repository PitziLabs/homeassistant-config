# Implementation Guide: Premium Kiosk Dashboard

## Overview
Complete rebuild of the Kiosk view using premium HACS cards for a polished, information-dense 65-inch 1080p dark mode wall display. The Home (mobile) view is NOT modified.

## Architecture
- **layout-card** (CSS Grid) for pixel-perfect positioning — no masonry, no stacking guesswork
- **Mushroom cards** for lights and sensors — compact, beautiful, dark-mode native
- **Mushroom chips** for alarm status in a dense top bar
- **clock-weather-card** for animated weather with forecast
- **mini-media-player** for compact Sonos display
- **card-mod** for font scaling and room borders (already installed)
- **kiosk-mode** for hiding sidebar/header (already installed)

## Step 1: Install HACS Cards

In the HA UI → HACS → Frontend → search and download each:

1. **Mushroom** (search "mushroom") — by piitaya
2. **clock-weather-card** (search "clock weather") — by pkissling
3. **mini-media-player** (search "mini media player") — by kalkih
4. **layout-card** (search "layout card") — by thomasloven

After installing all four, add them to `/config/configuration.yaml` under the `frontend:` block. Replace the existing `extra_module_url:` list with:

```yaml
frontend:
  themes: !include_dir_merge_named themes
  extra_module_url:
    - /hacsfiles/kiosk-mode/kiosk-mode.js
    - /hacsfiles/card-mod/card-mod.js
    - /hacsfiles/lovelace-mushroom/mushroom.js
    - /hacsfiles/clock-weather-card/clock-weather-card.js
    - /hacsfiles/mini-media-player/mini-media-player-bundle.js
    - /hacsfiles/lovelace-layout-card/layout-card.js
```

**IMPORTANT:** The filenames above are the standard HACS filenames. After installing each card, verify the actual filename exists:
```bash
ls /config/www/community/  # or
ls /config/custom_components/  # depending on install method
```

HACS typically places frontend cards in a `hacsfiles` directory that HA serves automatically. The `/hacsfiles/` URL prefix maps to wherever HACS stores its downloads. If HA can't find a resource after restart, check the HACS resource list in Settings → Dashboards → Resources to see the actual URLs HACS registered, and use those instead.

**Restart HA after adding the resources:**
```bash
ha core restart
```

## Step 2: Replace the Kiosk view in `/config/dashboards/home.yaml`

Keep the Home view (first view) completely untouched. Replace ONLY the Kiosk view (second view, starting with `- title: Kiosk`) with:

```yaml
  # =================================================================
  # KIOSK VIEW — Premium 65" 1080p wall display
  # CSS Grid layout, custom cards, dark theme
  # URL: /dashboard-home/kiosk
  # =================================================================
  - title: Kiosk
    path: kiosk
    theme: kiosk_dark
    icon: mdi:monitor
    type: custom:grid-layout
    layout:
      grid-template-columns: 1fr 1fr 1fr 1fr
      grid-template-rows: auto auto 1fr auto
      grid-template-areas: |
        "alarm alarm weather weather"
        "sensors sensors sensors sensors"
        "col1 col2 col3 col4"
        "media media media media"
      margin: 0
      padding: 8px
      grid-gap: 8px
      height: 100vh
    cards:

      # ============================================================
      # ALARM — top left (grid area: alarm)
      # ============================================================
      - type: custom:mushroom-alarm-control-panel-card
        entity: alarm_control_panel.home_alarm
        name: Home Alarm
        states:
          - armed_away
          - armed_home
        layout: horizontal
        view_layout:
          grid-area: alarm

      # ============================================================
      # WEATHER — top right (grid area: weather)
      # ============================================================
      - type: custom:clock-weather-card
        entity: weather.forecast_home
        forecast_rows: 5
        hide_clock: false
        hide_date: false
        hide_today_section: false
        hide_forecast_section: false
        weather_icon_type: line
        animated_icon: true
        time_format: 12
        view_layout:
          grid-area: weather

      # ============================================================
      # SENSORS — full-width strip (grid area: sensors)
      # ============================================================
      - type: custom:mushroom-chips-card
        alignment: center
        view_layout:
          grid-area: sensors
        chips:
          - type: alarm-control-panel
            entity: alarm_control_panel.home_alarm
          - type: entity
            entity: binary_sensor.main_panel_front_door
            icon: mdi:door
            name: Front
            content_info: name
            use_entity_picture: false
          - type: entity
            entity: binary_sensor.main_panel_garage_door
            icon: mdi:garage
            name: Garage
            content_info: name
          - type: entity
            entity: binary_sensor.main_panel_basement_door
            icon: mdi:door
            name: Basement
            content_info: name
          - type: entity
            entity: binary_sensor.main_panel_sliding_door
            icon: mdi:door-sliding
            name: Sliding
            content_info: name
          - type: entity
            entity: binary_sensor.main_panel_office_motion
            icon: mdi:motion-sensor
            name: Office
            content_info: name
          - type: entity
            entity: binary_sensor.main_panel_family_room_motion
            icon: mdi:motion-sensor
            name: Family
            content_info: name

      # ============================================================
      # COLUMN 1 — Kitchen + Play Room (grid area: col1)
      # ============================================================
      - type: vertical-stack
        view_layout:
          grid-area: col1
        cards:
          - type: custom:mushroom-title-card
            title: Kitchen
          - type: grid
            columns: 2
            square: false
            cards:
              - type: custom:mushroom-light-card
                entity: light.kitchen_main
                name: Main
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.kitchen_island
                name: Island
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.kitchen_table
                name: Table
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.kitchen_sink
                name: Sink
                layout: horizontal
                use_light_color: true
                show_brightness_control: false

          - type: custom:mushroom-title-card
            title: Play Room
          - type: grid
            columns: 2
            square: false
            cards:
              - type: custom:mushroom-light-card
                entity: light.play_room
                name: Main
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.play_room_1
                name: Light 1
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.play_room_2
                name: Light 2
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.play_room_3
                name: Light 3
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.play_room_4
                name: Light 4
                layout: horizontal
                use_light_color: true
                show_brightness_control: false

      # ============================================================
      # COLUMN 2 — Office (grid area: col2)
      # ============================================================
      - type: vertical-stack
        view_layout:
          grid-area: col2
        cards:
          - type: custom:mushroom-title-card
            title: Office
          - type: grid
            columns: 2
            square: false
            cards:
              - type: custom:mushroom-light-card
                entity: light.office
                name: Main
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.office_lamp
                name: Lamp
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.office_bookcase
                name: Bookcase
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.office_corner
                name: Corner
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.office_back_corner
                name: Back Corner
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.office_door
                name: Door
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.desk_lamp
                name: Desk Lamp
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.desk_lamp_2
                name: Desk Lamp 2
                layout: horizontal
                use_light_color: true
                show_brightness_control: false

      # ============================================================
      # COLUMN 3 — Family Room + Entry/Upstairs + Switches (grid area: col3)
      # ============================================================
      - type: vertical-stack
        view_layout:
          grid-area: col3
        cards:
          - type: custom:mushroom-title-card
            title: Family Room
          - type: grid
            columns: 2
            square: false
            cards:
              - type: custom:mushroom-light-card
                entity: light.family_room
                name: Main
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.family_room_2
                name: Light 2
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-entity-card
                entity: switch.family_room_outlets
                name: Outlets
                icon: mdi:power-plug
                layout: horizontal
              - type: custom:mushroom-light-card
                entity: light.floor_lamp
                name: Floor Lamp
                layout: horizontal
                use_light_color: true
                show_brightness_control: false

          - type: custom:mushroom-title-card
            title: Entry & Upstairs
          - type: grid
            columns: 2
            square: false
            cards:
              - type: custom:mushroom-light-card
                entity: light.entry_1
                name: Entry 1
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.entry_2
                name: Entry 2
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.downstairs_hallway
                name: Downstairs
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.upstairs_hallway_light
                name: Upstairs
                layout: horizontal
                use_light_color: true
                show_brightness_control: false

          - type: custom:mushroom-title-card
            title: Switches
          - type: grid
            columns: 2
            square: false
            cards:
              - type: custom:mushroom-entity-card
                entity: switch.play_room_outlet
                name: Play Room
                icon: mdi:power-plug
                layout: horizontal
              - type: custom:mushroom-entity-card
                entity: switch.bonus_room
                name: Bonus Room
                layout: horizontal
              - type: custom:mushroom-entity-card
                entity: switch.basement_1
                name: Basement
                layout: horizontal

      # ============================================================
      # COLUMN 4 — Outdoor (grid area: col4)
      # ============================================================
      - type: vertical-stack
        view_layout:
          grid-area: col4
        cards:
          - type: custom:mushroom-title-card
            title: Outdoor
          - type: grid
            columns: 2
            square: false
            cards:
              - type: custom:mushroom-light-card
                entity: light.front_door
                name: Front Door
                icon: mdi:coach-lamp
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.front_lantern
                name: Lantern
                icon: mdi:lamp-outline
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.garage_front
                name: Garage Fr
                icon: mdi:garage
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.garage_side
                name: Garage Sd
                icon: mdi:garage
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-light-card
                entity: light.shed
                name: Shed
                icon: mdi:shed
                layout: horizontal
                use_light_color: true
                show_brightness_control: false
              - type: custom:mushroom-entity-card
                entity: switch.back_porch
                name: Porch
                icon: mdi:outdoor-lamp
                layout: horizontal
              - type: custom:mushroom-entity-card
                entity: switch.garden
                name: Garden
                icon: mdi:flower
                layout: horizontal

      # ============================================================
      # MEDIA — bottom strip (grid area: media)
      # Conditional: only shows when Sonos is playing
      # ============================================================
      - type: horizontal-stack
        view_layout:
          grid-area: media
        cards:
          - type: conditional
            conditions:
              - condition: state
                entity: binary_sensor.sonos_office_leader
                state: "on"
            card:
              type: custom:mini-media-player
              entity: media_player.office
              artwork: cover
              hide:
                power: true
                icon: true
                source: true
              info: scroll

          - type: conditional
            conditions:
              - condition: state
                entity: binary_sensor.sonos_kitchen_leader
                state: "on"
            card:
              type: custom:mini-media-player
              entity: media_player.kitchen
              artwork: cover
              hide:
                power: true
                icon: true
                source: true
              info: scroll

          - type: conditional
            conditions:
              - condition: state
                entity: binary_sensor.sonos_dining_room_leader
                state: "on"
            card:
              type: custom:mini-media-player
              entity: media_player.dining_room
              artwork: cover
              hide:
                power: true
                icon: true
                source: true
              info: scroll

          - type: conditional
            conditions:
              - condition: state
                entity: binary_sensor.sonos_master_bedroom_leader
                state: "on"
            card:
              type: custom:mini-media-player
              entity: media_player.master_bedroom
              artwork: cover
              hide:
                power: true
                icon: true
                source: true
              info: scroll

          - type: conditional
            conditions:
              - condition: state
                entity: binary_sensor.sonos_basement_leader
                state: "on"
            card:
              type: custom:mini-media-player
              entity: media_player.basement
              artwork: cover
              hide:
                power: true
                icon: true
                source: true
              info: scroll

          - type: conditional
            conditions:
              - condition: state
                entity: binary_sensor.sonos_roam_leader
                state: "on"
            card:
              type: custom:mini-media-player
              entity: media_player.roam_2
              artwork: cover
              hide:
                power: true
                icon: true
                source: true
              info: scroll
```

## Step 3: Validate and restart

```bash
ha core check
ha core restart
```

## Step 4: Verify

1. Navigate to `/dashboard-home/kiosk`
2. **Top left:** Mushroom alarm card — compact, horizontal layout, arm/disarm buttons
3. **Top right:** Clock-weather-card — animated weather icon, time, date, 5-day forecast bars
4. **Sensor strip:** Mushroom chips — colored dots for alarm, doors, motion across full width
5. **Four columns:** All lights visible with Mushroom cards — colored icons when on, muted when off
6. **Bottom strip:** Mini-media-player for active Sonos — compact with album art background
7. **No scrolling** at 1080p
8. **Dark theme** applied to all cards

## Step 5: Commit and push

```bash
cd /config
git add -A
git commit -m "Premium kiosk dashboard: Mushroom + clock-weather + mini-media-player

HACS cards: mushroom, clock-weather-card, mini-media-player, layout-card
CSS Grid layout with named areas (alarm, weather, sensors, 4 columns, media)
- Alarm: mushroom compact horizontal card
- Weather: animated clock-weather-card with 5-day forecast
- Sensors: mushroom chips bar across full width
- Lights: mushroom light cards with use_light_color
- Sonos: mini-media-player with album art cover mode
- Grid locked to 100vh — zero scrolling on 1080p"

git push
```

## Layout Map

```
┌─────────────────────────┬─────────────────────────┐
│ 🔒 Alarm (Mushroom)     │ ☀ Clock + Weather       │
│ [Arm Away] [Arm Home]   │ 10:30 PM  67°F  Rainy   │
│                         │ Mon Tue Wed Thu Fri      │
├─────────────────────────┴─────────────────────────┤
│ 🔘 [Alarm] [Front] [Garage] [Base] [Slide] [Mot]  │
├────────┬────────┬─────────────┬───────────────────┤
│Kitchen │Office  │ Family Room │ Outdoor           │
│[Mn][Is]│[Mn][Lp]│ [Mn] [Lt2]  │ [FrDr] [Lntn]   │
│[Tb][Sk]│[Bk][Cr]│ [Out] [Flr] │ [GrFr] [GrSd]   │
│        │[BC][Dr]│             │ [Shed] [Prch]     │
│Play Rm │[DL][D2]│ Entry       │ [Grdn]            │
│[Mn][L1]│        │ [E1] [E2]   │                   │
│[L2][L3]│        │ [Dn] [Up]   │                   │
│[L4]    │        │             │                   │
│        │        │ Switches    │                   │
│        │        │ [PR] [Bon]  │                   │
│        │        │ [Base]      │                   │
├────────┴────────┴─────────────┴───────────────────┤
│ ♫ [Office: Chopin]  [Basement: Zero 7]            │
└───────────────────────────────────────────────────┘
```

## What makes this different from previous versions

| Feature | Previous | Premium |
|---------|----------|---------|
| Layout engine | panel + horizontal/vertical stacks | CSS Grid with named areas |
| Weather | built-in tile (just "Rainy") | animated icon + clock + 5-day forecast |
| Alarm | full-size keypad | compact Mushroom horizontal card |
| Lights | built-in tile cards | Mushroom light cards with actual light color |
| Sensors | tile cards in grid | Mushroom chips bar (minimal height) |
| Sonos | full media-control card (~100px) | mini-media-player (~40px) with cover art |
| Positioning | cards flow where HA decides | every card has an explicit grid area |

## Troubleshooting

**Cards show "Custom element doesn't exist":**
HACS resources not loaded. Check Settings → Dashboards → Resources for the actual URLs HACS registered. Compare with the `extra_module_url` list in `configuration.yaml`. They may differ — HACS sometimes uses `/hacsfiles/` and sometimes `/local/community/`. Use whatever HACS shows.

**Layout doesn't fill the screen:**
Make sure `height: 100vh` is in the layout config. If the sidebar is showing, kiosk-mode isn't active — check the user name in the kiosk_mode config matches exactly.

**Clock-weather-card shows error:**
Make sure the Met.no integration is installed and `weather.forecast_home` exists. Check Developer Tools → States.

**Mushroom cards look wrong in dark mode:**
Mushroom respects HA's theme. The `kiosk_dark` theme should apply automatically. If colors look off, Mushroom may need `--mushroom-card-primary-color` and `--mushroom-card-secondary-color` added to the theme file.
