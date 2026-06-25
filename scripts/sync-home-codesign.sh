#!/usr/bin/env bash
#
# sync-home-codesign.sh — regenerate dashboards/home-codesign.yaml as a
# mirror of dashboards/home.yaml.
#
# The co-design dashboard (/dashboard-home-codesign/home) is a preview copy
# of the production home dashboard (/dashboard-home/home). It used to drift: fixes
# landed in home.yaml and never got back-ported, so a stale codesign sat
# behind production (e.g. the Nest cam stuck on camera_view: live after the
# snapshot fix shipped). This script makes production the single source of
# truth — codesign is generated, never hand-edited.
#
# The intentional differences are cosmetic only: the first view's tab
# title/icon are swapped to a "Co-design" marker, and its theme is swapped
# from "Home Polish" to "Home Codesign" so the sandbox renders the
# instrument-panel design study (themes/home_codesign.yaml) without forking
# the cards. Every card, template, and entity reference is identical to
# production.
#
# Usage:
#   sync-home-codesign.sh            Regenerate codesign in place (default).
#   sync-home-codesign.sh --write    Same as default; explicit.
#   sync-home-codesign.sh --check    Exit non-zero if codesign has drifted
#                                     from home.yaml (used by CI). No writes.
#   sync-home-codesign.sh --help     This message.
#
# Paths can be overridden for testing via HOME_SRC / HOME_DST.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SRC="${HOME_SRC:-${REPO_ROOT}/dashboards/home.yaml}"
DST="${HOME_DST:-${REPO_ROOT}/dashboards/home-codesign.yaml}"

usage() { sed -n '17,24p' "$0" | sed 's/^# \{0,1\}//'; }

# Emit the generated codesign dashboard to stdout: a "do not edit" banner
# followed by home.yaml with the first view's tab title/icon relabeled.
# The sed substitutions are anchored to the unique view-header lines; if a
# future home.yaml renames that view, the content still mirrors correctly,
# only the cosmetic marker is dropped.
generate() {
  cat <<'EOF'
# =================================================================
# AUTO-GENERATED — DO NOT EDIT BY HAND.
# Mirror of dashboards/home.yaml, produced by
# scripts/sync-home-codesign.sh. Edit home.yaml, then run that
# script to refresh this file. CI (Tests > Codesign Sync) fails if
# this file drifts from production.
#
# Purpose: preview home changes at /dashboard-home-codesign/home
# without touching the live dashboard (/dashboard-home/home).
# Open http://homeassistant.local:8123/dashboard-home-codesign/home
# in the HA web UI or companion app to preview.
#
# Only the first view's tab title/icon and theme differ from production;
# all cards, templates, and entity references are identical.
EOF
  sed -e 's|^  - title: Home$|  - title: Co-design|' \
      -e 's|^    icon: mdi:monitor-dashboard$|    icon: mdi:monitor-edit|' \
      -e 's|^    theme: Home Polish$|    theme: Home Codesign|' \
      "$SRC"
}

mode="write"
case "${1:-}" in
  --check) mode="check" ;;
  --write | "") mode="write" ;;
  -h | --help) usage; exit 0 ;;
  *) echo "sync-home-codesign.sh: unknown argument: $1" >&2; exit 2 ;;
esac

if [[ ! -r "$SRC" ]]; then
  echo "sync-home-codesign.sh: source not readable: $SRC" >&2
  exit 2
fi

if [[ "$mode" == "check" ]]; then
  if diff -u "$DST" <(generate); then
    echo "home-codesign.yaml is in sync with home.yaml"
  else
    echo "" >&2
    echo "home-codesign.yaml has drifted from home.yaml." >&2
    echo "Run: scripts/sync-home-codesign.sh" >&2
    exit 1
  fi
else
  generate > "$DST"
  echo "regenerated $(basename "$DST") from $(basename "$SRC")"
fi
