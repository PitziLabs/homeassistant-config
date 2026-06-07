#!/usr/bin/env bash
#
# sync-kiosk-codesign.sh — regenerate dashboards/kiosk-codesign.yaml as a
# mirror of dashboards/kiosk.yaml.
#
# The co-design dashboard (/dashboard-kiosk-codesign/home) is a preview copy
# of the production kiosk (/dashboard-kiosk/home). It used to drift: fixes
# landed in kiosk.yaml and never got back-ported, so a stale codesign sat
# behind production (e.g. the Nest cam stuck on camera_view: live after the
# snapshot fix shipped). This script makes production the single source of
# truth — codesign is generated, never hand-edited.
#
# The only intentional difference is the first view's tab title/icon, swapped
# to a "Co-design" marker so the preview is visually distinguishable. Every
# card, template, and entity reference is identical to production.
#
# Usage:
#   sync-kiosk-codesign.sh            Regenerate codesign in place (default).
#   sync-kiosk-codesign.sh --write    Same as default; explicit.
#   sync-kiosk-codesign.sh --check    Exit non-zero if codesign has drifted
#                                     from kiosk.yaml (used by CI). No writes.
#   sync-kiosk-codesign.sh --help     This message.
#
# Paths can be overridden for testing via KIOSK_SRC / KIOSK_DST.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SRC="${KIOSK_SRC:-${REPO_ROOT}/dashboards/kiosk.yaml}"
DST="${KIOSK_DST:-${REPO_ROOT}/dashboards/kiosk-codesign.yaml}"

usage() { sed -n '17,24p' "$0" | sed 's/^# \{0,1\}//'; }

# Emit the generated codesign dashboard to stdout: a "do not edit" banner
# followed by kiosk.yaml with the first view's tab title/icon relabeled.
# The sed substitutions are anchored to the unique view-header lines; if a
# future kiosk.yaml renames that view, the content still mirrors correctly,
# only the cosmetic marker is dropped.
generate() {
  cat <<'EOF'
# =================================================================
# AUTO-GENERATED — DO NOT EDIT BY HAND.
# Mirror of dashboards/kiosk.yaml, produced by
# scripts/sync-kiosk-codesign.sh. Edit kiosk.yaml, then run that
# script to refresh this file. CI (Tests > Codesign Sync) fails if
# this file drifts from production.
#
# Purpose: preview kiosk changes at /dashboard-kiosk-codesign/home
# without touching the household monitor (/dashboard-kiosk/home).
# Preview with:
#   kiosk-host/kiosk-preview dashboards/kiosk-codesign.yaml \
#     --url http://homeassistant.local:8123/dashboard-kiosk-codesign/home
#
# Only the first view's tab title/icon differ from production; all
# cards, templates, and entity references are identical.
EOF
  sed -e 's|^  - title: Home$|  - title: Co-design|' \
      -e 's|^    icon: mdi:monitor-dashboard$|    icon: mdi:monitor-edit|' \
      "$SRC"
}

mode="write"
case "${1:-}" in
  --check) mode="check" ;;
  --write | "") mode="write" ;;
  -h | --help) usage; exit 0 ;;
  *) echo "sync-kiosk-codesign.sh: unknown argument: $1" >&2; exit 2 ;;
esac

if [[ ! -r "$SRC" ]]; then
  echo "sync-kiosk-codesign.sh: source not readable: $SRC" >&2
  exit 2
fi

if [[ "$mode" == "check" ]]; then
  if diff -u "$DST" <(generate); then
    echo "kiosk-codesign.yaml is in sync with kiosk.yaml"
  else
    echo "" >&2
    echo "kiosk-codesign.yaml has drifted from kiosk.yaml." >&2
    echo "Run: scripts/sync-kiosk-codesign.sh" >&2
    exit 1
  fi
else
  generate > "$DST"
  echo "regenerated $(basename "$DST") from $(basename "$SRC")"
fi
