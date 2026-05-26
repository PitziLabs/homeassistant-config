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

## Dashboards

- **Roblox activity detector** — Query Loki for Zeek DNS logs matching
  `roblox.com` / `rbxcdn.com`, surface as a conditional tile on the
  dashboard showing which child's device is playing.
- **Kiosk polish** — Ongoing iteration on layout, colors, card sizing.
