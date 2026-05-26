#!/usr/bin/env bash
# One-shot: import dashboards/home.yaml as a UI-managed (storage-mode)
# Lovelace dashboard at url_path /home-ui, so that ha-context-dump.sh
# captures it under context/dashboards-storage.json.
#
# Run inside the HA Core container (Python 3, aiohttp, and PyYAML are
# part of Core's runtime):
#
#   docker exec homeassistant /config/scripts/import-home-to-storage.sh
#
# Token resolution order (first non-empty wins):
#   1. HA_TOKEN env var (one-shot override)
#   2. ha_token from /config/secrets.yaml (preferred, follows the project
#      convention of storing complete Authorization header values; see
#      scripts/README.md > "Script auth conventions")
#   3. SUPERVISOR_TOKEN env var (last resort — current HA versions reject
#      it on the Core websocket auth path; the script will still try)
#
# A leading "Bearer " prefix is stripped automatically so the value can
# be stored in the same form rest_command consumers expect.
#
# Idempotent: re-running overwrites the saved config but does not
# duplicate the dashboard registry entry.

set -euo pipefail

readonly SOURCE_YAML="${SOURCE_YAML:-/config/dashboards/home.yaml}"
readonly URL_PATH="${URL_PATH:-home-ui}"
readonly TITLE="${TITLE:-Home (UI)}"
readonly ICON="${ICON:-mdi:home-variant}"
readonly HA_WS_URL="${HA_WS_URL:-ws://127.0.0.1:8123/api/websocket}"
readonly SECRETS_YAML="${SECRETS_YAML:-/config/secrets.yaml}"

if [[ ! -f "$SOURCE_YAML" ]]; then
    echo "error: source dashboard not found: $SOURCE_YAML" >&2
    exit 1
fi

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

Then either (preferred) add it to ${SECRETS_YAML}:
    ha_token: "Bearer <paste-the-token-here>"

...or pass it once via env:
    docker exec -e HA_TOKEN='<paste-here>' homeassistant $0
MSG
    exit 1
fi

export _IMPORT_SOURCE_YAML="$SOURCE_YAML"
export _IMPORT_URL_PATH="$URL_PATH"
export _IMPORT_TITLE="$TITLE"
export _IMPORT_ICON="$ICON"
export _IMPORT_WS_URL="$HA_WS_URL"
export _IMPORT_TOKEN="$token"
export _IMPORT_TOKEN_SOURCE="$token_source"
export _IMPORT_SECRETS_YAML="$SECRETS_YAML"

python3 <<'PY'
import asyncio
import os
import sys

import aiohttp
import yaml

SOURCE_YAML = os.environ["_IMPORT_SOURCE_YAML"]
URL_PATH = os.environ["_IMPORT_URL_PATH"]
TITLE = os.environ["_IMPORT_TITLE"]
ICON = os.environ["_IMPORT_ICON"]
WS_URL = os.environ["_IMPORT_WS_URL"]
TOKEN = os.environ["_IMPORT_TOKEN"]
TOKEN_SOURCE = os.environ["_IMPORT_TOKEN_SOURCE"]
SECRETS_YAML = os.environ["_IMPORT_SECRETS_YAML"]


with open(SOURCE_YAML) as fh:
    dashboard_config = yaml.safe_load(fh)


def fail_auth(resp):
    lines = [f"auth failed (token from {TOKEN_SOURCE}): {resp}"]
    if "SUPERVISOR_TOKEN" in TOKEN_SOURCE:
        lines += [
            "",
            "SUPERVISOR_TOKEN is the token Core uses to call OUT to Supervisor;",
            "current HA versions do not accept it for the Core websocket auth path.",
            "",
            "Fix: create a long-lived access token in the HA UI",
            "(profile avatar -> Security -> Long-Lived Access Tokens -> Create), then add:",
            f'    ha_token: "Bearer <paste-the-token-here>"',
            f"to {SECRETS_YAML} and re-run.",
        ]
    sys.exit("\n".join(lines))


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
                fail_auth(auth_resp)

            print(f"authenticated via {TOKEN_SOURCE}")
            msg_id = 1

            list_resp = await call(ws, msg_id, {"type": "lovelace/dashboards/list"})
            msg_id += 1
            if not list_resp.get("success", False):
                sys.exit(f"list failed: {list_resp}")

            existing = {d["url_path"]: d for d in list_resp.get("result") or []}
            if URL_PATH in existing:
                print(f"dashboard '{URL_PATH}' already registered (id={existing[URL_PATH]['id']}); overwriting config only")
            else:
                create_resp = await call(ws, msg_id, {
                    "type": "lovelace/dashboards/create",
                    "url_path": URL_PATH,
                    "title": TITLE,
                    "icon": ICON,
                    "show_in_sidebar": True,
                    "require_admin": False,
                    "mode": "storage",
                })
                msg_id += 1
                if not create_resp.get("success", False):
                    sys.exit(f"create failed: {create_resp}")
                print(f"registered dashboard '{URL_PATH}' (title='{TITLE}', icon='{ICON}')")

            save_resp = await call(ws, msg_id, {
                "type": "lovelace/config/save",
                "url_path": URL_PATH,
                "config": dashboard_config,
            })
            msg_id += 1
            if not save_resp.get("success", False):
                sys.exit(f"save failed: {save_resp}")

            view_count = len((dashboard_config or {}).get("views") or [])
            print(f"saved {view_count} view(s) from {SOURCE_YAML} to dashboard '{URL_PATH}'")
            print("trigger context-sync (input_button.ha_context_dump_now) to refresh context/dashboards-storage.json")


asyncio.run(main())
PY
