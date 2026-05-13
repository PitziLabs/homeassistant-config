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

## `import-home-to-storage.sh`

One-shot helper that copies the git-managed `dashboards/home.yaml` into a
storage-mode (UI-managed) Lovelace dashboard at `url_path: home-ui`. After it
runs, the next `ha-context-dump.sh` snapshot picks the dashboard up in
`context/dashboards-storage.json`, which makes it visible to assistants
working against `context/`.

Must run inside the HA Core container (Python 3, `aiohttp`, and `PyYAML` are
part of Core's runtime; the SSH add-on's Alpine shell has none of them):

```bash
docker exec homeassistant /config/scripts/import-home-to-storage.sh
```

### Authentication

Core's websocket auth does NOT accept `SUPERVISOR_TOKEN` in current HA
versions (that token is for outbound Core-to-Supervisor calls, not inbound
Core API). A long-lived access token is required:

1. In the HA UI: profile avatar (bottom-left) → **Security** tab →
   **Long-Lived Access Tokens** → **Create Token** → copy the value (shown
   only once).
2. Add it to `/config/secrets.yaml` so future runs need no env flag:
   ```yaml
   ha_token: "Bearer <paste-the-token-here>"
   ```
   The `Bearer ` prefix matches the project convention for stored
   Authorization header values (see CLAUDE.md > "Script auth conventions").
   The script strips the prefix before sending to the websocket.

The script resolves the token in this order: `HA_TOKEN` env var → `ha_token`
in `secrets.yaml` → `SUPERVISOR_TOKEN` (last-resort fallback that will
almost certainly fail). For a one-shot run without modifying `secrets.yaml`:

```bash
docker exec -e HA_TOKEN='<paste-token-here>' homeassistant /config/scripts/import-home-to-storage.sh
```

### Overrides and behavior

Env vars: `SOURCE_YAML`, `URL_PATH`, `TITLE`, `ICON`, `HA_WS_URL`,
`SECRETS_YAML`, `HA_TOKEN`. Idempotent — re-running overwrites the saved
config but does not duplicate the registry entry. The git-managed
`dashboards/home.yaml` and its `lovelace.dashboards` registration in
`configuration.yaml` are left in place; both dashboards coexist
(`/dashboard-home/home` from YAML, `/home-ui` from storage) until cutover
is decided.
