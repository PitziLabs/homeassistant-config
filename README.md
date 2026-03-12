# Home Assistant Configuration

YAML-based configuration for a Home Assistant smart home running on Proxmox (Intel NUC).

## Smart Home Hardware

| Category | Device | HA Integration | Status |
|----------|--------|----------------|--------|
| Alarm/Sensors | Konnected | `konnected` | Configured |
| Lighting | Philips Hue (Go, downlights) | `hue` | Configured |
| Audio | Sonos (multi-room) | `sonos` | Configured |
| TTS | Google Translate | `google_translate` | Configured |
| Mobile | Samsung Galaxy S21 | `mobile_app` | Configured |
| Network | Firewalla | `firewalla` | New — needs setup |
| Irrigation | Rachio | `rachio` | New — needs setup |
| Garage | MyQ | `myq` | Previously used (commented out) |
| Thermostat | Nest | `nest` | Previously used (commented out) |
| Music | Spotify | `spotify` | Previously used (commented out) |
| Network | Google Wifi | `google_wifi` | May be replaced by Firewalla |

## Repository Layout

```
config/
├── configuration.yaml   # Main config — includes all other files
├── automations.yaml     # 7 automation rules (alarm, door alerts, TTS)
├── scripts.yaml         # Light flash loops, siren control, Sonos grouping
├── scenes.yaml          # Red Alert, Alarm Armed, Alarm Triggered scenes
├── groups.yaml          # Door sensor + motion sensor groups
└── secrets.yaml         # (gitignored) API keys, passwords, codes
```

## Alarm System

Manual alarm panel with three modes:

| Mode | Arming Time | Entry Delay | Triggers On |
|------|-------------|-------------|-------------|
| Armed Away | 30s | 20s | Doors + motion |
| Armed Home | 5s | 5s | Doors only |
| Disarmed | — | — | Nothing |

**When triggered:** Hue Go flashes red, Konnected siren sounds, push + persistent notifications sent.

**Safety check:** If any door/window is open when arming, HA announces via TTS and auto-disarms.

## Door & Room Announcements

- Jake's room opens → TTS to master bedroom speaker
- Hannah's room opens → TTS to master bedroom + kitchen speakers, push notification

---

## Resurrection Plan

Step-by-step guide to get Home Assistant running again on Proxmox.

### Phase 1: Infrastructure (Proxmox + HA Install)

1. **Provision the HA VM on Proxmox**
   - Download the [Home Assistant OS image for Proxmox](https://www.home-assistant.io/installation/alternative#install-home-assistant-operating-system) (QCOW2)
   - Create a new VM: 2+ vCPUs, 2GB+ RAM, 32GB+ disk
   - Import the QCOW2 disk image and boot
   - Assign a static IP or DHCP reservation via Firewalla

2. **Initial HA setup**
   - Access HA at `http://<vm-ip>:8123`
   - Create your user account
   - Let HA discover devices on the network (it will auto-detect Hue, Sonos, etc.)

3. **Install HACS (Home Assistant Community Store)**
   - Adds access to community integrations and frontend cards
   - Useful for Firewalla integration and custom Lovelace cards

### Phase 2: Restore Configuration

4. **Clone this repo into the HA config directory**
   ```bash
   # SSH into the HA VM or use the Terminal add-on
   cd /config
   git init
   git remote add origin <this-repo-url>
   git pull origin main
   ```

5. **Create `secrets.yaml`** with your credentials:
   ```yaml
   alarm_code: "your_alarm_code"
   myq_password: "your_myq_password"
   nest_client_secret: "your_nest_secret"
   spotify_secret: "your_spotify_secret"
   ```

6. **Update device IDs** — After HA discovers devices, the internal `device_id` values will differ from the old config. Find and replace these in:
   - `automations.yaml` (Konnected device triggers, Hue Go triggers)
   - `scripts.yaml` (Hue Go flash scripts, siren scripts)
   - Use HA Developer Tools > States to look up new entity/device IDs

7. **Update entity IDs if needed** — If devices are named differently during setup, update references in automations, scripts, scenes, and groups.

8. **Update the mobile app notification target** — Re-install the HA Companion App on your phone. The new entity ID (e.g., `notify.mobile_app_sm_xxxxx`) needs to replace `notify.mobile_app_sm_g998u1` in automations.

9. **Restart Home Assistant** and verify all entities are available in Developer Tools > States.

### Phase 3: Add New Integrations

10. **Firewalla**
    - Install the [Firewalla integration](https://www.home-assistant.io/integrations/firewalla/) via HACS or native integration
    - Provides network device presence, bandwidth monitoring, and device tracking
    - Can be used for presence-based automations (who's home)

11. **Rachio**
    - Add via Settings > Devices & Services > Add Integration > Rachio
    - Requires Rachio API key from [rachio.com/api](https://app.rach.io)
    - Exposes zone switches, schedules, and rain delay controls
    - See [Enhancement Ideas](#enhancement-ideas) below for irrigation automations

12. **Re-enable commented-out integrations** as needed:
    - **MyQ**: Uncomment in `configuration.yaml`, add password to `secrets.yaml`
    - **Nest**: Re-register via Google Device Access Console, uncomment config
    - **Spotify**: Re-register app, uncomment config, add secret

### Phase 4: Validate & Harden

13. **Test all automations** — Arm/disarm the alarm, open doors, trigger motion sensors. Verify notifications, TTS, lights, and siren all respond correctly.

14. **Set up backups** — Configure HA automatic backups (Settings > System > Backups). Consider backing up to a network share or the second NUC.

15. **Enable SSL/HTTPS** — Use the DuckDNS or Let's Encrypt add-on for secure remote access, or use Nabu Casa (Home Assistant Cloud).

16. **Set up the File Editor or VS Code add-on** for editing YAML directly in the browser.

---

## Enhancement Ideas

### Presence-Based Automations
- **Auto-arm/disarm** using phone presence detection (HA Companion App or Firewalla device tracking)
- **Arrive home**: disarm alarm, turn on entryway lights, adjust thermostat
- **Leave home**: arm alarm (after door-open check), turn off all lights, set thermostat to away mode

### Firewalla Network Awareness
- **New device alerts**: notify when an unknown device joins the network
- **Bandwidth monitoring**: alert when unusual traffic patterns detected
- **Kid device tracking**: automate screen-time notifications or internet schedules

### Rachio Irrigation Automations
- **Weather-aware watering**: skip schedules when rain is forecasted (Rachio does this natively, but HA can add more logic)
- **Seasonal schedules**: adjust watering duration based on month/temperature via HA automations
- **Notification on completion**: "Front yard watering complete" via TTS or push

### Alarm System Upgrades
- **Alarm code via keypad**: uncomment and set `code: !secret alarm_code` in `configuration.yaml` for PIN-protected arming
- **Camera snapshots on trigger**: if cameras are added, capture a snapshot and attach to the push notification
- **Progressive alerts**: first trigger sends notification, second trigger activates siren
- **Night mode**: auto-arm at bedtime, auto-disarm at wake-up time

### Sonos & Audio
- **Doorbell announcements**: play a chime on all speakers when the doorbell rings
- **Whole-home announcements**: TTS broadcast to all grouped Sonos speakers for alarm events
- **Morning briefing**: weather, calendar events, commute time read aloud at a set time

### Dashboard & Monitoring
- **Custom Lovelace dashboard**: alarm status panel, door/window status, Rachio zones, Firewalla stats
- **History & trends**: track door open/close frequency, alarm events over time
- **System health card**: Proxmox VM status, HA uptime, integration connectivity

### Infrastructure
- **Use the second NUC** as a backup Proxmox node or dedicated monitoring server (Grafana + InfluxDB for HA long-term stats)
- **Zigbee/Z-Wave stick**: add a Zigbee coordinator (like Sonoff Zigbee 3.0 dongle) passed through to the HA VM for direct device control without vendor bridges
- **MQTT broker**: run Mosquitto as an add-on for local IoT device communication

### Quality of Life
- **Adaptive lighting**: auto-adjust light color temperature throughout the day (warm at night, bright during day)
- **Vacation mode**: randomize lights on/off to simulate occupancy
- **Garage door automation**: auto-close garage if left open for 15+ minutes, with notification
- **Leak sensors**: add water leak sensors near water heater, washing machine — instant notification on detection
