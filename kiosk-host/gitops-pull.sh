#!/usr/bin/env bash
# Pull the kiosk-host artifacts from origin/main and re-deploy them
# if the in-repo copy drifts from what's installed on this host.
#
# Mirrors the spirit of the HA-side scripts/gitops-sync.sh: timestamped
# leveled log with in-script rotation, flock against concurrent runs,
# branch guard, validation before install, and a no-op fast path so the
# kiosk doesn't restart on every poll.
#
# Intended invocation: oneshot systemd service driven by a 5-min timer
# (see gitops-pull.service / gitops-pull.timer in this directory).

set -euo pipefail

readonly REPO_DIR="/opt/homeassistant-config"
readonly REPO_SUBDIR="kiosk-host"
readonly LOCK_FILE="/run/dashboard-kiosk-gitops.lock"
readonly LOG_FILE="/var/log/dashboard-kiosk-gitops.log"
readonly LOG_MAX_BYTES=1048576

readonly SCRIPT_SRC="${REPO_DIR}/${REPO_SUBDIR}/dashboard-kiosk.sh"
readonly SCRIPT_DST="/usr/local/bin/dashboard-kiosk.sh"
readonly UNIT_SRC="${REPO_DIR}/${REPO_SUBDIR}/dashboard-kiosk.service"
readonly UNIT_DST="/etc/systemd/system/dashboard-kiosk.service"
readonly HELPER_SRC="${REPO_DIR}/${REPO_SUBDIR}/kiosk-show"
readonly HELPER_DST="/usr/local/bin/kiosk-show"
readonly SNAP_SRC="${REPO_DIR}/${REPO_SUBDIR}/snapshot-server"
readonly SNAP_DST="/usr/local/bin/snapshot-server"
readonly SNAP_UNIT_SRC="${REPO_DIR}/${REPO_SUBDIR}/snapshot-server.service"
readonly SNAP_UNIT_DST="/etc/systemd/system/snapshot-server.service"
readonly KIOSK_UNIT="dashboard-kiosk.service"
readonly SNAP_UNIT="snapshot-server.service"

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

  if [[ ! -d "${REPO_DIR}/.git" ]]; then
    log ERROR "Repo not found at ${REPO_DIR}. Bootstrap with: git clone https://github.com/PitziLabs/homeassistant-config.git ${REPO_DIR}"
    exit 1
  fi

  cd "$REPO_DIR"

  local current_branch
  current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)
  if [[ "$current_branch" != "main" ]]; then
    log ERROR "Expected branch 'main', got '${current_branch}'. Aborting to avoid deploying wrong branch."
    exit 1
  fi

  if ! git fetch --quiet origin main; then
    log ERROR "git fetch failed — check network or DNS"
    exit 1
  fi

  local rollback_sha remote_sha
  rollback_sha=$(git rev-parse HEAD)
  remote_sha=$(git rev-parse origin/main)

  if [[ "$rollback_sha" != "$remote_sha" ]]; then
    log INFO "Updating ${rollback_sha:0:7} → ${remote_sha:0:7}"
    git reset --hard --quiet origin/main
  fi

  # Validate before installing so a syntax-broken commit can't put the
  # kiosk into a crash loop.
  if ! bash -n "$SCRIPT_SRC"; then
    log ERROR "dashboard-kiosk.sh failed syntax check; refusing to install"
    exit 1
  fi
  if ! bash -n "$HELPER_SRC"; then
    log ERROR "kiosk-show failed syntax check; refusing to install"
    exit 1
  fi
  if ! python3 -m py_compile "$SNAP_SRC" 2>/dev/null; then
    log ERROR "snapshot-server failed python syntax check; refusing to install"
    exit 1
  fi
  if ! systemd-analyze verify "$UNIT_SRC" 2>/dev/null; then
    log ERROR "dashboard-kiosk.service failed systemd-analyze verify; refusing to install"
    exit 1
  fi
  if ! systemd-analyze verify "$SNAP_UNIT_SRC" 2>/dev/null; then
    log ERROR "snapshot-server.service failed systemd-analyze verify; refusing to install"
    exit 1
  fi

  local script_changed=false unit_changed=false helper_changed=false
  local snap_changed=false snap_unit_changed=false
  if ! cmp -s "$SCRIPT_SRC" "$SCRIPT_DST"; then
    script_changed=true
  fi
  if ! cmp -s "$UNIT_SRC" "$UNIT_DST"; then
    unit_changed=true
  fi
  if ! cmp -s "$HELPER_SRC" "$HELPER_DST"; then
    helper_changed=true
  fi
  if ! cmp -s "$SNAP_SRC" "$SNAP_DST"; then
    snap_changed=true
  fi
  if ! cmp -s "$SNAP_UNIT_SRC" "$SNAP_UNIT_DST"; then
    snap_unit_changed=true
  fi

  if [[ "$script_changed" == false && "$unit_changed" == false \
        && "$helper_changed" == false && "$snap_changed" == false \
        && "$snap_unit_changed" == false ]]; then
    log INFO "no-op, deployed copy matches ${remote_sha:0:7}"
    exit 0
  fi

  if [[ "$script_changed" == true ]]; then
    log INFO "Installing dashboard-kiosk.sh → ${SCRIPT_DST}"
    install -m 0755 -o root -g root "$SCRIPT_SRC" "$SCRIPT_DST"
  fi
  if [[ "$unit_changed" == true ]]; then
    log INFO "Installing dashboard-kiosk.service → ${UNIT_DST}"
    install -m 0644 -o root -g root "$UNIT_SRC" "$UNIT_DST"
  fi
  if [[ "$helper_changed" == true ]]; then
    log INFO "Installing kiosk-show → ${HELPER_DST}"
    install -m 0755 -o root -g root "$HELPER_SRC" "$HELPER_DST"
  fi
  if [[ "$snap_changed" == true ]]; then
    log INFO "Installing snapshot-server → ${SNAP_DST}"
    install -m 0755 -o root -g root "$SNAP_SRC" "$SNAP_DST"
  fi
  if [[ "$snap_unit_changed" == true ]]; then
    log INFO "Installing snapshot-server.service → ${SNAP_UNIT_DST}"
    install -m 0644 -o root -g root "$SNAP_UNIT_SRC" "$SNAP_UNIT_DST"
  fi

  # Daemon-reload once if any unit drifted.
  if [[ "$unit_changed" == true || "$snap_unit_changed" == true ]]; then
    systemctl daemon-reload
  fi

  # Helper-only changes don't affect the running display; skip the
  # display restart so a kiosk-show update doesn't flicker the screen.
  if [[ "$script_changed" == true || "$unit_changed" == true ]]; then
    log INFO "Restarting ${KIOSK_UNIT}"
    systemctl restart "$KIOSK_UNIT"
  fi

  # snapshot-server is PartOf dashboard-kiosk.service, so a kiosk restart
  # will have already stopped it. Either way, restart on drift to pick up
  # changes; enable in case it's not enabled yet (idempotent).
  if [[ "$snap_changed" == true || "$snap_unit_changed" == true \
        || "$script_changed" == true || "$unit_changed" == true ]]; then
    systemctl enable --now "$SNAP_UNIT" >/dev/null 2>&1 || true
    log INFO "Restarting ${SNAP_UNIT}"
    systemctl restart "$SNAP_UNIT"
  fi

  log INFO "Deployed ${remote_sha:0:7}"
}

main_locked() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    exit 0
  fi
  main
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main_locked
fi
