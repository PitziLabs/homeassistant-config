#!/usr/bin/env bats
#
# Tests for scripts/sync-home-codesign.sh — regenerates home-codesign.yaml as
# a mirror of home.yaml. Codesign used to drift behind production (fixes landed
# in home.yaml and were never back-ported), so the suite proves the generator
# mirrors body content verbatim, relabels the first view's tab title/icon and
# swaps its theme to Home Codesign, and that --check is a real drift guard
# (passes in sync, fails on drift). Paths
# are redirected to a temp dir via HOME_SRC/HOME_DST so the real dashboards are
# never touched.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/sync-home-codesign.sh"
  export HOME_SRC="${BATS_TEST_TMPDIR}/home.yaml"
  export HOME_DST="${BATS_TEST_TMPDIR}/home-codesign.yaml"
  cat > "$HOME_SRC" <<'EOF'
# home source banner
views:
  - title: Home
    path: home
    icon: mdi:monitor-dashboard
    theme: Home Polish
    cards:
      - type: picture-entity
        entity: camera.front_door
        camera_view: snapshot
EOF
}

@test "writes a mirror with the auto-generated banner" {
  run bash "$SCRIPT" --write
  [ "$status" -eq 0 ]
  [[ "$output" == *"regenerated home-codesign.yaml"* ]]
  grep -q "AUTO-GENERATED — DO NOT EDIT BY HAND." "$HOME_DST"
}

@test "relabels only the first view's title and icon" {
  bash "$SCRIPT" --write
  grep -q "^  - title: Co-design$" "$HOME_DST"
  grep -q "^    icon: mdi:monitor-edit$" "$HOME_DST"
  # production marker values must not survive in the mirror
  ! grep -q "^  - title: Home$" "$HOME_DST"
  ! grep -q "^    icon: mdi:monitor-dashboard$" "$HOME_DST"
}

@test "swaps the sandbox view theme to Home Codesign" {
  bash "$SCRIPT" --write
  grep -q "^    theme: Home Codesign$" "$HOME_DST"
  # production theme must not survive in the mirror
  ! grep -q "^    theme: Home Polish$" "$HOME_DST"
}

@test "mirrors body content verbatim (camera fix carries over)" {
  bash "$SCRIPT" --write
  grep -q "camera_view: snapshot" "$HOME_DST"
  grep -q "entity: camera.front_door" "$HOME_DST"
}

@test "--check passes when codesign is in sync" {
  bash "$SCRIPT" --write
  run bash "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"in sync"* ]]
}

@test "--check fails when production has drifted ahead" {
  bash "$SCRIPT" --write
  printf '      - type: gauge\n' >> "$HOME_SRC"
  run bash "$SCRIPT" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"drifted"* ]]
}

@test "unknown argument is rejected" {
  run bash "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument"* ]]
}
