#!/usr/bin/env bash
#
# Collapse the cross-layer latency windows on demand. Triggers an immediate
# gitops deploy (instead of waiting for the 5-minute poll) and an immediate
# context snapshot (instead of the 6-hour dump), so a coordinated LIVE+INTENT
# change reconciles in seconds rather than minutes/hours.
#
# Runs inside the HA Core container, where SUPERVISOR_TOKEN is injected — same
# auth pattern as gitops-sync.sh. See docs/cross-layer-changes.md for when to
# reach for this (step 3/4 of the rename recipe).
#
# Usage: force-sync.sh
set -euo pipefail

readonly SUPERVISOR_BASE="${SUPERVISOR_BASE:-http://supervisor}"

# Call a HA service through the Supervisor's Core API proxy.
# Args: <domain> <service> [json_data]
ha_call_service() {
  local domain="$1" service="$2" data="${3:-}"
  [[ -z "$data" ]] && data='{}'
  curl -fsS -X POST \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$data" \
    "${SUPERVISOR_BASE}/core/api/services/${domain}/${service}"
}

# Deploy INTENT now, then reconcile the SNAPSHOT. Deploy first so the snapshot
# that follows reflects the just-deployed YAML as well as the live registry.
force_sync() {
  echo "[force-sync] Triggering immediate gitops deploy (shell_command.gitops_sync)…"
  ha_call_service shell_command gitops_sync >/dev/null

  echo "[force-sync] Triggering immediate context snapshot (input_button.ha_context_dump_now)…"
  ha_call_service input_button press '{"entity_id":"input_button.ha_context_dump_now"}' >/dev/null

  echo "[force-sync] Both fired. Watch /config/gitops-sync.log and" \
       "/config/ha-context-dump.log for results."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ -z "${SUPERVISOR_TOKEN:-}" ]]; then
    echo "error: SUPERVISOR_TOKEN is not set — run inside the HA Core container." >&2
    exit 1
  fi
  force_sync
fi
