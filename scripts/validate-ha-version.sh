#!/usr/bin/env bash
#
# Validate an HA version string. Accepts a stable release (YYYY.MM.N) or a
# beta (YYYY.MM.NbN); rejects dev builds and anything else. On success the
# validated version is echoed to stdout so callers can capture it; on failure
# a message is written to stderr and the exit code is non-zero.
#
# Source of truth for the regex gating ha-version-sync.yml. The bats suite in
# tests/ sources this file (the BASH_SOURCE == $0 guard keeps the CLI body from
# running) and exercises validate_ha_version directly.
#
# Usage: validate-ha-version.sh <version>
set -euo pipefail

# Assigned to a variable and used unquoted in =~ — the portable way to apply a
# regex without quoting it into a literal string.
readonly HA_VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+(b[0-9]+)?$'

validate_ha_version() {
  [[ "$1" =~ $HA_VERSION_RE ]]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  version="${1-}"
  if ! validate_ha_version "$version"; then
    echo "Version '${version}' failed format check." \
         "Expected: YYYY.MM.N or YYYY.MM.NbN. Dev builds not supported." >&2
    exit 1
  fi
  printf '%s\n' "$version"
fi
