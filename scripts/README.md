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
   Authorization header values (see *Script auth conventions* below).
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

## `validate-ha-version.sh` / `validate-context-branch.sh`

Tiny input validators used by the sync workflows, factored out of inline
workflow YAML so the regexes have a single source of truth that CI can test.

- `validate-ha-version.sh <version>` — accepts a stable (`YYYY.MM.N`) or beta
  (`YYYY.MM.NbN`) HA version, rejects everything else; echoes the validated
  version on success. Called by `ha-version-sync.yml` before it commits
  `.ha-version`.
- `validate-context-branch.sh <branch>` — accepts only
  `context-sync/YYYYMMDD-HHMMSS`. The branch is an externally-supplied
  `repository_dispatch` payload that `ha-context-sync.yml` turns into a PR, so
  this is a trust boundary. Echoes the branch on success.

Both expose a sourceable function (`validate_ha_version` /
`validate_context_branch`) guarded by `BASH_SOURCE == $0`, exercised by
`tests/validate_inputs.bats`. Because the workflows now call these scripts, they
checkout the repo *before* validating the payload (an early checkout for an
invalid payload is the only behavioral change; the payload isn't used in
checkout, so there's no security impact).

## Script auth conventions

Three conventions learned the hard way during context-sync work. Future scripts
that talk to GitHub or the HA Supervisor from inside the HA Core container
should follow these without re-deriving them.

### `secrets.yaml` stores complete Authorization header values

The `github_pat` secret in `/config/secrets.yaml` is stored as the **full
Authorization header value**, including the auth scheme prefix:

    github_pat: "Bearer github_pat_xxxxxxxxxx..."

This is the HA `rest_command` integration convention — it allows direct use as
`headers: { authorization: !secret github_pat }` in rest_command definitions
(see `packages/ha_version_sync.yaml` for the canonical example).

Bash scripts consuming this secret should extract the quoted value cleanly:

    GITHUB_AUTH=$(awk -F'"' '/^github_pat:/ {print $2}' /config/secrets.yaml)

The naive `awk '{print $2}'` (whitespace-split, no quote awareness) returns
`"Bearer` — the opening quote plus the scheme word. It's non-empty (passes
naive checks) but unusable. Always use `-F'"'`.

When a bare token is needed (e.g., for git URL-embedded auth), strip the prefix:

    GITHUB_TOKEN="${GITHUB_AUTH#Bearer }"

### Git HTTPS push needs URL-embedded credentials, not extraheader

For `git push` over HTTPS from inside the Core container, use URL-embedded auth:

    git -C "$WORKTREE" push \
        "https://x-access-token:${GITHUB_TOKEN}@github.com/${OWNER}/${REPO}.git" \
        "$branch"

**Do not use** the `git -c http.extraheader=...` or
`git -c http.<url>.extraheader=...` patterns for push. They work for fetch and
`ls-remote` but git 2.52 drops the extraheader on the auth challenge during the
receive-pack handshake, falling back to credential helper or interactive prompt
— which has no terminal in shell_command context, so it hangs.

The URL-embedded form is what GitHub Actions uses internally for its own git
operations. It puts the bare token briefly in `ps` output, but on a single-user
HAOS VM this is acceptable. The push is one-shot — the URL is constructed inline,
not persisted to git config; `git remote -v` continues to show only the bare
HTTPS origin URL afterward.

### GitHub REST API uses Bearer auth (the stored format works as-is)

For curl calls to `api.github.com` endpoints (firing `repository_dispatch`,
checking PR state, etc.), use the full stored value directly as the
Authorization header:

    curl -H "Authorization: ${GITHUB_AUTH}" \
        https://api.github.com/repos/${OWNER}/${REPO}/dispatches \
        ...

No prefix manipulation — the `Bearer ` is already in the value. Adding
`token ` or `Bearer ` prefixes in the script produces malformed headers.

### Public-repo `ls-remote` is not a valid auth test

`git ls-remote https://github.com/<owner>/<public-repo>.git HEAD` succeeds
anonymously — GitHub serves refs for public repos without authentication. If
you're testing whether a PAT works for git operations, the only valid test is
an authenticated operation that the public-anonymous path can't satisfy:

- A push (`git push ...`)
- A REST API call requiring auth (e.g., `GET /user`, `GET /repos/.../dispatches`
  with a body)
- A clone of a private repo

Don't conclude auth works just because `ls-remote` returns a SHA.
