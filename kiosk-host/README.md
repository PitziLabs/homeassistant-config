# kiosk-host/

Display-host configuration for the machine that renders
`/dashboard-kiosk/home` on the household monitor. The kiosk dashboard
itself lives in `dashboards/kiosk.yaml`; these files configure the
*Chromium kiosk runner* that points a screen at it.

## Where it runs

| | |
|---|---|
| **Host** | `pve2` (NUC, i3-6100U, quorum-only PVE node — see top-level `~/CLAUDE.md`) |
| **Display** | 2560x1440 monitor on `HDMI-2`, mouse + keyboard attached |
| **Browser** | Chromium, root-owned, no X session manager. Two modes (see *Toggle* below). |
| **Display target URL (default)** | `http://homeassistant.local:8123/dashboard-kiosk/home` |

## File map (on pve2)

| Repo path | Deployed to | Mode | Owner | Managed by |
|---|---|---|---|---|
| `dashboard-kiosk.sh` | `/usr/local/bin/dashboard-kiosk.sh` | `0755` | `root:root` | gitops loop |
| `dashboard-kiosk.service` | `/etc/systemd/system/dashboard-kiosk.service` | `0644` | `root:root` | gitops loop |
| `kiosk-show` | `/usr/local/bin/kiosk-show` | `0755` | `root:root` | gitops loop |
| `snapshot-server` | `/usr/local/bin/snapshot-server` | `0755` | `root:root` | gitops loop |
| `snapshot-server.service` | `/etc/systemd/system/snapshot-server.service` | `0644` | `root:root` | gitops loop |
| `gitops-pull.sh` | (run in place from `/opt/homeassistant-config/kiosk-host/`) | `0755` | `root:root` | bootstrap only |
| `gitops-pull.service` | `/etc/systemd/system/dashboard-kiosk-gitops.service` | `0644` | `root:root` | bootstrap only |
| `gitops-pull.timer` | `/etc/systemd/system/dashboard-kiosk-gitops.timer` | `0644` | `root:root` | bootstrap only |
| `kiosk-snapshot` | (run from your workstation, not deployed) | `0755` | n/a | n/a |
| `kiosk-preview` | (run from your workstation, not deployed) | `0755` | n/a | n/a |

Also on pve2, *not* managed by the loop:

| Path | Owner | Purpose |
|---|---|---|
| `/etc/default/dashboard-kiosk` | `kiosk-show` | Mutable runtime state (`KIOSK_MODE`, `KIOSK_URL`). Absent → defaults apply. |

The kiosk `systemd` unit launches a bare `xinit` session pinned to
display `:0` (no display manager) and the script forks `chromium` in
front of it. The gitops loop is a oneshot service driven by a 5-minute
timer that pulls `origin/main` and reinstalls the three kiosk artifacts
if they drift.

## Toggle: kiosk dashboard ⇄ ad-hoc browser

`dashboard-kiosk.sh` reads `/etc/default/dashboard-kiosk` and branches
on `KIOSK_MODE`:

- **`kiosk`** (default) — fullscreen Chromium, no chrome, no WM,
  `unclutter` hiding the mouse. Renders the household HA dashboard.
- **`browser`** — windowed Chromium with the normal UI (tabs, address
  bar, devtools), under an `openbox` WM so the window is movable and
  resizable. For ad-hoc "put this URL on the household monitor"
  workflows driven over SSH.

The state file is owned by `/usr/local/bin/kiosk-show` and is **not**
managed by the gitops loop. Edits are clobbered on the next
`kiosk-show` run; if the file is absent, the script falls back to the
kiosk-dashboard defaults.

```bash
# Put a URL on the household monitor (browser mode, default)
ssh -J root@pve.local root@pve2 'kiosk-show https://grafana.example/d/foo'

# Fullscreen kiosk an arbitrary URL (no chrome)
ssh -J root@pve.local root@pve2 'kiosk-show --kiosk https://example.com'

# Snap back to the HA kiosk dashboard
ssh -J root@pve.local root@pve2 'kiosk-show --dashboard'

# Show current state
ssh -J root@pve.local root@pve2 'kiosk-show --show'
```

Each call rewrites the state file and `systemctl restart`s
`dashboard-kiosk.service` — the screen blinks once and lands on the
new URL within a few seconds. The display has no kiosk lockout in
browser mode; whoever's at the keyboard can navigate normally.

## Snapshot the live display

`kiosk-snapshot` is the **preferred way to capture what the household
monitor is showing** — it grabs the actual rendered frame from pve2's
X session, so you see the real kiosk state (alarm color, current Sonos
art, active media tile, etc.) rather than a fresh, just-loaded render.

Run it from your workstation (it is not deployed to pve2):

```bash
# Drop a snapshot in cwd → ./kiosk-snapshot-<UTC-timestamp>.png
kiosk-host/kiosk-snapshot

# Custom output path
kiosk-host/kiosk-snapshot -o /tmp/before-fix.png

# Capture and open in the default image viewer
kiosk-host/kiosk-snapshot --open
```

Under the hood: `ssh -J root@pve.local root@pve2`, `scrot` against
`DISPLAY=:0` as root (the kiosk's bare-xinit session), `scp` back, then
`rm` the remote temp file. Requires `scrot` on pve2 — added to the
bootstrap recipe below.

This is also the fallback path when local Playwright/Chromium fails to
launch (Gdk portal / sandbox crashes have been seen on the workstation).
Even when Playwright works, prefer `kiosk-snapshot` for kiosk captures —
Playwright would render a clean, just-authed session, missing the live
state.

## Serving arbitrary pages → moved to `office-presence`

The workstation control surface for putting pages/URLs on the office
monitor — the `kiosk` CLI, the page library, and the URL favorites — now
lives in the **private** [`office-presence`](https://github.com/PitziLabs/office-presence)
repo, installed on `PATH`:

```bash
kiosk page arch          # tagged library page (offline Mermaid)
kiosk url nullschool     # saved URL favorite
kiosk show https://…     # any http(s) URL
kiosk snap --open        # grab the current frame
kiosk home               # back to the household dashboard
```

Only the **pve2 display-host plumbing stays here** — `kiosk-show` (point
the HDMI at a URL), `snapshot-server` (`:9999` live frame), and
`dashboard-kiosk.service` (the household-dashboard runner) — because it
renders the household dashboard and is gitops-deployed from this repo.
`office-presence`'s `kiosk` drives these over SSH; it pushes page content
to `/opt/claude-kiosk/` on pve2 and serves it with a transient
`claude-kiosk-www` unit on `:8088`.

### Snapshot-server independence

`snapshot-server` on pve2 (`:9999`) — used by `office-presence`'s `kiosk`,
by `kiosk-snapshot`, and by the 6-hourly `ha-context-dump` — is
deliberately **not** `PartOf=dashboard-kiosk.service`: it scrots X `:0`,
which outlives Chromium restarts. It used to be coupled, so every
`kiosk-show` URL change (each restarts the kiosk) tore it down — and
`PartOf` propagates *stop* but not *start*, so nothing brought it back
until the next drift-triggered gitops run. It stayed dead for ~6 days. It
is now independent + `enabled` + `Restart=on-failure`, so it survives
kiosk churn and reboots.

## Live preview iteration (`kiosk-preview`)

`kiosk-preview` is the fast-iteration loop for kiosk dashboard YAML —
push a local edit, refresh Chromium, capture the new frame, in
roughly 3 seconds. Use it when you want to see the rendered result
of a dashboard change *before* committing.

```bash
# Default: pushes ./dashboards/kiosk.yaml, snapshots to cwd
kiosk-host/kiosk-preview

# Specify a different YAML and open the snapshot
kiosk-host/kiosk-preview dashboards/kiosk.yaml --open

# Push + refresh without capturing (e.g. you're at the monitor)
kiosk-host/kiosk-preview --no-snapshot

# Iterating an !include child — touches the manifest to bust HA's
# yaml-mode dashboard cache (which keys off the root file's mtime,
# not the included child's)
kiosk-host/kiosk-preview dashboards/homelab-views/hardware.yaml \
  --dashboard-root dashboards/homelab-status.yaml

# URL change (different view, dashboard, or subview) — does
# `kiosk-show --kiosk <URL>` instead of F5 (~10–15s vs ~3s for F5)
kiosk-host/kiosk-preview dashboards/homelab-status.yaml \
  --url http://homeassistant.local:8123/dashboard-homelab-status/ups-detail

# Debug overlay: distinct pure-color outline per grid-area cell, so a
# snapshot can be measured by color (see Design session protocol §
# "Measuring layout precisely"). Injected on a temp copy — never committed.
kiosk-host/kiosk-preview --debug-cells --open
```

| Flag | When to reach for it |
|---|---|
| `--dashboard-root FILE` | The pushed file is `!include`d by another dashboard YAML; pass the manifest path |
| `--url URL` | Chromium needs to point at a different URL (new dashboard, view, or subview); skips F5 for a `kiosk-show` restart |
| `--debug-cells` | You need to measure cell geometry precisely — injects a distinct color outline per grid-area cell (temp copy only; never commits borders) |
| `--open` | xdg-open the captured PNG after capture |
| `--keep` | Suppress the gitops-clobber reminder |
| `--no-snapshot` | Push + refresh only; no capture (use when you're physically watching the monitor) |

### Decision table: which flags for which file

The flag selection above maps mechanically to the file you're editing:

| You're editing | What you need |
|---|---|
| `dashboards/kiosk.yaml` | Nothing — kiosk shows it by default; plain `kiosk-host/kiosk-preview` |
| Another root manifest (e.g. `dashboards/homelab-status.yaml`) | Pause HA gitops + `kiosk-show --kiosk <URL>` once + `--url <URL>` on the first preview (see *Design session protocol for non-kiosk dashboards*) |
| A file `!include`d by another dashboard (e.g. `dashboards/homelab-views/*.yaml`) | All of the above **and** `--dashboard-root <root-manifest.yaml>` on every preview (the yaml-mode cache keys off the manifest's mtime, not the child's) |
| Theme or `extra_module_url` JS resource | Skip the loop — needs `lovelace.reload_resources` which requires the optional HA token (often absent). Commit + wait for gitops instead. |

Under the hood, each call:

1. `python3 yaml.safe_load`s the local file (refuses to push broken YAML).
2. `ssh -p 22 root@homeassistant.local 'cat > /homeassistant/dashboards/.<name>.preview-tmp && mv ... <name>'` — atomic write via stdin redirect. **Requires** SSH key access to `root@homeassistant.local` port 22 (HAOS host SSH). `scp` does *not* work on HAOS port 22 (no sftp-server); the Core container's `/config` maps to `/homeassistant` on the HAOS host filesystem.
3. Calls `lovelace.reload_resources` via the HA REST API to clear the
   frontend resource cache. Optional — looks for a long-lived access
   token at `~/.config/kiosk-preview/ha-token`; skipped silently if
   absent. yaml-mode dashboards re-read from disk on each fetch, so
   the F5 alone is enough for dashboard YAML; the resource reload only
   matters when you've also touched a JS module under `resources:`.
4. `ssh -J root@pve.local root@pve2 'DISPLAY=:0 xdotool key F5'` to
   refresh Chromium on the household monitor. **Requires** `xdotool`
   on pve2 (in the bootstrap apt-install list).
5. Waits for a **stable** rendered frame, then `curl`s the snapshot
   server (`http://pve2.local:9999/`) into
   `./kiosk-preview-<UTC-timestamp>.png`. Stability heuristic: short
   initial wait (1.2s), then poll until two consecutive PNG sizes are
   within 1% of each other (or a 6s cap is hit). md5 equality won't
   work — clock seconds + small dashboard animations make settled
   frames vary in pixels but cluster within ~0.2% of size, while a
   mid-paint skeleton is typically 50–75% smaller than a settled
   frame. Typical end-to-end loop is 4–8s.

### Things to know

- **gitops-sync clobber.** The HA-side `scripts/gitops-sync.sh` runs
  every 5 min and `git reset --hard origin/main`s `/config/`. Your
  preview survives until the next poll, then reverts. This is what you
  want — your iteration window is whatever's left in the current
  cycle, then commit + PR to make the change permanent. Pass `--keep`
  to suppress the trailing reminder.
- **Display flicker.** F5 in Chromium produces a brief blank frame
  visible at the monitor. Don't iterate in moments where it'd disrupt
  someone's view.
- **First-time SSH setup.** Both the HA host (`homeassistant.local`) and
  the kiosk-snapshot path (via `pve.local` jump) need your workstation
  key in their `authorized_keys`. The kiosk-snapshot jump already works
  for the rest of this tooling; HA-host SSH (port 22, NOT the
  Terminal & SSH add-on on 22222) needs a one-time `authorized_keys.txt`
  drop on the HAOS data partition — see the HA developer docs. Verify
  with `ssh -p 22 root@homeassistant.local 'echo ok'`.
- **Optional HA token for resource reload.** If you want
  `lovelace.reload_resources` to actually fire (rarely needed for pure
  dashboard YAML edits — see step 3 above), put a long-lived access
  token at `~/.config/kiosk-preview/ha-token` (mode `0600`). Without
  it the call is skipped and the tool still works for dashboard YAML.

### Troubleshooting

When the loop fails, the symptom usually identifies the stage:

| Symptom | Likely cause | Fix |
|---|---|---|
| Errors at *validating YAML* | Local YAML is malformed | Fix locally — the tool refuses to push broken YAML. The error names the line. |
| Errors at *pushing* | SSH to HAOS port 22 down, or key not authorized | Verify with `ssh -p 22 root@homeassistant.local 'echo ok'`. If it fails, the one-time HAOS `authorized_keys` setup hasn't been done (see *Things to know* above). |
| Snapshot is a skeleton / loading state | Frame captured before stable; transient HA load fooled the stability heuristic | Re-run `kiosk-preview`. Or capture a fresh frame with `kiosk-host/kiosk-snapshot` (which has no stability check and grabs whatever's currently on the monitor). |
| Card body shows `Card error: …` | Unknown card type, missing required option, or schema mismatch | Read the error string — it names the field or type. Cross-check the card type via `mcp__Local-HA__ha_read_resource skill://home-assistant-best-practices/references/dashboard-cards.md`. For HACS cards, confirm the card is actually installed via `mcp__Local-HA__ha_hacs_search`. |
| Card shows `Unavailable` | Entity is genuinely down, OR the entity_id is wrong | `mcp__Local-HA__ha_search_entities` to confirm the entity exists; `ha_get_state` to confirm its current value. **Don't trust `context/entities.json` for this** — it's up to 6h stale. |
| `curl pve2.local:9999` returns 503 or hangs | `snapshot-server.service` on pve2 is down | `ssh -J root@pve.local root@pve2 'systemctl status snapshot-server.service --no-pager'`; restart if needed. The unit is `PartOf=dashboard-kiosk.service`, so a kiosk restart cycles it too. |
| F5 doesn't change what's on the monitor | Chromium hung, or `xdotool` not on pve2 | `ssh -J root@pve.local root@pve2 'systemctl restart dashboard-kiosk.service'`; verify `xdotool` is installed (bootstrap apt list). |

### Design session protocol

For non-trivial kiosk dashboard work (layout changes, theming, new
cards, alarm-state polish), use this loop instead of the slower
edit→commit→wait-5min-for-gitops cycle:

1. **Start clean.** Branch off `main`:
   ```bash
   git checkout main && git pull && git checkout -b kiosk-<topic>
   ```
2. **Iterate.** Edit the YAML, run `kiosk-host/kiosk-preview --open`,
   check the captured PNG against the rubric below, repeat. Each loop
   is 4–8s.

   **Snapshot rubric** (run after every capture; if any check fails,
   fix and re-iterate before continuing):

   - **Target card rendered** — not blank, no `Card error: …` string,
     not stuck on a `Loading…` skeleton.
   - **Entity states bound** — cards you expected to have data don't
     show `Unavailable` because of an entity_id typo. Distinguish from
     entities that are genuinely down by spot-checking
     `mcp__Local-HA__ha_get_state`.
   - **Adjacent cards unchanged** — a layout change in one grid cell
     can ripple. Compare against the previous snapshot side by side
     and confirm cells you didn't touch are visually identical.
   - **Layout intact** — no horizontal scrollbars, no card overflowing
     its grid cell, no cells shrunk to zero height. Look at the cell
     boundaries, not just the card content.
   - **State encoding correct** — icons and colors match the entity's
     current state per the card's `state` blocks (e.g. green hero on a
     `disarmed` alarm, grey on a presence chip showing `not_home`).
3. **Checkpoint at logical units.** When a coherent change is ready
   (one card refactored, one theme tweak landed, one alarm-state polish
   complete), commit + PR + arm auto-merge with the usual repo flow.
   Don't pile multiple unrelated changes into one PR — small PRs are
   easier to revert if a downstream issue surfaces.
4. **Mind the gitops clobber.** Every 5 min, the HA-side gitops-sync
   resets `/homeassistant/dashboards/` to `origin/main`. While
   iterating you have whatever's left in the current poll window. If
   you want a YAML change that survives past the next poll, commit
   and let auto-merge land it.

5. **Stop iterating** when any of these is true:

   - The rubric passes and the change matches the original ask.
   - **3 consecutive snapshots are visually indistinguishable** —
     you're polishing past diminishing returns; commit what you have.
   - **More than ~6 iterations on the same card with no convergence** —
     likely the wrong card type or a fundamental layout choice. Step
     back instead of grinding harder; re-read the relevant skill
     reference (`mcp__Local-HA__ha_read_resource
     skill://home-assistant-best-practices/references/dashboard-cards.md`)
     or ask for direction.
   - **The task as stated is complete** — don't add scope from what
     the snapshot incidentally surfaces. File a GitHub issue per the
     repo's "incidentally-observed latent problems" convention if it
     warrants follow-up.

**Measuring layout precisely — when eyeballing fails.** Brightness
heuristics and thumbnails lie. Two compounding traps, and the tools that
beat them. (Every one of these produced a wrong "confirmed" in the
session that wrote this — take them seriously.)

*The traps.* Kiosk cards are dark-on-dark with no borders, so you cannot
see where one cell's box ends and the next begins, and a downscaled
thumbnail blurs every edge into the background. A model that measures
"where does the content end" by scanning for bright pixels will (a)
latch onto the nearest bright glyph *across* a cell boundary and
misattribute it (e.g. read album art two rows down as the presence
cell), and (b) mistake a top-aligned text label for the bottom of its
card box, inventing a gap that isn't there. Eyeballing column x-ranges
instead of computing them from the grid's `fr` units makes a measurement
window straddle two cells.

*Tool 1 — `kiosk-preview --debug-cells`.* Pushes a temp copy of the YAML
with a distinct pure-color outline injected per grid-area cell
(weather=cyan, alarm=magenta, meeting=yellow, …); the local file and the
committed dashboard never carry borders. Each cell's true box is then one
`np.where(color)` away, independent of its contents:

```python
from PIL import Image; import numpy as np
a = np.asarray(Image.open('kiosk-preview-<ts>.png').convert('RGB')).astype(int)
R, G, B = a[:,:,0], a[:,:,1], a[:,:,2]
def box(c):
    r, g, b = c
    m = (abs(R-r) < 40) & (abs(G-g) < 40) & (abs(B-b) < 40)
    ys, xs = np.where(m)
    return (xs.min(), xs.max(), ys.min(), ys.max())
print('alarm cell box', box((255, 0, 255)))   # magenta
```

With the box known, measure content *inside* it — and measure the card
*box*, not its text. Detect a card's accent border color (e.g. the green
`--kiosk-accent-disarmed` ≈ `(86,211,100)` left border), not the label
glyphs; the label is top-aligned, so reading it as the card bottom is how
you hallucinate a gap. A cell whose content box reaches the colored
outline is filling its cell; one that stops well short is underfilling;
one whose content extends *past* the outline is overflowing into its
neighbor.

*Tool 2 — zoom in, crop at native resolution.* Never judge typography or
alignment from the downscaled full-frame PNG. Crop the region of interest
at full 2560-wide resolution and read *that*:

```python
Image.open('shot.png').crop((1168, 0, 2545, 300)).save('/tmp/z.png')
```

A clipped clock digit or a 20px gap is obvious at native res and
invisible in a thumbnail. Crop first, then look.

*Discipline.* Do not say "confirmed" / "flush" / "aligned" from a
thumbnail or a brightness scan. Either the colored box bounds agree or a
native-resolution crop shows it plainly. If two readings disagree, the
measurement is wrong — re-measure, don't rationalize.

**Live-state caveats** (look at the captured PNG with these in mind):

- Cards labeled *Unavailable* reflect the actual current entity
  states, not a kiosk bug. If you're surprised, check the upstream
  device/integration; consider whether the dashboard should hide vs.
  show unavailable entities for that card type.
- The clock and Sonos art are dynamic — comparing PNGs from runs a
  few seconds apart won't be pixel-identical even on an unchanged
  dashboard.
- The snapshot captures the **live** kiosk session (alarm color,
  current Sonos coordinator, last media played, current weather). If
  a hero card looks empty, the entity may genuinely have no value
  right now — try again later or simulate the state via the HA UI.

**When NOT to use this loop:**

- Trivial copy edits — too much friction; just commit.
- Adding cards that reference entities not yet in
  `context/entities.json` — `kiosk-preview` only refreshes Lovelace;
  HA must already know about the entity. Refresh the context snapshot
  first (`input_button.ha_context_dump_now`) and let the
  context-snapshot PR land.
- Theme or `extra_module_url` changes — those need
  `lovelace.reload_resources`, which requires the optional HA token
  (see above).

### Design session protocol for non-kiosk dashboards

Use this when iterating any dashboard that the kiosk *isn't* currently
displaying — e.g. `homelab-status.yaml`'s lens views, the Home
dashboard, or a brand-new dashboard whose YAML doesn't yet exist on
`main`. Same fast iteration shape, plus three setup/teardown steps for
the household display:

1. **Pause the HA-side gitops sync** (otherwise it'll reset
   `/homeassistant/dashboards/` to `origin/main` every 5 min and erase
   any new files you've pushed via kiosk-preview):

   ```yaml
   # MCP tool call (Local-HA server prefix may differ in cloud sessions):
   mcp__Local-HA__ha_call_service:
     domain: automation
     service: turn_off
     target:
       entity_id: automation.gitops_poll_and_deploy
   ```

   Or via UI: Settings → Automations → "GitOps: Poll and deploy" → off.
2. **Redirect pve2's Chromium** to the dashboard you're iterating
   (commandeers the household monitor for the session):
   ```bash
   ssh -J root@pve.local root@pve2 'kiosk-show --kiosk \
     http://homeassistant.local:8123/dashboard-<id>/<view-path>'
   ```
   Once Chromium is on the right URL, regular `kiosk-preview` calls
   F5-refresh it — no further `kiosk-show` needed unless the URL
   changes (e.g. navigating to a different view or subview, which
   you can drive in one shot with `kiosk-preview --url <URL>`).
3. **Iterate.** Same edit → `kiosk-preview` → snapshot → rubric-check
   shape as the kiosk dashboard loop above (apply the same snapshot
   rubric and stop conditions). For multi-file dashboards that use
   `!include`, pass `--dashboard-root <manifest.yaml>` so the yaml-mode
   dashboard cache (keyed off the manifest's mtime, not the included
   child's) actually gets busted.
4. **Restore on the way out** (in this order, after the PR is open
   and ideally merged — otherwise the next gitops poll fetches
   `origin/main` which doesn't yet have your new files and the
   dashboard breaks until merge):

   ```yaml
   # Re-enable gitops via MCP tool call:
   mcp__Local-HA__ha_call_service:
     domain: automation
     service: turn_on
     target:
       entity_id: automation.gitops_poll_and_deploy
   ```

   ```bash
   # Send the kiosk back to the household dashboard
   ssh -J root@pve.local root@pve2 'kiosk-show --dashboard'
   ```
5. **Confirm.** A quick `kiosk-snapshot` after the restore should
   show the regular household kiosk again.

**Cost to the household:** the wall display flickers when you
`kiosk-show`, again at the F5 cadence of your iteration, and once more
at the restore. If someone's watching the dashboard at the moment,
defer the session — iteration is dense and disruptive.

## Snapshot server (network endpoint for HA)

`snapshot-server` runs as a small systemd service on pve2 listening on
`0.0.0.0:9999`. Each `GET /` returns a live PNG of the kiosk display
(content-type `image/png`). Errors return `503` with a short text body
(scrot timeout, scrot not installed, etc.). No auth — exposure is the
LAN, and the content is the household dashboard that's already visible
on the monitor.

The HA-side `scripts/ha-context-dump.sh` calls this on every ~6h dump
to refresh `context/kiosk-latest.png`. The call is best-effort with an
8-second timeout: if the server is down, the previous file is retained
and the rest of the dump proceeds normally. See `scripts/README.md` for
the consumer side.

Quick test from anywhere on the LAN:

```bash
curl -fsSL http://pve2.local:9999/ -o /tmp/kiosk-now.png && file /tmp/kiosk-now.png
```

Service status / logs:

```bash
ssh -J root@pve.local root@pve2 'systemctl status snapshot-server.service --no-pager'
ssh -J root@pve.local root@pve2 'journalctl -u snapshot-server.service -n 50 --no-pager'
```

The unit is `PartOf=dashboard-kiosk.service`, so a kiosk restart cycles
the snapshot server too — they share the X session anyway. The gitops
loop explicitly restarts `snapshot-server.service` whenever its script
or unit drifts.

## Deploy

Push a change through the standard PitziLabs PR flow. The merged
change is picked up by the gitops loop on pve2 within ~5 minutes:

1. Loop fetches `origin/main` and resets the clone if it has diverged.
2. Loop `bash -n`'s the two scripts (`dashboard-kiosk.sh`, `kiosk-show`)
   and `systemd-analyze verify`'s the unit before touching the deployed
   copies — a syntax-broken commit can't put the kiosk into a crash loop.
3. If any of the three artifacts differs from the deployed copy, the
   loop reinstalls just the ones that drifted, runs `daemon-reload` if
   the unit changed, then `systemctl restart dashboard-kiosk.service`
   *only if the runner script or unit changed* — a `kiosk-show`-only
   update doesn't flicker the display. No-op polls do not restart
   anything.

The loop refuses to deploy unless the clone is on the `main` branch,
mirroring the HA-side `scripts/gitops-sync.sh` guard.

To force an immediate pull instead of waiting for the timer:

```bash
ssh -J root@pve.local root@pve2 'systemctl start dashboard-kiosk-gitops.service'
```

To watch the loop's log:

```bash
ssh -J root@pve.local root@pve2 'tail -f /var/log/dashboard-kiosk-gitops.log'
# or
ssh -J root@pve.local root@pve2 'journalctl -u dashboard-kiosk-gitops.service -f'
```

To temporarily disable the loop (e.g. while hand-iterating on pve2):

```bash
ssh -J root@pve.local root@pve2 'systemctl stop dashboard-kiosk-gitops.timer'
# resume with:
ssh -J root@pve.local root@pve2 'systemctl start dashboard-kiosk-gitops.timer'
```

## Bootstrap (one-time, after a fresh pve2 install)

The gitops loop manages the two kiosk artifacts but cannot install
itself, so the initial setup is manual:

```bash
ssh -J root@pve.local root@pve2 '
  set -euo pipefail
  apt-get update
  apt-get install -y git chromium xserver-xorg xinit unclutter openbox scrot xdotool

  # Clone the canonical config
  test -d /opt/homeassistant-config || \
    git clone https://github.com/PitziLabs/homeassistant-config.git /opt/homeassistant-config
  cd /opt/homeassistant-config && git checkout main && git pull --ff-only origin main

  # Install the kiosk display artifacts (the loop manages these going forward)
  install -m 0755 -o root -g root kiosk-host/dashboard-kiosk.sh         /usr/local/bin/dashboard-kiosk.sh
  install -m 0644 -o root -g root kiosk-host/dashboard-kiosk.service    /etc/systemd/system/dashboard-kiosk.service
  install -m 0755 -o root -g root kiosk-host/kiosk-show                 /usr/local/bin/kiosk-show
  install -m 0755 -o root -g root kiosk-host/snapshot-server            /usr/local/bin/snapshot-server
  install -m 0644 -o root -g root kiosk-host/snapshot-server.service    /etc/systemd/system/snapshot-server.service

  # Install the gitops loop units (the loop does NOT manage these — bootstrap only)
  install -m 0644 -o root -g root kiosk-host/gitops-pull.service        /etc/systemd/system/dashboard-kiosk-gitops.service
  install -m 0644 -o root -g root kiosk-host/gitops-pull.timer          /etc/systemd/system/dashboard-kiosk-gitops.timer

  systemctl daemon-reload
  systemctl enable --now dashboard-kiosk.service
  systemctl enable --now snapshot-server.service
  systemctl enable --now dashboard-kiosk-gitops.timer

  systemctl status --no-pager dashboard-kiosk.service snapshot-server.service dashboard-kiosk-gitops.timer
'
```

Edits to `gitops-pull.sh` *will* be picked up automatically (it runs
in-place from the clone). Edits to `gitops-pull.service` or
`gitops-pull.timer` need a manual re-bootstrap of just those two
files — the loop deliberately doesn't manage the units that manage it,
to avoid a broken update putting the system in a state where it can't
fix itself.

## Verify

```bash
ssh -J root@pve.local root@pve2 'systemctl status dashboard-kiosk.service dashboard-kiosk-gitops.timer --no-pager'
ssh -J root@pve.local root@pve2 'journalctl -u dashboard-kiosk.service -n 50 --no-pager'
```

Or just walk over to the monitor.
