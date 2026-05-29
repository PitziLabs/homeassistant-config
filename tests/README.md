# tests/

Fast, dependency-light tests for the repo's shell logic. They run on a stock
Ubuntu runner with `shellcheck` + `bats` — **no Home Assistant instance and no
secrets required** — via the `Tests` workflow (`.github/workflows/tests.yml`).

This complements, rather than replaces, the existing gates:

| Gate | Scope |
|---|---|
| `YAML Lint` (`lint.yml`) | yamllint syntax/style across all YAML |
| `check-config` (`ha-config-check.yml`) | Real HA validates the proposed config |
| **`ShellCheck` (`tests.yml`)** | Static analysis of every `scripts/*.sh` |
| **`Bats` (`tests.yml`)** | Behavioral unit tests for shell logic |

## Running locally

```bash
sudo apt-get install -y shellcheck bats   # one-time
shellcheck scripts/*.sh
bats tests/
```

## What's covered

- **`apply_reload.bats`** — the smart-reload routing tree in
  `scripts/gitops-sync.sh` (`apply_reload`). This is the GitOps loop's decision
  about the lightest safe reload for a change set (dashboards → themes →
  automations → scripts → scenes → full restart, plus no-op and fallback cases).
  A bug here means a deploy silently doesn't take effect, or HA gets needlessly
  restarted. The function is pure path-matching with no HA dependency, so the
  suite sources the script and stubs its side-effecting helpers
  (`log` / `ha_call_service` / `ha_core_restart` / `ha_notify`) and `git diff`.

## Making a script testable

Scripts that self-execute at the bottom should guard that call so the file can
be sourced without side effects:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main_locked
fi
```

Sourcing then loads only the function definitions, letting a bats `setup()`
override the side-effecting helpers before calling the function under test.
