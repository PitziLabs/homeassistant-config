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

| Repo path | Deployed to | Mode | Owner |
|---|---|---|---|
| `dashboard-kiosk.sh` | `/usr/local/bin/dashboard-kiosk.sh` | `0755` | `root:root` |
| `dashboard-kiosk.service` | `/etc/systemd/system/dashboard-kiosk.service` | `0644` | `root:root` |

The systemd unit launches a bare `xinit` session pinned to display `:0`
(no display manager) and the script forks `unclutter` + `chromium` in
front of it.

## Deploy

After editing files in this directory, push them and reload systemd:

```bash
# from a workstation that can ssh to pve.local (pve → pve2 hop):
scp -o ProxyJump=root@pve.local \
    kiosk-host/dashboard-kiosk.sh \
    root@pve2:/usr/local/bin/dashboard-kiosk.sh
scp -o ProxyJump=root@pve.local \
    kiosk-host/dashboard-kiosk.service \
    root@pve2:/etc/systemd/system/dashboard-kiosk.service

ssh -J root@pve.local root@pve2 '
  chmod 0755 /usr/local/bin/dashboard-kiosk.sh
  systemctl daemon-reload
  systemctl restart dashboard-kiosk.service
  systemctl status --no-pager dashboard-kiosk.service
'
```

A restart cycles the X session and reloads Chromium against the live
dashboard URL.

## Verify

```bash
ssh -J root@pve.local root@pve2 'systemctl status dashboard-kiosk.service --no-pager'
ssh -J root@pve.local root@pve2 'journalctl -u dashboard-kiosk.service -n 50 --no-pager'
```

Or just walk over to the monitor.

## Known cleanup (not done in this commit)

- `Description=Grafana Dashboard Kiosk` in the unit is a stale label
  from when pve2 displayed Grafana. Rename to
  `Description=Home Assistant Dashboard Kiosk` next time the unit is
  touched.
- The chromium URL hard-codes `192.168.139.172` (HAOS VM IP). The HAOS
  VM gets DHCP today — pin the IP in Firewalla (see the *Static DHCP
  reservations* note in `~/CLAUDE.md`) or switch the URL to
  `http://homeassistant.local:8123/dashboard-kiosk/home`. Either makes
  the kiosk survive a lease change.
- No GitOps-style auto-deploy. Edits to this dir are deployed manually
  via the scp+restart recipe above; if this surface grows, consider an
  Ansible role or a small drop-in service on pve2 that `git pull`s and
  diffs.
