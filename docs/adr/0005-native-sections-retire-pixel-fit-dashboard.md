# ADR-0005: Retire the pixel-fit wall-display layout for HA-native `sections`

**Status:** Accepted (2026-06-11; reconstructed 2026-08-13)

## Context

The household wall display (then called the "kiosk" dashboard) had been built
around a hard size-fit requirement: render exactly one 2560×1440 screen with
no scrollbar, on the assumption the monitor's viewport was fixed and content
had to be forced into it. That produced `dashboards/kiosk.yaml` as
`custom:grid-layout` plus `custom:mod-card` flex/height-cascade wrappers plus
per-card pixel tuning — 1917 lines, much of it layout arithmetic rather than
card content, and the whole page pinned to `height: 100vh; overflow: hidden`.

PR #401 (2026-06-11) investigated the premise directly: the Chromium
rendering it was already running at native resolution
(`--force-device-scale-factor=1`) — the "hard layout" was entirely
self-imposed in the dashboard YAML, not a hardware constraint. Told to
abandon the size-fit requirement, the rewrite replaced the whole layout
mechanism with HA's native `type: sections` (`max_columns: 3`): cards size to
their own content, sections reflow responsively, and the page scrolls if
content exceeds one screen. Card bodies (state-driven colors, templates,
group-dimming) were carried over unchanged — only the layout wrapper was
replaced, cutting the file to 855 lines.

Two weeks later, the premise this design served — a physical wall monitor
worth pixel-fitting for — went away entirely. The household wall display and
its entire supporting stack on pve2 (X session, Chromium, `snapshot-server`,
the `office-presence` repo's `home-host/home-preview` plumbing) were torn
down 2026-06-23 and the removal documented in this repo in PRs #487 and #488
(merged 2026-06-25). `dashboards/home.yaml` (the kiosk dashboard, renamed and
promoted in the interim by PR #435) was explicitly unaffected by that
teardown — it's still deployed by the HA-side GitOps loop and viewable in the
HA web UI / companion app — but the "render for a fixed wall viewport"
concern it once served no longer has a physical target in this repo at all;
per the fleet's shared context, that shared-viewport product concern now
belongs to a separate product (`brasenia`), not this HA config repo.

## Decision

The home dashboard uses HA-native `sections` layout, deliberately with **no**
`custom:grid-layout`, no `custom:mod-card` height-cascade wrappers, and no
fixed-pixel "fit one screen without a scrollbar" sizing. Cards are typed
(`button-card`, `mushroom-*`, `mini-media-player`, `clock-weather-card`,
`thermostat` dials) with state-driven colors in per-card `state` blocks; the
page is allowed to scroll. This is recorded in `CLAUDE.md` as a deliberate,
named retirement ("that pixel-fit design was retired 2026-06-11 — abandoning
the size-fit requirement was a deliberate call") specifically so a future
session doesn't "fix" the scrolling behavior by reintroducing pixel-fit
layout.

## Alternatives

- **Recorded at the time:** a "minimal relax" of the existing pixel-fit
  design — loosen specific measurements that were fighting content rather
  than replace the layout mechanism outright. PR #401 states this option was
  offered and Chris chose the full rewrite instead, on the reasoning that the
  size-fit requirement itself, not just its current tuning, was the thing to
  drop.
- **Recorded at the time (the retired design itself):** the
  `custom:grid-layout` + `mod-card` cascade + fixed-pixel design. This was
  the shape actually built and shipped for months before #401; it's recorded
  here as the alternative being retired, not a hypothetical.
- **Retrospective — not considered at the time:** keep the pixel-fit design
  but scope it to a dedicated `dashboards/home-wall.yaml` used only by the
  physical monitor, leaving `home.yaml` free to reflow for mobile/web. Judged
  worse in hindsight, not just different: the household wall monitor this
  would have served was torn down twelve days later (#487/#488), which would
  have made the dedicated pixel-fit variant dead weight almost immediately —
  the single-dashboard, no-hard-layout design turned out to be the
  forward-compatible choice by accident, not foresight.

## Consequences

- The home dashboard scrolls when content exceeds one screen — an explicit,
  accepted trade for layout simplicity and content-driven sizing, not a
  regression to fix.
- With no wall monitor left to render to, this design's original motivation
  (fit a fixed physical viewport) no longer applies to this repo at all; the
  dashboard is now designed for the HA web UI / companion app, where
  variable viewport size was always the norm anyway. Any future project that
  needs a shared, always-on physical viewport is a `brasenia`-shaped concern,
  not a reason to reintroduce pixel-fit YAML here.
- `dashboards/home-codesign.yaml` mirrors `home.yaml` structurally (via
  `scripts/sync-home-codesign.sh`, CI-enforced), so this layout choice
  propagates automatically to the codesign sandbox without separate upkeep.
