#!/usr/bin/env bats
#
# Tests for the two sync-workflow input validators:
#   scripts/validate-ha-version.sh     (gates ha-version-sync.yml)
#   scripts/validate-context-branch.sh (gates ha-context-sync.yml)
#
# These regexes guard what gets auto-committed (.ha-version) and which
# externally-supplied repository_dispatch branch gets turned into a PR — a trust
# boundary. They previously lived only inline in workflow YAML and ran only in
# production. The suite sources each script (the BASH_SOURCE == $0 guard keeps
# the CLI body from executing) to exercise the validator functions, and also
# drives the scripts as CLIs to lock in the exit code + stdout contract the
# workflows rely on.

setup() {
  HA_VER="${BATS_TEST_DIRNAME}/../scripts/validate-ha-version.sh"
  CTX_BR="${BATS_TEST_DIRNAME}/../scripts/validate-context-branch.sh"
  # shellcheck source=../scripts/validate-ha-version.sh
  source "$HA_VER"
  # shellcheck source=../scripts/validate-context-branch.sh
  source "$CTX_BR"
}

# --- validate_ha_version ---------------------------------------------------

@test "ha version: accepts stable releases and betas" {
  for v in 2026.5.1 2024.12.0 2026.6.0b3 1.0.0; do
    run validate_ha_version "$v"
    [ "$status" -eq 0 ] || { echo "should accept: $v"; return 1; }
  done
}

@test "ha version: rejects dev builds, prefixes, partials, and junk" {
  for v in "2026.5.1-dev" "v2026.5.1" "2026.5" "2026.5.1b" "1.2.3.4" \
           "2026.5.1 " " 2026.5.1" "2026.5.1; rm -rf /" "" "2026.05.1a"; do
    run validate_ha_version "$v"
    [ "$status" -ne 0 ] || { echo "should reject: '$v'"; return 1; }
  done
}

@test "ha version CLI: valid input echoes version and exits 0" {
  run "$HA_VER" "2026.5.1"
  [ "$status" -eq 0 ]
  [ "$output" = "2026.5.1" ]
}

@test "ha version CLI: invalid input exits non-zero with a message" {
  run "$HA_VER" "2026.5.1-dev"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed format check"* ]]
}

# --- validate_context_branch -----------------------------------------------

@test "context branch: accepts the timestamped form" {
  run validate_context_branch "context-sync/20260601-191918"
  [ "$status" -eq 0 ]
}

@test "context branch: rejects wrong shapes, separators, and traversal" {
  for b in "context-sync/2026601-191918" "context-sync/20260601_191918" \
           "context-sync/20260601-1919" "context-sync/20260601-191918extra" \
           "main" "../context-sync/20260601-191918" \
           "context-sync/20260601-191918/x" ""; do
    run validate_context_branch "$b"
    [ "$status" -ne 0 ] || { echo "should reject: '$b'"; return 1; }
  done
}

@test "context branch CLI: valid input echoes branch and exits 0" {
  run "$CTX_BR" "context-sync/20260601-191918"
  [ "$status" -eq 0 ]
  [ "$output" = "context-sync/20260601-191918" ]
}

@test "context branch CLI: invalid input exits non-zero with a message" {
  run "$CTX_BR" "main"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid branch name pattern"* ]]
}
