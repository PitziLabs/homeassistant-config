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
| **Browser** | Chromium in `--kiosk` mode, root-owned, no X session manager |
| **Display target URL** | `http://192.168.139.172:8123/dashboard-kiosk/home` (= `homeassistant.local`) |

## File map (on pve2)

| Repo path | Deployed to | Mode | Owner | Managed by |
|---|---|---|---|---|
| `dashboard-kiosk.sh` | `/usr/local/bin/dashboard-kiosk.sh` | `0755` | `root:root` | gitops loop |
| `dashboard-kiosk.service` | `/etc/systemd/system/dashboard-kiosk.service` | `0644` | `root:root` | gitops loop |
| `gitops-pull.sh` | (run in place from `/opt/homeassistant-config/kiosk-host/`) | `0755` | `root:root` | bootstrap only |
| `gitops-pull.service` | `/etc/systemd/system/dashboard-kiosk-gitops.service` | `0644` | `root:root` | bootstrap only |
| `gitops-pull.timer` | `/etc/systemd/system/dashboard-kiosk-gitops.timer` | `0644` | `root:root` | bootstrap only |

The kiosk `systemd` unit launches a bare `xinit` session pinned to
display `:0` (no display manager) and the script forks `unclutter` +
`chromium` in front of it. The gitops loop is a oneshot service driven
by a 5-minute timer that pulls `origin/main` and reinstalls the two
kiosk artifacts if they drift.

## Deploy

Push a change through the standard PitziLabs PR flow. The merged
change is picked up by the gitops loop on pve2 within ~5 minutes:

1. Loop fetches `origin/main` and resets the clone if it has diverged.
2. Loop `bash -n`'s the script and `systemd-analyze verify`'s the unit
   before touching the deployed copies — a syntax-broken commit can't
   put the kiosk into a crash loop.
3. If either differs from the deployed copy, the loop reinstalls it,
   runs `daemon-reload` if the unit changed, then
   `systemctl restart dashboard-kiosk.service` — a single restart
   cycles X + Chromium against the new state. No-op polls do not
   restart anything.

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
  apt-get install -y git chromium xserver-xorg xinit unclutter

  # Clone the canonical config
  test -d /opt/homeassistant-config || \
    git clone https://github.com/PitziLabs/homeassistant-config.git /opt/homeassistant-config
  cd /opt/homeassistant-config && git checkout main && git pull --ff-only origin main

  # Install the kiosk display artifacts (the loop manages these going forward)
  install -m 0755 -o root -g root kiosk-host/dashboard-kiosk.sh         /usr/local/bin/dashboard-kiosk.sh
  install -m 0644 -o root -g root kiosk-host/dashboard-kiosk.service    /etc/systemd/system/dashboard-kiosk.service

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

## Known cleanup (not done in this commit)

- `Description=Grafana Dashboard Kiosk` in `dashboard-kiosk.service`
  is a stale label from when pve2 displayed Grafana. Rename to
  `Description=Home Assistant Dashboard Kiosk` next time the unit is
  touched (the gitops loop will pick up the change automatically).
- The chromium URL hard-codes `192.168.139.172` (HAOS VM IP). The HAOS
  VM gets DHCP today — pin the IP in Firewalla (see the *Static DHCP
  reservations* note in `~/CLAUDE.md`) or switch the URL to
  `http://homeassistant.local:8123/dashboard-kiosk/home`. Either makes
  the kiosk survive a lease change.
