#!/usr/bin/env bats
#
# Tests for scripts/force-sync.sh — the helper that collapses the cross-layer
# latency windows by firing an immediate gitops deploy and context snapshot.
# The service calls are side effects, so the suite sources the script (the
# BASH_SOURCE == $0 guard keeps the CLI body from running), stubs ha_call_service
# to record invocations, and asserts force_sync fires both services in the right
# order. The CLI guard (refusing to run without SUPERVISOR_TOKEN) is checked
# end-to-end.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/force-sync.sh"
  # shellcheck source=../scripts/force-sync.sh
  source "$SCRIPT"
  CALLS_FILE="${BATS_TEST_TMPDIR}/calls"
  : > "$CALLS_FILE"
  ha_call_service() { printf '%s %s %s\n' "$1" "$2" "${3:-}" >> "$CALLS_FILE"; }
  export CALLS_FILE
}

@test "force_sync deploys (gitops) before reconciling the snapshot (dump button)" {
  run force_sync
  [ "$status" -eq 0 ]
  # gitops deploy fires first…
  [ "$(sed -n '1p' "$CALLS_FILE")" = "shell_command gitops_sync " ]
  # …then the context dump button press
  [[ "$(sed -n '2p' "$CALLS_FILE")" == "input_button press "*"ha_context_dump_now"* ]]
}

@test "CLI refuses to run without SUPERVISOR_TOKEN" {
  run env -u SUPERVISOR_TOKEN bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SUPERVISOR_TOKEN is not set"* ]]
}
