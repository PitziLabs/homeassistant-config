# Roadmap

Aspirational work for this HA instance. Items here are not commitments —
they're prompts for the next conversation. Promote to a GitHub issue when
work actually starts.

## Integrations

- **Firewalla HA integration** — Toggle kids' internet rules, show active
  rulesets, time remaining on scheduled blocks.
- **`firewalla-network-guardian`** — Anomaly detection module (planned
  PitziLabs repo).
- **Roku integration** — Two Rokus unreachable; possible Firewalla Smart
  Protect interference. Diagnose, then decide whether to whitelist or drop.

## Presence

- **Firewalla `consider_home` tuning** — Default window flaps Android
  device_trackers to `not_home` during routine doze (observed on
  Rachel-s-S23; see #365). Person aggregation now papers over it for
  Rachel via the laptop tracker, but bumping the Firewalla integration's
  `consider_home` to ~900s would also debounce single-source phone
  trackers (`device_tracker.galaxy_s22_presence`,
  `device_tracker.chris_phone_presence`).

## Dashboards

- **Roblox activity detector** — Query Loki for Zeek DNS logs matching
  `roblox.com` / `rbxcdn.com`, surface as a conditional tile on the
  dashboard showing which child's device is playing.
- **Kiosk polish** — Ongoing iteration on layout, colors, card sizing.
