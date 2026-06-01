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
| `gitops-pull.sh` | (run in place from `/opt/homeassistant-config/kiosk-host/`) | `0755` | `root:root` | bootstrap only |
| `gitops-pull.service` | `/etc/systemd/system/dashboard-kiosk-gitops.service` | `0644` | `root:root` | bootstrap only |
| `gitops-pull.timer` | `/etc/systemd/system/dashboard-kiosk-gitops.timer` | `0644` | `root:root` | bootstrap only |
| `kiosk-snapshot` | (run from your workstation, not deployed) | `0755` | n/a | n/a |

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
  apt-get install -y git chromium xserver-xorg xinit unclutter openbox scrot

  # Clone the canonical config
  test -d /opt/homeassistant-config || \
    git clone https://github.com/PitziLabs/homeassistant-config.git /opt/homeassistant-config
  cd /opt/homeassistant-config && git checkout main && git pull --ff-only origin main

  # Install the kiosk display artifacts (the loop manages these going forward)
  install -m 0755 -o root -g root kiosk-host/dashboard-kiosk.sh         /usr/local/bin/dashboard-kiosk.sh
  install -m 0644 -o root -g root kiosk-host/dashboard-kiosk.service    /etc/systemd/system/dashboard-kiosk.service
  install -m 0755 -o root -g root kiosk-host/kiosk-show                 /usr/local/bin/kiosk-show

  # Install the gitops loop units (the loop does NOT manage these — bootstrap only)
  install -m 0644 -o root -g root kiosk-host/gitops-pull.service        /etc/systemd/system/dashboard-kiosk-gitops.service
  install -m 0644 -o root -g root kiosk-host/gitops-pull.timer          /etc/systemd/system/dashboard-kiosk-gitops.timer

  systemctl daemon-reload
  systemctl enable --now dashboard-kiosk.service
  systemctl enable --now dashboard-kiosk-gitops.timer

  systemctl status --no-pager dashboard-kiosk.service dashboard-kiosk-gitops.timer
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
