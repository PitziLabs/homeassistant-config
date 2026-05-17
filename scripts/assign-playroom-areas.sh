#!/usr/bin/env bash
# One-shot: assign the orphaned Play Room devices to the play_room area.
#
# Device→area mapping in HA lives in .storage/core.device_registry (runtime
# state, not git-tracked) and can only be edited via the websocket
# `config/device_registry/update` command. This script does that for the
# three Play Room devices that landed without an area_id:
#
#   8a93d92e1ef5b0f7e39d20a7d9cfa603 → play_room  (Playroom 3, ZHA Hue bulb)
#   2cf841bd422c4e20593540bf7eeb2f1b → play_room  (Playroom 4, ZHA Hue bulb)
#   c13d103ea0a1177f174dba7bd38fbeaa → play_room  (Play Room outlet, Kasa HS200)
#   f090c7c3434162e57c3d8a9cee321fae → play_room  (Wemo wall switch — labeled
#                                                  "Bonus room" at adoption,
#                                                  actually powers the Hue bulbs)
#
# Run inside the HA Core container (Python 3 + aiohttp are part of Core):
#
#   docker exec homeassistant /config/scripts/assign-playroom-areas.sh
#
# More commonly: triggered via shell_command.assign_playroom_areas from the
# `input_button.assign_playroom_areas` helper in
# packages/playroom_area_fix.yaml.
#
# Token resolution mirrors scripts/import-home-to-storage.sh:
#   1. HA_TOKEN env var (one-shot override)
#   2. ha_token from /config/secrets.yaml (preferred; see CLAUDE.md >
#      "Script auth conventions" for why values are stored as full
#      Authorization header strings)
#   3. SUPERVISOR_TOKEN env var (last resort; rejected by current HA on
#      the Core websocket auth path, but tried for completeness)
#
# Idempotent — HA accepts the same update payload repeatedly and the script
# logs the resulting area_id from each response so re-runs are observable.

set -euo pipefail

readonly HA_WS_URL="${HA_WS_URL:-ws://127.0.0.1:8123/api/websocket}"
readonly SECRETS_YAML="${SECRETS_YAML:-/config/secrets.yaml}"

token=""
token_source=""
if [[ -n "${HA_TOKEN:-}" ]]; then
    token=$HA_TOKEN
    token_source="HA_TOKEN env var"
elif [[ -f "$SECRETS_YAML" ]]; then
    secret=$(awk -F'"' '/^ha_token:/ {print $2; exit}' "$SECRETS_YAML")
    if [[ -n "$secret" && "$secret" != "CHANGE_ME" && "$secret" != "Bearer CHANGE_ME" ]]; then
        token=$secret
        token_source="ha_token from $SECRETS_YAML"
    fi
fi
if [[ -z "$token" && -n "${SUPERVISOR_TOKEN:-}" ]]; then
    token=$SUPERVISOR_TOKEN
    token_source="SUPERVISOR_TOKEN env var (fallback)"
fi
token="${token#Bearer }"

if [[ -z "$token" ]]; then
    cat >&2 <<MSG
error: no Home Assistant access token found.

Create a long-lived access token in the HA UI:
    profile (bottom-left avatar) -> Security tab
    -> Long-Lived Access Tokens -> Create Token

Then add it to ${SECRETS_YAML}:
    ha_token: "Bearer <paste-the-token-here>"
MSG
    exit 1
fi

export _ASSIGN_WS_URL="$HA_WS_URL"
export _ASSIGN_TOKEN="$token"
export _ASSIGN_TOKEN_SOURCE="$token_source"

python3 <<'PY'
import asyncio
import os
import sys

import aiohttp

WS_URL = os.environ["_ASSIGN_WS_URL"]
TOKEN = os.environ["_ASSIGN_TOKEN"]
TOKEN_SOURCE = os.environ["_ASSIGN_TOKEN_SOURCE"]

ASSIGNMENTS = [
    ("8a93d92e1ef5b0f7e39d20a7d9cfa603", "play_room", "Playroom 3"),
    ("2cf841bd422c4e20593540bf7eeb2f1b", "play_room", "Playroom 4"),
    ("c13d103ea0a1177f174dba7bd38fbeaa", "play_room", "Play Room outlet"),
    ("f090c7c3434162e57c3d8a9cee321fae", "play_room", "Bonus room (Wemo wall switch)"),
]


async def call(ws, msg_id, payload):
    payload = {**payload, "id": msg_id}
    await ws.send_json(payload)
    while True:
        resp = await ws.receive_json()
        if resp.get("id") == msg_id:
            return resp


async def main():
    timeout = aiohttp.ClientTimeout(total=30)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        async with session.ws_connect(WS_URL) as ws:
            hello = await ws.receive_json()
            if hello.get("type") != "auth_required":
                sys.exit(f"unexpected handshake: {hello}")

            await ws.send_json({"type": "auth", "access_token": TOKEN})
            auth_resp = await ws.receive_json()
            if auth_resp.get("type") != "auth_ok":
                sys.exit(f"auth failed (token from {TOKEN_SOURCE}): {auth_resp}")

            print(f"authenticated via {TOKEN_SOURCE}")
            msg_id = 1
            failures = 0

            for device_id, area_id, label in ASSIGNMENTS:
                resp = await call(ws, msg_id, {
                    "type": "config/device_registry/update",
                    "device_id": device_id,
                    "area_id": area_id,
                })
                msg_id += 1
                if not resp.get("success", False):
                    failures += 1
                    print(f"FAIL {label} ({device_id}): {resp.get('error')}")
                    continue
                resulting_area = (resp.get("result") or {}).get("area_id")
                print(f"OK   {label} ({device_id}) -> area_id={resulting_area}")

            if failures:
                sys.exit(f"{failures} assignment(s) failed")
            print("trigger context-sync (input_button.ha_context_dump_now) to refresh context/devices.json")


asyncio.run(main())
PY
