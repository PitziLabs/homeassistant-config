# packages/

HA [packages](https://www.home-assistant.io/docs/configuration/packages/) — self-contained YAML units that bundle related entities, automations, and services. Loaded via `!include_dir_named packages` in `configuration.yaml`, which merges each file's keys into the top-level config namespace.

## `ha_version_sync.yaml` — HA Version Sync

Automatically tracks the running HA version and opens a PR to update `.ha-version` when it drifts from the pinned CI value.

### Components

**`sensor.ha_core_version`** — `command_line` sensor reading `/config/.HA_VERSION` (HA's own runtime version file, distinct from the git-tracked `.ha-version` pin). Updated hourly. Provides a queryable entity for the running version; the startup dispatch is event-driven, not polled from this sensor.

**`rest_command.github_dispatch_version`** — POSTs a `ha-version-report` repository dispatch event to the GitHub API with `client_payload.version` set to the current HA version. Uses `!secret github_pat` (a PAT with `Contents: Write` on this repo).

**`automation.ha_version_sync_on_start`** — Fires on `homeassistant_started`, calls `rest_command.github_dispatch_version`. `mode: single` prevents duplicate dispatches on rapid-reboot bursts.

### How the full loop works

```
homeassistant_started
  → rest_command POSTs dispatch to GitHub API
  → ha-version-sync.yml workflow validates version format
  → compares incoming version to .ha-version on main
  → if equal: exits 0 (no-op)
  → if drift: creates ha-version-bump/<version> branch
               bumps .ha-version
               opens PR via HA_SYNC_PAT
  → PR triggers ha-config-check against the new version
  → auto-merge fires on check pass
```

### Why `HA_SYNC_PAT` instead of `GITHUB_TOKEN`

Two constraints force a PAT:

1. `GITHUB_TOKEN`-created PRs do not trigger other GitHub Actions workflows (intentional anti-loop guard). The version-bump PR needs to fire `ha-config-check` and the Claude review — both run on `pull_request` events. A PAT-opened PR bypasses this.
2. `actions/checkout` uses its `token:` input for all `git push` calls in the job. `github-actions[bot]` lacks write access to this repo under branch protection, so the push to the bump branch fails with 403 unless the PAT is substituted.

The same PAT lives in two places: `secrets.yaml` on the HA instance as `github_pat` (for the dispatch POST) and in repo Actions secrets as `HA_SYNC_PAT` (for checkout and PR creation).
