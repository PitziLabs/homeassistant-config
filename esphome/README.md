# esphome/

Custom ESPHome firmware for two Konnected ESP8266 alarm panels. Both configs are fully inlined — no remote `github://` package references, no cloud dependencies, every GPIO and component declared explicitly.

## Boards

### `konnected-56ac70.yaml` — Main Alarm Panel

**Hardware:** Konnected ESP8266 (NodeMCU v2), MAC `2C:F4:32:56:AC:70`

| Zone | GPIO | Assignment | Type |
|------|------|------------|------|
| 1 | GPIO5 | Front Door | Binary sensor (NC contact) |
| 2 | GPIO4 | Garage Door | Binary sensor (NC contact) |
| 3 | GPIO14 | Basement Door | Binary sensor (NC contact) |
| 4 | GPIO12 | Sliding Door | Binary sensor (NC contact) |
| 5 | GPIO13 | Office Motion | Binary sensor |
| 6 | GPIO3 | Family Room Motion | Binary sensor |
| ALRM | GPIO15 | Siren/Bell | Switch (RESTORE_DEFAULT_OFF) |

**Diagnostics exposed to HA:** WiFi signal strength, IP address, uptime, restart button.

### `konnected-56a4fa.yaml` — Secondary Panel (Piezo Annunciator)

**Hardware:** Konnected ESP8266 (NodeMCU v2), MAC `2C:F4:32:56:A4:FA`

Zone 1 (GPIO5) is repurposed as a PWM output driving a piezo buzzer. Zones 2–6 are unconnected. The panel exposes two custom ESPHome services:

| Service | Call from HA |
|---------|-------------|
| `esphome.konnected_56a4fa_play_rtttl` | `data: { song_str: "t:d=32,o=4,b=100:e4" }` |
| `esphome.konnected_56a4fa_stop_rtttl` | (no data) |

These services are called directly from alarm automations in `automations.yaml` to produce audible countdown ticks and confirmation tones. Tone differentiation: 1 tick = delay countdown, 2 ticks = armed/chime, 3 ticks = disarmed.

## Design Decisions

**Why fully inlined configs?** Remote package references (`github://`) create a hidden runtime dependency — a network outage or upstream change can break firmware compilation at the worst possible time. Inlining every component makes the firmware reproducible from the local YAML alone.

**Why repurpose a Konnected zone as a piezo output?** The secondary panel had five unused zones after its alarm sensor role was eliminated. Repurposing Zone 1 as a PWM annunciator gave a dedicated audible feedback channel without additional hardware — the panel's existing 12V power supply drives the piezo directly.

**Why `RESTORE_DEFAULT_OFF` on the siren switch?** If HA restarts while the siren is triggered, the switch must not reactivate on reconnect. `RESTORE_DEFAULT_OFF` ensures the siren is always silent after a board reset regardless of the last known state.

## Secrets

`secrets.yaml` (gitignored) contains WiFi SSID/password and the ESPHome API encryption key. `secrets.yaml.example` documents the required keys.

Firmware is compiled and flashed OTA via the ESPHome Device Builder add-on running on the same HA instance.
