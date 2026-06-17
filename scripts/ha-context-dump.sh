#!/usr/bin/env bash
set -euo pipefail

readonly WORKTREE="/config/.context-mirror"
readonly CONTEXT_DIR="${WORKTREE}/context"
readonly REPO_OWNER="PitziLabs"
readonly REPO_NAME="homeassistant-config"
readonly SECRETS_FILE="/config/secrets.yaml"
readonly LOG_FILE="/config/ha-context-dump.log"
readonly LOG_MAX_BYTES=1048576
readonly STORAGE="/config/.storage"

# Display live-frame snapshot — fetched from snapshot-server on pve2. Hostname
# first, IP as fallback so the dump survives a transient mDNS hiccup. If both
# fail, the previous context/home-latest.png (if any) is retained — the
# rest of the dump continues normally.
readonly DISPLAY_SNAPSHOT_URL_HOST="http://pve2.local:9999/"
readonly DISPLAY_SNAPSHOT_URL_IP="http://192.168.139.7:9999/"
readonly DISPLAY_SNAPSHOT_TIMEOUT=8

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

# Read the items array from a storage-collection-style .storage file
# (shape: {data: {items: [...]}}). Emit [] if the file is absent so
# downstream artifacts are always well-formed and presence-stable.
storage_items() {
  local path="$1"
  if [[ -f "$path" ]]; then
    jq '.data.items // [] | sort_by(.id // "")' "$path"
  else
    printf '[]\n'
  fi
}

# --- Snapshot transforms ---------------------------------------------------
# Each build_* function takes its input path(s) and emits the artifact JSON on
# stdout. They are pure (no global state, no file writes) so the bats suite in
# tests/ can exercise them against fixtures without an HA instance.

# Project the entity registry down to the fields the snapshot exposes,
# dropping disabled entities and sorting by entity_id.
build_entities() {
  jq '
    .data.entities
    | map(select(.disabled_by == null))
    | map({
        entity_id: .entity_id,
        friendly_name: (.name // .original_name // null),
        area_id: .area_id,
        device_id: .device_id,
        platform: .platform,
        hidden: (.hidden_by != null)
      })
    | sort_by(.entity_id)
  ' "$1"
}

# Project the area registry to {area_id, name}, sorted by name.
build_areas() {
  jq '
    .data.areas
    | map({area_id: .id, name: .name})
    | sort_by(.name)
  ' "$1"
}

# Join devices against config_entries to resolve each device's integration
# domains. Args: <device_registry_path> <config_entries_path>.
build_devices() {
  jq -n \
    --slurpfile dev "$1" \
    --slurpfile cfg "$2" \
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
    '
}

# Assemble the combined helpers artifact — an object keyed by helper type, each
# value the storage_items array for that type. Arg: <storage_dir>.
build_helpers() {
  local storage_dir="$1"
  local helpers='{}'
  local helper_types=(
    input_boolean
    input_number
    input_text
    input_select
    input_datetime
    timer
    counter
    schedule
  )
  local t items
  for t in "${helper_types[@]}"; do
    items=$(storage_items "${storage_dir}/${t}")
    helpers=$(jq --argjson items "$items" --arg key "$t" '. + {($key): $items}' <<<"$helpers")
  done
  printf '%s\n' "$helpers"
}

# Assemble the storage-mode dashboards artifact: the dashboard registry plus the
# config blob for the default dashboard (.storage/lovelace) and any additional
# storage-mode dashboards (.storage/lovelace.<url_path>). Arg: <storage_dir>.
build_dashboards_storage() {
  local storage_dir="$1"
  local dashboards_registry
  dashboards_registry=$(storage_items "${storage_dir}/lovelace_dashboards")
  local configs='{}'
  if [[ -f "${storage_dir}/lovelace" ]]; then
    configs=$(jq --slurpfile lv "${storage_dir}/lovelace" \
      '. + {lovelace: ($lv[0].data.config // {})}' <<<"$configs")
  fi
  local f key
  shopt -s nullglob
  for f in "${storage_dir}"/lovelace.*; do
    key=$(basename "$f")
    configs=$(jq --slurpfile lv "$f" --arg key "$key" \
      '. + {($key): ($lv[0].data.config // {})}' <<<"$configs")
  done
  shopt -u nullglob
  jq -n --argjson dashboards "$dashboards_registry" --argjson configs "$configs" \
    '{dashboards: $dashboards, configs: $configs}'
}

# Fetch a live PNG snapshot of the pve2 display and write it to
# context/home-latest.png. Best-effort: tries hostname then IP with a
# short timeout, retains the previous file on failure, never aborts the
# dump. Writes to a tempfile and atomically moves on success so a partial
# download can't replace a good prior snapshot.
fetch_home_snapshot() {
  local out="${CONTEXT_DIR}/home-latest.png"
  local tmp="${out}.tmp.$$"
  local url
  for url in "$DISPLAY_SNAPSHOT_URL_HOST" "$DISPLAY_SNAPSHOT_URL_IP"; do
    if curl --fail --silent --show-error \
            --max-time "$DISPLAY_SNAPSHOT_TIMEOUT" \
            --output "$tmp" \
            "$url" 2>>"$LOG_FILE"; then
      # PNG magic check: first 4 bytes must be 89 50 4E 47. Read with xxd
      # if available, otherwise fall back to a size sanity check — real
      # display frames are hundreds of KB; error bodies are tens of bytes.
      local valid=false
      if command -v xxd >/dev/null 2>&1; then
        if [[ "$(xxd -p -l 4 "$tmp" 2>/dev/null)" == "89504e47" ]]; then
          valid=true
        fi
      else
        local sz
        sz=$(stat -c%s "$tmp" 2>/dev/null || echo 0)
        if (( sz > 10000 )); then
          valid=true
        fi
      fi
      if [[ "$valid" == true ]]; then
        mv "$tmp" "$out"
        log INFO "Display snapshot updated from $url"
        return 0
      fi
      log WARN "Display snapshot from $url did not look like PNG; discarding"
      rm -f "$tmp"
    fi
  done
  rm -f "$tmp"
  if [[ -f "$out" ]]; then
    log WARN "Display snapshot fetch failed; retaining previous home-latest.png"
  else
    log WARN "Display snapshot fetch failed; no previous file to retain"
  fi
  return 0
}

main() {
  rotate_log
  log INFO "Starting HA context dump"

  # One-time cleanup of Card A staging dir; remove after a few snapshots have run.
  if [[ -d /config/context-staging ]]; then
    rm -rf /config/context-staging
    log INFO "Removed legacy /config/context-staging/ directory"
  fi

  # Validate prerequisites
  if [[ ! -d "$WORKTREE" ]]; then
    log ERROR "Worktree not found at $WORKTREE — run: git worktree add /config/.context-mirror -b context-mirror main"
    exit 1
  fi
  if [[ ! -f "$SECRETS_FILE" ]]; then
    log ERROR "Secrets file not found at $SECRETS_FILE"
    exit 1
  fi
  for cmd in jq git curl; do
    if ! command -v "$cmd" &>/dev/null; then
      log ERROR "Required command not found: $cmd"
      exit 1
    fi
  done

  # Reset worktree to origin/main
  log INFO "Resetting worktree to origin/main"
  git -C "$WORKTREE" fetch origin main
  git -C "$WORKTREE" checkout -B context-mirror origin/main

  # Generate context files
  mkdir -p "$CONTEXT_DIR"

  log INFO "Building entities.json"
  build_entities "${STORAGE}/core.entity_registry" > "${CONTEXT_DIR}/entities.json"

  log INFO "Building areas.json"
  build_areas "${STORAGE}/core.area_registry" > "${CONTEXT_DIR}/areas.json"

  log INFO "Building devices.json"
  build_devices "${STORAGE}/core.device_registry" "${STORAGE}/core.config_entries" \
    > "${CONTEXT_DIR}/devices.json"

  log INFO "Copying automations-ui.yaml"
  cp /config/automations.yaml "${CONTEXT_DIR}/automations-ui.yaml"

  # Storage-mode scripts. The script integration is YAML-mode on this instance
  # (UI editor writes to /config/scripts.yaml), so .storage/script typically
  # does not exist and the artifact will be []. When the ha-mcp server begins
  # prototyping scripts into .storage/, this captures them automatically.
  log INFO "Building scripts.json"
  storage_items "${STORAGE}/script" > "${CONTEXT_DIR}/scripts.json"

  # Storage-mode scenes. Same caveat as scripts — scene integration is YAML-mode
  # by default (/config/scenes.yaml), so the artifact is typically [].
  log INFO "Building scenes.json"
  storage_items "${STORAGE}/scenes" > "${CONTEXT_DIR}/scenes.json"

  # Helpers — single combined artifact for reviewability. Each helper integration
  # uses its domain name as the storage key (e.g. .storage/input_boolean). The
  # output is an object keyed by helper type so a single jq query can list all
  # helpers of a given kind.
  log INFO "Building helpers.json"
  build_helpers "$STORAGE" > "${CONTEXT_DIR}/helpers.json"

  # Storage-mode Lovelace dashboards. The dashboard registry lives at
  # .storage/lovelace_dashboards; the default dashboard config is .storage/lovelace
  # and additional storage-mode dashboards are .storage/lovelace.<url_path>.
  # YAML-mode dashboards (this repo's home/homelab-status) are not stored
  # in .storage/ — they remain in dashboards/*.yaml and are absent here.
  log INFO "Building dashboards-storage.json"
  build_dashboards_storage "$STORAGE" > "${CONTEXT_DIR}/dashboards-storage.json"

  fetch_home_snapshot

  # Check for diff — most common case is no change
  if [[ -z "$(git -C "$WORKTREE" status --porcelain context/)" ]]; then
    log INFO "No changes since last snapshot; nothing to push"
    exit 0
  fi

  # Extract the full Authorization header value from secrets.yaml.
  # Secret format follows HA rest_command convention: "Bearer github_pat_xxx" stored
  # as a single quoted string so it can be used directly as a header value.
  GITHUB_AUTH=$(awk -F'"' '/^github_pat:/ {print $2}' "$SECRETS_FILE")
  if [[ -z "$GITHUB_AUTH" ]]; then
    log ERROR "Could not read github_pat from $SECRETS_FILE"
    exit 1
  fi

  # Derive the bare token (no "Bearer " prefix) for git push URL-embedded auth.
  # Git HTTPS push auth uses a different envelope than REST API auth — the URL
  # carries credentials directly, no Authorization header.
  GITHUB_TOKEN="${GITHUB_AUTH#Bearer }"
  if [[ "$GITHUB_TOKEN" == "$GITHUB_AUTH" ]]; then
    log ERROR "Secret value did not start with 'Bearer ' prefix — unexpected format"
    exit 1
  fi

  # Configure commit identity (worktree-scoped, not global)
  git -C "$WORKTREE" config user.name "ha-context-sync[bot]"
  git -C "$WORKTREE" config user.email "ha-context-sync@users.noreply.github.com"

  # Create branch, commit, push
  stamp=$(date -u +%Y%m%d-%H%M%S)
  branch="context-sync/${stamp}"
  git -C "$WORKTREE" checkout -b "$branch"
  git -C "$WORKTREE" add context/
  git -C "$WORKTREE" commit -m "context-snapshot: ${stamp}"
  # Use URL-embedded auth for git push. The extraheader approach (git -c http...extraheader=...)
  # is unreliable for push in git 2.52 — git drops the extraheader on auth challenge during
  # the receive-pack handshake. URL-embedded auth is what GitHub Actions uses internally.
  git -C "$WORKTREE" push \
    "https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO_OWNER}/${REPO_NAME}.git" \
    "$branch"

  log INFO "Pushed branch $branch"

  # Fire repository_dispatch
  payload=$(jq -n --arg branch "$branch" \
    '{event_type: "ha-context-report", client_payload: {branch: $branch}}')
  response_file=$(mktemp)
  trap 'rm -f "$response_file"' EXIT
  http_status=$(curl -s -o "$response_file" -w "%{http_code}" \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: ${GITHUB_AUTH}" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/dispatches" \
    -d "$payload")
  if [[ "$http_status" != "204" ]]; then
    log ERROR "Dispatch returned HTTP $http_status: $(head -c 200 "$response_file")"
    exit 1
  fi
  log INFO "Dispatch fired for $branch (HTTP 204)"
  log INFO "Snapshot pushed — context-snapshot PR will open shortly"
}

# Only self-execute when run directly, not when sourced for testing (the bats
# suite in tests/ sources this file to exercise the build_* transforms).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
