#!/usr/bin/env bash
#
# Validate a context-sync branch name: context-sync/YYYYMMDD-HHMMSS. This is the
# externally-supplied repository_dispatch payload that ha-context-sync.yml turns
# into a PR, so the pattern is a trust boundary — reject anything that isn't the
# exact timestamped form. On success the branch is echoed to stdout; on failure
# a message is written to stderr and the exit code is non-zero.
#
# Source of truth for the regex gating ha-context-sync.yml. The bats suite in
# tests/ sources this file (the BASH_SOURCE == $0 guard keeps the CLI body from
# running) and exercises validate_context_branch directly.
#
# Usage: validate-context-branch.sh <branch>
set -euo pipefail

readonly CONTEXT_BRANCH_RE='^context-sync/[0-9]{8}-[0-9]{6}$'

validate_context_branch() {
  [[ "$1" =~ $CONTEXT_BRANCH_RE ]]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  branch="${1-}"
  if ! validate_context_branch "$branch"; then
    echo "Invalid branch name pattern: '${branch}'." \
         "Expected: context-sync/YYYYMMDD-HHMMSS" >&2
    exit 1
  fi
  printf '%s\n' "$branch"
fi
