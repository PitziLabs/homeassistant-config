#!/usr/bin/env bats
#
# Tests for scripts/sync-kiosk-codesign.sh — regenerates kiosk-codesign.yaml as
# a mirror of kiosk.yaml. Codesign used to drift behind production (fixes landed
# in kiosk.yaml and were never back-ported), so the suite proves the generator
# mirrors body content verbatim, relabels only the first view's tab title/icon,
# and that --check is a real drift guard (passes in sync, fails on drift). Paths
# are redirected to a temp dir via KIOSK_SRC/KIOSK_DST so the real dashboards are
# never touched.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/sync-kiosk-codesign.sh"
  export KIOSK_SRC="${BATS_TEST_TMPDIR}/kiosk.yaml"
  export KIOSK_DST="${BATS_TEST_TMPDIR}/kiosk-codesign.yaml"
  cat > "$KIOSK_SRC" <<'EOF'
# kiosk source banner
views:
  - title: Home
    path: home
    icon: mdi:monitor-dashboard
    cards:
      - type: picture-entity
        entity: camera.front_door
        camera_view: snapshot
EOF
}

@test "writes a mirror with the auto-generated banner" {
  run bash "$SCRIPT" --write
  [ "$status" -eq 0 ]
  [[ "$output" == *"regenerated kiosk-codesign.yaml"* ]]
  grep -q "AUTO-GENERATED — DO NOT EDIT BY HAND." "$KIOSK_DST"
}

@test "relabels only the first view's title and icon" {
  bash "$SCRIPT" --write
  grep -q "^  - title: Co-design$" "$KIOSK_DST"
  grep -q "^    icon: mdi:monitor-edit$" "$KIOSK_DST"
  # production marker values must not survive in the mirror
  ! grep -q "^  - title: Home$" "$KIOSK_DST"
  ! grep -q "^    icon: mdi:monitor-dashboard$" "$KIOSK_DST"
}

@test "mirrors body content verbatim (camera fix carries over)" {
  bash "$SCRIPT" --write
  grep -q "camera_view: snapshot" "$KIOSK_DST"
  grep -q "entity: camera.front_door" "$KIOSK_DST"
}

@test "--check passes when codesign is in sync" {
  bash "$SCRIPT" --write
  run bash "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"in sync"* ]]
}

@test "--check fails when production has drifted ahead" {
  bash "$SCRIPT" --write
  printf '      - type: gauge\n' >> "$KIOSK_SRC"
  run bash "$SCRIPT" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"drifted"* ]]
}

@test "unknown argument is rejected" {
  run bash "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument"* ]]
}
