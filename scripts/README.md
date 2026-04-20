# scripts/

Shell scripts executed by Home Assistant's `shell_command` integration.

## `gitops-sync.sh`

GitOps auto-deploy script. Called every 5 minutes by the `gitops_sync_poll` automation via `shell_command.gitops_sync`. Requires the `SUPERVISOR_TOKEN` environment variable (injected automatically by the HA shell_command integration).

### What it does

1. **Lock acquisition** — creates `.gitops-sync.lock` to prevent concurrent runs from overlapping polls
2. **Branch guard** — verifies the working tree is on `main` before touching anything; aborts if not
3. **Fetch** — runs `git fetch origin main`
4. **Drift check** — compares `HEAD` to `origin/main`; exits silently if already up to date (no-op polls produce no log entries)
5. **Reset** — `git reset --hard origin/main` applies the new commits
6. **Validate** — `POST /core/check` via Supervisor API; evaluates the HTTP response code
7. **On success** — routes to the lightest applicable reload:
   - Dashboard YAML changes only → `lovelace.reload_resources` + `frontend.reload_themes`
   - Automation changes → `automation.reload`
   - Script changes → `script.reload`
   - Scene changes → `scene.reload`
   - Any other config change → `core.restart`
   - Sends a success notification via the HA notify service
8. **On failure** — rolls back to the pre-sync SHA (`git reset --hard <pre-sync-sha>`), sends a failure notification; HA Core is never restarted on a failed check

### Operational details

- **Upper-bound deploy time:** 5 minutes from merge to running config
- **Log:** `/config/gitops-sync.log` — timestamped, leveled entries; rotates at 1 MB to `gitops-sync.log.1`
- **Disable:** toggle the `GitOps: Poll and deploy` automation off in Developer Tools
- **Force sync:** call `shell_command.gitops_sync` from Developer Tools → Services

### Why this approach

Polling from inside HA (rather than pushing from a GitHub Actions webhook) avoids exposing the HA instance to inbound internet traffic and sidesteps NAT traversal entirely. The tradeoff is a maximum 5-minute latency on deploys — acceptable for a home automation context. The Supervisor API validation step (`/core/check`) runs the same config validator as a normal HA startup, so a bad merge is caught before the service is disrupted.
