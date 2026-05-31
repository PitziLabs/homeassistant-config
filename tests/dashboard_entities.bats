#!/usr/bin/env bats
#
# Tests for scripts/check-dashboard-entities.py — the dashboard entity-reference
# checker. Dashboards reference entities by ID, which HA does not validate at
# config-check time, so a typo renders a silent blank/unavailable card. The
# checker cross-references those IDs against the entity snapshot; this suite
# proves it actually catches a bad reference, honors the allowlist, ignores
# templated values, and flags a stale allowlist entry.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/check-dashboard-entities.py"
  FIX="${BATS_TEST_DIRNAME}/fixtures/dashboards"
  DASH="${FIX}/sample.yaml"
  ENT="${FIX}/entities.json"
}

check() {  # check <args...> -> populates $output / $status
  run python3 "$SCRIPT" --entities "$ENT" "$@"
}

@test "flags references absent from the snapshot" {
  check "$DASH"
  [ "$status" -eq 0 ]                       # non-strict: report only
  [[ "$output" == *"light.bogus"* ]]
  [[ "$output" == *"switch.bogus2"* ]]
}

@test "resolves real references (entity, entities list, entity_id list)" {
  check "$DASH"
  # light.real (entity + entities-list) and switch.real (entity_id list) resolve
  [[ "$output" != *"light.real"* ]]
  [[ "$output" != *"switch.real"* ]]
}

@test "ignores templated entity values" {
  check "$DASH"
  [[ "$output" != *"light.templated"* ]]
}

@test "--strict exits non-zero when unknown references exist" {
  check --strict "$DASH"
  [ "$status" -eq 1 ]
}

@test "--allowlist exempts listed entities and restores a clean strict pass" {
  allow="${BATS_TEST_TMPDIR}/allow.txt"
  printf '%s\n' "light.bogus" "switch.bogus2 # pending" > "$allow"
  check --strict --allowlist "$allow" "$DASH"
  [ "$status" -eq 0 ]
}

@test "stale allowlist entries (now in snapshot) are reported for pruning" {
  allow="${BATS_TEST_TMPDIR}/allow.txt"
  printf '%s\n' "light.bogus" "switch.bogus2" "light.real" > "$allow"
  check --strict --allowlist "$allow" "$DASH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"can be removed"* ]]
  [[ "$output" == *"light.real"* ]]
}
