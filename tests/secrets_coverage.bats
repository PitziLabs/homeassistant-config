#!/usr/bin/env bats
#
# Guards the check-config gate against !secret drift.
#
# ha-config-check.yml copies secrets.fake.yaml -> secrets.yaml and validates the
# tree. If a YAML file gains a `!secret foo` reference whose key is absent from
# secrets.fake.yaml, check-config fails in CI with an opaque error. This test
# turns that into a fast, local, explicit failure naming the missing key(s).
#
# esphome/ is excluded: ESPHome firmware is not part of HA's check-config (it has
# its own secrets handling), so its !secret refs are out of scope here.

@test "every !secret reference in HA config is defined in secrets.fake.yaml" {
  local repo_root fake
  repo_root="${BATS_TEST_DIRNAME}/.."
  fake="${repo_root}/secrets.fake.yaml"
  [ -f "$fake" ]

  local refs
  mapfile -t refs < <(grep -rhoP '!secret\s+\K[A-Za-z0-9_]+' \
    --include='*.yaml' --exclude-dir=esphome --exclude-dir=.git \
    "$repo_root" | sort -u)

  # Guard: the scan must find at least one reference. A zero count means the
  # grep pattern broke, which would make this test vacuously pass.
  [ "${#refs[@]}" -gt 0 ]

  local key missing=()
  for key in "${refs[@]}"; do
    grep -qE "^${key}:" "$fake" || missing+=("$key")
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Keys referenced via !secret but missing from secrets.fake.yaml: ${missing[*]}" >&2
    return 1
  fi
}
