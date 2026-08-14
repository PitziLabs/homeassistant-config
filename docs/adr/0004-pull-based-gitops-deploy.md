# ADR-0004: Pull-based GitOps deploy, validated and rolled back locally

**Status:** Accepted (2026-04-17; reconstructed 2026-08-13)

## Context

Getting merged config changes onto a Home Assistant OS VM needs some
deployment mechanism, and HAOS is an appliance the operator would rather not
expose to inbound traffic. The chosen shape: an `automation` inside HA itself
(`gitops_sync_poll`) fires `shell_command.gitops_sync` on a `time_pattern`
trigger every 5 minutes, running `scripts/gitops-sync.sh` locally on the VM
(PRs #46 and #52, 2026-04-17). The script:

1. Takes a lock file, confirms it's on `main`, and fetches `origin/main`.
2. Exits silently if already up to date.
3. On divergence, resets the working tree to `origin/main`.
4. Validates via the Supervisor API (`POST /core/check`) before touching
   running state.
5. On success, smart-routes to the lightest reload the change set needs
   (lovelace → automation → script → scene → full restart, in ascending
   order of disruption) rather than always restarting HA Core.
6. On failure, rolls back to the pre-sync SHA and sends a failure
   notification — HA Core is never restarted on a failed check.

A related but distinct problem is the reverse direction: two flows
(`ha_version_sync` and `ha-context-sync`) need HA-side automation to open PRs
*against* this repo (a version-drift bump, and the 6-hourly `context/`
snapshot). Both use a `HA_SYNC_PAT` secret rather than the default
`GITHUB_TOKEN`, for two compounding reasons documented in `packages/README.md`
and mirrored in `.github/workflows/ha-context-sync.yml`: `GITHUB_TOKEN`-opened
PRs don't trigger downstream `pull_request`-gated workflows (`ha-config-check`,
`claude-code-review`) — an intentional anti-loop guard on GitHub's part — and
`github-actions[bot]` is denied push access to this repo's branches under the
branch-protection ruleset, so even the initial branch push needs a PAT with
write permission.

## Decision

**The deploy direction is pull-only.** HA polls GitHub for new commits on a
timer; nothing pushes into HA or calls it over the network to trigger a
deploy. The appliance never accepts an inbound deploy request. **Validate
before mutating, and always leave a way back:** `check_config` runs before
any reload, and a failed check rolls back the working tree instead of leaving
HA on a config it couldn't validate. **Reload no more than the change
warrants:** smart-routing to the lightest applicable reload avoids
restarting Core (which briefly disrupts everything) for changes that only
touch, say, a dashboard.

**The PR-opening direction uses a PAT, not the default token,** specifically
because those flows need their own PRs to trigger the same CI gates a
human-authored PR would — `HA_SYNC_PAT` is the credential that makes
`ha-version-sync` and `ha-context-sync` behave like first-class contributors
rather than second-class automation that silently bypasses review-gating CI.

## Alternatives

- **Recorded at the time (implicit in the chosen shape):** a push- or
  webhook-triggered deploy — GitHub Actions calls into HA (or a runner with
  network access to it) immediately on merge, instead of HA polling on a
  timer. Not documented as explicitly rejected, but the shape actually built
  is the pull model, and the repo's own reasoning for the reverse-direction
  `HA_SYNC_PAT` choice is written from a pull-first posture throughout.
- **Retrospective — not considered at the time:** push deploy over SSH or an
  inbound webhook, i.e. have CI reach into the HAOS VM to deploy directly.
  Worse on the axis this repo already optimizes for: it requires either
  exposing an inbound port/webhook receiver on the appliance or running a
  network-connected deploy runner with credentials to reach it, whereas the
  pull model needs no LAN-reachable runner and no inbound surface on HA at
  all — HA only ever makes outbound calls to GitHub, on its own timer.
- **Retrospective — not considered at the time:** use `GITHUB_TOKEN` for the
  reverse-direction PRs and accept that they don't trigger `claude-review`
  /`ha-config-check`, gating them with a separate, manually-triggered
  workflow instead. Lateral-to-worse — it avoids provisioning a PAT but
  reintroduces exactly the un-reviewed-merge risk the rest of this repo's
  CI-gating conventions exist to close, for the sake of not managing one
  more secret.

## Consequences

- Deploy latency is bounded but not instant: up to 5 minutes from merge to
  running config, plus however long `check_config` and the chosen reload
  take. `scripts/force-sync.sh` exists as an escape hatch (PR #329) for when
  a coordinated cross-layer change needs that window collapsed to seconds.
- A bad merge to `main` never reaches the running system uncontained — the
  worst case is a failed-check notification and an unchanged live config,
  not a broken HA Core.
- `HA_SYNC_PAT` is a standing secret with repo write access, held both in HA
  (`secrets.yaml` as `github_pat`) and in GitHub Actions secrets — broader
  privilege than `GITHUB_TOKEN` would carry, accepted specifically to keep
  automation-opened PRs subject to the same CI gates human PRs get.
- `scripts/gitops-sync.sh` and its reload-routing logic are now something
  every new config category (a new file type that needs its own reload
  service) has to be explicitly taught to the script, or it falls back to a
  full restart by default.
