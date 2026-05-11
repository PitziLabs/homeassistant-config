#!/usr/bin/env bash
set -euo pipefail

readonly LOG_FILE="/config/ha-context-dump.log"
readonly LOG_MAX_BYTES=1048576
readonly STAGING_DIR="/config/context-staging"
readonly SUPERVISOR_BASE="http://supervisor"
readonly STORAGE="/config/.storage"

log() {
  local level="$1"
  shift
  local ts line
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  line="[$ts] [$level] $*"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >> "$LOG_FILE"
}

rotate_log() {
  if [[ -f "$LOG_FILE" ]]; then
    local size
    size=$(stat -c%s "$LOG_FILE")
    if (( size >= LOG_MAX_BYTES )); then
      mv "$LOG_FILE" "${LOG_FILE}.1"
    fi
  fi
}

main() {
  rotate_log
  log INFO "Starting HA context dump"

  if [[ -z "${SUPERVISOR_TOKEN:-}" ]]; then
    log ERROR "SUPERVISOR_TOKEN is not set — HA must expose it to shell_command context"
    log ERROR "See: https://www.home-assistant.io/integrations/shell_command/"
    exit 1
  fi

  mkdir -p "$STAGING_DIR"

  # Fetch live states for friendly_name resolution
  local states_file
  states_file=$(mktemp)
  trap 'rm -f "${states_file}"' EXIT

  log INFO "Fetching live entity states via Supervisor API"
  if ! curl -sf \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    "${SUPERVISOR_BASE}/core/api/states" \
    -o "$states_file"; then
    log ERROR "Failed to fetch states from Supervisor API"
    exit 1
  fi

  # entities.json: non-disabled entities with friendly_name from live state
  log INFO "Building entities.json"
  jq -n \
    --slurpfile reg "${STORAGE}/core.entity_registry" \
    --slurpfile states "${states_file}" \
    '
    ($states[0] | map({(.entity_id): .attributes.friendly_name}) | add // {}) as $state_names |
    $reg[0].data.entities
    | map(select(.disabled_by == null))
    | map({
        entity_id: .entity_id,
        friendly_name: ($state_names[.entity_id] // .name // .original_name // null),
        area_id: .area_id,
        device_id: .device_id,
        platform: .platform,
        hidden: (.hidden_by != null)
      })
    | sort_by(.entity_id)
    ' > "${STAGING_DIR}/entities.json"

  # areas.json: area_id + name, sorted by name
  log INFO "Building areas.json"
  jq '
    .data.areas
    | map({area_id: .id, name: .name})
    | sort_by(.name)
  ' "${STORAGE}/core.area_registry" > "${STAGING_DIR}/areas.json"

  # devices.json: device metadata with resolved integration domains
  log INFO "Building devices.json"
  jq -n \
    --slurpfile dev "${STORAGE}/core.device_registry" \
    --slurpfile cfg "${STORAGE}/core.config_entries" \
    '
    ($cfg[0].data.entries | map({(.entry_id): .domain}) | add // {}) as $entry_domains |
    $dev[0].data.devices
    | map({
        device_id: .id,
        name: (.name_by_user // .name // null),
        manufacturer: .manufacturer,
        model: .model,
        area_id: .area_id,
        integrations: (.config_entries | map($entry_domains[.]) | map(select(. != null)) | unique)
      })
    | sort_by(.name // "")
    ' > "${STAGING_DIR}/devices.json"

  # automations-ui.yaml: byte-for-byte copy
  log INFO "Copying automations-ui.yaml"
  cp /config/automations.yaml "${STAGING_DIR}/automations-ui.yaml"

  log INFO "Dump complete — four files written to ${STAGING_DIR}/"
}

main
