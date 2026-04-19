# Home Assistant Configuration — PitziLabs

Production-grade, git-controlled Home Assistant deployment running on Proxmox. Every configuration file is YAML-driven, version-controlled, and deployed through a structured AI-augmented development workflow.

This isn't a collection of UI screenshots. It's an opinionated infrastructure project with a defined architecture, reproducible deployment patterns, and a development process built around code review and iterative refinement.

## What's Here

**A complete smart home platform** managing 40+ entities across lighting (Hue, Kasa), security (Konnected alarm panels with custom ESPHome firmware), media (Sonos whole-home audio), and environmental monitoring (weather, door/motion sensors) — all surfaced through two purpose-built dashboards.

**A custom alarm system** built from bare hardware up. Two Konnected ESP8266 panels running fully inlined ESPHome firmware: one driving 4 door contacts, 2 motion sensors, and a siren output; the other repurposed as an interior annunciator with a piezo buzzer playing RTTTL tones. Eight YAML automations handle the full alarm lifecycle — arming sequences, entry/exit delays with audible countdowns, triggered siren activation, disarm confirmation, and a door chime for everyday use.

**Two dashboard experiences** from a single YAML file. A mobile-first Home view uses conditional cards that surface only what's active — lights appear when on, Sonos players show only when playing (with group-awareness so grouped speakers don't duplicate). A Kiosk view drives a 65-inch wall display using CSS Grid layout, Mushroom cards with theme-driven state coloring, animated alarm status chips, and a clock-weather widget — all locked to 1080p with zero scrolling.

**A Homelab Status dashboard** providing an at-a-glance infrastructure overview: NAS health (Neptune UGREEN DXP2800 — pool status, disk temps, SMART hours, LAN throughput), Proxmox node and VM metrics, smart home coordinator firmware/signal status, battery health grid with amber/red color coding, CMYK toner levels, GitHub repo activity, and the custom-built ESP32 meeting indicator device.

**Template sensors** that solve real UX problems. Sonos group coordinator detection prevents duplicate media cards when speakers are grouped. Per-room light activity sensors drive the mobile view's "all off" indicators. Both patterns are documented in `configuration.yaml` with clear rationale.

## Architecture

```
Proxmox VE (hypervisor)
├── Home Assistant OS VM (192.168.139.172)
│   ├── ESPHome Device Builder (add-on)
│   │   ├── Main Panel — 4 doors, 2 motion, siren (ESP8266)
│   │   └── Secondary Panel — piezo annunciator (ESP8266)
│   ├── YAML Configuration ← this repo
│   │   ├── configuration.yaml — core config, alarm platform, template sensors
│   │   ├── automations.yaml — alarm lifecycle + door chime
│   │   ├── dashboards/home.yaml — Home (mobile) + Kiosk (wall display) views
│   │   └── themes/noctis_kiosk.yaml — global card-mod state styling
│   └── .storage/ — HA-managed runtime state (excluded from git)
├── Firewalla Gold SE (192.168.139.1) — network firewall
└── Grafana/Loki stack (LXC 192.168.139.20) — observability
```

## Development Workflow

This project uses an AI-augmented development process that separates architectural thinking from mechanical execution. The workflow is designed around the same principles I'd apply to any infrastructure team: clear separation of concerns, mandatory code review, and reproducible deployments.

### The Cycle

```
┌─────────────────────────────────────────────────────────┐
│  1. DESIGN — Claude.ai (Architect)                      │
│     Discuss requirements, constraints, tradeoffs.       │
│     Produce an implementation guide: exact file paths,  │
│     YAML blocks, validation steps, commit message.      │
├─────────────────────────────────────────────────────────┤
│  2. BUILD — Claude Code (Engineer)                      │
│     Execute the implementation guide mechanically.      │
│     Create/modify files, run validation commands.       │
│     Open a pull request with descriptive commits.       │
├─────────────────────────────────────────────────────────┤
│  3. REVIEW — Human + Claude.ai                         │
│     Review the PR diff for correctness, style, and      │
│     alignment with the implementation guide.            │
│     Catch entity ID mismatches, YAML structure issues,  │
│     and unintended side effects.                        │
├─────────────────────────────────────────────────────────┤
│  4. MERGE — GitHub (automerge enabled)                  │
│     PR merges to main after approval.                   │
├─────────────────────────────────────────────────────────┤
│  5. DEPLOY — SSH to HA VM                               │
│     git pull from /homeassistant                        │
│     ha core check (validate config)                     │
│     ha core restart                                     │
│     Visual verification on target device                │
├─────────────────────────────────────────────────────────┤
│  6. ITERATE — back to step 1                            │
│     Observe behavior on real hardware.                  │
│     File issues for anything unexpected.                │
│     Next cycle addresses what was learned.              │
└─────────────────────────────────────────────────────────┘
```

### Why This Works

**Architectural decisions are documented before code is written.** Every implementation guide captures the reasoning — not just *what* to change, but *why* this approach over alternatives. This creates a decision log that survives beyond any single session.

**Mechanical execution is separated from design thinking.** Claude Code operates from a spec, not from a conversation. This eliminates the drift that happens when you design and build simultaneously, and it produces cleaner commits because the scope was defined before the first file was touched.

**Code review catches a real category of bugs.** Entity IDs in Home Assistant are notoriously tricky — they're set at device adoption time and don't change when you rename things. A review step specifically looking for ID mismatches between config and actual entities has caught real issues in this project.

**The deploy step includes validation.** `ha core check` catches YAML syntax errors and missing entity references before a restart. Visual verification on the target device (phone for mobile view, wall display for kiosk) confirms the actual rendered output matches intent.

### What I'd Change at Scale

This workflow is optimized for a single-maintainer project. For a team, I'd add:

- **A CI pipeline** running `yamllint` and custom validators on PR (checking entity IDs against a known inventory, verifying theme references resolve, flagging secrets references that don't have `.example` counterparts).
- **Automated deployment** via GitHub Actions — webhook on merge triggers `git pull` + `ha core check` + `ha core restart` on the HA VM, with rollback on check failure.
- **Environment promotion** — a staging HA instance for testing dashboard changes before they hit the production wall display.

## Validation Pipeline

Every PR runs Home Assistant's actual `check_config` validator as a CI gate — the same validator the daemon runs at startup. This catches schema errors, missing integrations, and bad `!include` paths that plain YAML linters miss entirely.

### What the gate does

The `ha-config-check` workflow (`.github/workflows/ha-config-check.yml`):

1. Reads the pinned HA version from `.ha-version` at repo root
2. Copies `secrets.fake.yaml` → `secrets.yaml` so `!secret` references resolve without exposing real credentials
3. Runs `frenck/action-home-assistant` (pinned to a commit SHA for supply-chain hygiene) which pulls the exact HA Docker image for that version and runs `check_config` against the full config tree

A `check_config` failure blocks merge. A YAML syntax error or a voluptuous schema violation will show the exact integration and line number in the job log.

### `.ha-version`

`.ha-version` contains a single line matching the format of `/config/.HA_VERSION` on the running instance (e.g., `2026.4.1`). This pin ensures CI validates against the same HA release actually deployed — not latest, which may have breaking schema changes.

### Card 2 — auto-sync via `repository_dispatch`

HAOS pushes the running version to GitHub on every full startup. The loop is event-driven — no polling, no cron, no external exposure.

```
homeassistant_started event
  → rest_command POSTs to /repos/PitziLabs/homeassistant-config/dispatches
  → ha-version-sync workflow validates payload, compares to .ha-version
  → if drift: branch, bump, PR (opened with HA_SYNC_PAT so downstream workflows fire)
  → PR triggers Card 1 ha-config-check against the new version
  → auto-merge via existing branch protection Ruleset on pass
```

#### HA-side components (`packages/ha_version_sync.yaml`)

- **`sensor.ha_core_version`** — `command_line` sensor reading `/config/.HA_VERSION`, refreshed hourly (startup dispatch is event-driven, not polled)
- **`rest_command.github_dispatch_version`** — POSTs a `ha-version-report` dispatch event with `client_payload.version` to the GitHub API
- **`automation.ha_version_sync_on_start`** — fires on `homeassistant_started`, calls the rest command; `mode: single` prevents burst duplication

#### Workflow (`ha-version-sync.yml`)

1. Validates the incoming `client_payload.version` against `^[0-9]+\.[0-9]+\.[0-9]+(b[0-9]+)?$` — dev builds are explicitly rejected; fail-closed on bad input before any shell interpolation
2. Compares to `.ha-version` on `main`; exits 0 if versions match
3. Checks for an existing open PR on `ha-version-bump/<version>` (idempotent — handles rapid reboot bursts)
4. If drift and no existing PR: creates branch, bumps `.ha-version`, opens PR via `HA_SYNC_PAT`

#### Why `HA_SYNC_PAT` instead of `GITHUB_TOKEN`

GitHub's default `GITHUB_TOKEN` cannot trigger other GitHub Actions workflows on events it creates (this is an intentional anti-loop guard). The `ha-version-sync` workflow needs the version bump PR to fire `ha-config-check` and the Claude review — both of which run on `pull_request` events. Opening the PR with a fine-grained PAT (`HA_SYNC_PAT`) bypasses this restriction. The same PAT lives in HAOS `secrets.yaml` as `github_pat` (for the dispatch POST) and in repo Actions secrets as `HA_SYNC_PAT` (for PR creation).

> **PAT rotation reminder:** Rotate `HA_SYNC_PAT` and `github_pat` annually. The PAT needs `Contents: Write` on this repo only.

## Config Governance

Automation files are partitioned by governance model to prevent bidirectional sync conflicts:

| File | Owner | Sync Direction | Edit Surface |
|------|-------|----------------|--------------|
| `automations.yaml` | UI-authored | git ← HA (manual, on drift) | HA editor (Settings → Automations) |
| `automations/*.yaml` | Git-authored | git → HA (via GitOps) | PR only |

**Why this matters:** The GitOps deploy pipeline uses `git reset --hard origin/main`. Any UI edit to a git-tracked automation would be silently clobbered on the next sync. The partition makes the authority explicit: `automations.yaml` is the HA editor's scratchpad, `automations/` is the pipeline's domain.

**Reconciling UI drift:** When `automations.yaml` accumulates UI edits worth keeping:
1. SSH to the HA VM: `cat /config/automations.yaml`
2. Copy the file content into a local checkout
3. Open a PR — automated review catches any issues

**Adding new git-managed automations:** Create a new `.yaml` file under `automations/` (e.g., `automations/lighting.yaml`). HA merges all files in the directory at startup via `!include_dir_merge_list`.

## GitOps Auto-Deploy

Config changes merge to `main` and deploy automatically — no SSH required.

A `time_pattern` automation (`GitOps: Poll and deploy`) triggers `shell_command.gitops_sync` every 5 minutes. The script fetches `origin/main`, compares it to `HEAD`, and if diverged: resets to the latest commits, validates via the Supervisor API (`POST /core/check`), and restarts HA Core on success. On validation failure, it rolls back to the pre-sync SHA without restarting.

**Upper-bound deployment time:** 5 minutes from merge to running config.

**Logs:** `/config/gitops-sync.log` — timestamped, leveled entries; rotates at 1 MB to `gitops-sync.log.1`.

**Rollback:** Automatic on failure. If config check returns non-200, the working tree resets to the pre-sync commit and HA Core is not restarted. A mobile notification is sent on both success and failure. No-op polls (already up to date) are silent.

**Disable:** Developer Tools → Automations → `GitOps: Poll and deploy` → toggle off.

**Force sync:** Developer Tools → Services → `shell_command.gitops_sync` → Call Service.

## Design Decisions

**Why ESPHome over stock Konnected firmware?** Full local control, no cloud dependency, custom GPIO repurposing (the secondary panel's Zone 1 became a piezo output), and the ability to define RTTTL services for granular tone control from HA automations.

**Why a manual alarm platform instead of an integration?** The manual platform gives explicit control over every timing parameter and state transition. The alarm behavior is defined entirely in YAML — arming delays, entry delays, trigger duration, which sensors are active in which arm mode — making it auditable, version-controlled, and reproducible.

**Why global theme-based card styling instead of per-card card-mod?** The Noctis Kiosk theme applies state-based backgrounds (warm amber for lights on, cool blue for switches on) to all Mushroom cards through a single `card-mod-card` block. This means adding a new light to the dashboard requires zero styling work — it inherits the theme automatically. Per-card styling creates maintenance debt that scales linearly with entity count.

**Why conditional cards on the mobile view?** A house with 40+ controllable entities produces a dashboard that's mostly noise. The Home view shows only what's active — if all kitchen lights are off, you see "All off" instead of four disabled tiles. This is an opinionated UX choice: the dashboard reflects the current state of the house, not its full capability.

**Why Sonos group coordinator detection?** When Sonos speakers are grouped, every speaker in the group reports as "playing." Without filtering, you'd see duplicate media cards. The template sensors check whether each speaker is the first member of its own group — only the coordinator gets a card. This is a small detail, but it's the kind of thing that separates a polished dashboard from a functional one.

## Homelab Status Dashboard

Portfolio-grade infrastructure status page surfacing NAS health, Proxmox VM metrics, smart home coordinator status, and device telemetry in a single scrollable view.

![](./docs/homelab-status.png)

Seven sections:
1. **Neptune (UGREEN DXP2800)** — server status, RAID pool health, disk temps and power-on hours, CPU/RAM/fan/LAN throughput
2. **Proxmox (pve)** — node CPU/memory/disk, HAOS and grafana-stack VM health, backup schedule
3. **Coordinators** — ZWA-2, ZBT-2, and both Konnected ESPHome alarm panels with WiFi RSSI
4. **Battery Health** — 8-device grid with amber (<40%) and red (<20%) color thresholds
5. **Printer** — HP M477fdw CMYK toner levels with warning colors
6. **GitHub** — cpitzi/prompts commits, issues, PRs, stars, forks
7. **Meeting Indicator** — ESP32 device built for Rachel's office: state, WiFi signal quality, uptime

## File Structure

```
├── configuration.yaml        Core config: alarm, templates, frontend, Prometheus
├── automations.yaml          UI-authored automations (HA editor target; drift expected)
├── automations/
│   └── meeting.yaml          Git-managed automations (pipeline-managed, PR-only)
├── packages/
│   └── ha_version_sync.yaml  HA Version Sync — startup dispatch to GitHub
├── groups.yaml               Door and motion sensor groups
├── secrets.yaml.example      Documents required secrets (actual secrets gitignored)
├── secrets.fake.yaml         Safe dummy secrets for CI check_config validation
├── .ha-version               Pinned HA version for CI (matches running instance)
├── dashboards/
│   ├── home.yaml             Two views: Home (mobile) + Kiosk (wall display)
│   └── homelab-status.yaml   Homelab Status dashboard (7 sections)
├── themes/
│   ├── noctis_kiosk.yaml     Active theme with global card-mod state styling
│   └── kiosk_dark.yaml       Deprecated — retained for reference
├── esphome/
│   ├── konnected-56ac70.yaml Main alarm panel firmware
│   ├── konnected-56a4fa.yaml Secondary panel (piezo) firmware
│   └── secrets.yaml.example  ESPHome secrets template
├── .github/workflows/
│   ├── ha-config-check.yml   HA check_config CI gate (Card 1)
│   ├── ha-version-sync.yml   Auto-bump .ha-version on HAOS startup (Card 2)
│   ├── lint.yml              YAML lint gate
│   └── claude.yml            Claude Code automation
├── CLAUDE.md                 Project context for AI-assisted development
└── .gitignore                Excludes runtime state, secrets, build artifacts
```

## HACS Dependencies

| Card | Purpose |
|------|---------|
| [Mushroom](https://github.com/piitaya/lovelace-mushroom) | Light/entity/alarm cards and sensor chips |
| [clock-weather-card](https://github.com/pkissling/clock-weather-card) | Animated weather with clock and forecast |
| [mini-media-player](https://github.com/kalkih/mini-media-player) | Compact Sonos display with album art |
| [layout-card](https://github.com/thomasloven/lovelace-layout-card) | CSS Grid layout engine for kiosk view |
| [card-mod](https://github.com/thomasloven/lovelace-card-mod) | Theme-level CSS styling with Jinja2 |
| [kiosk-mode](https://github.com/NemesisRE/kiosk-mode) | Hides sidebar/header for wall display |
| [Noctis](https://github.com/aFFekopp/nern) | Base dark theme (extended by Noctis Kiosk) |

## Part of the PitziLabs Portfolio

This repository is one piece of a broader infrastructure portfolio at [github.com/PitziLabs](https://github.com/PitziLabs):

- **[aws-lab-infra](https://github.com/PitziLabs/aws-lab-infra)** — Terraform-managed three-tier AWS environment (VPC, ECS Fargate, RDS, ElastiCache, CI/CD)
- **[firewalla-axiom-pipeline](https://github.com/PitziLabs/firewalla-axiom-pipeline)** — Fluent Bit log pipeline shipping Firewalla network telemetry to Axiom
- **[firewalla-grafana-stack](https://github.com/PitziLabs/firewalla-grafana-stack)** — Self-hosted Grafana + Loki observability for home network monitoring
- **[workstation-bootstrap](https://github.com/PitziLabs/workstation-bootstrap)** — Idempotent workstation provisioning for ChromeOS, Xubuntu, and Fedora

## License

MIT
