#!/usr/bin/env bash
# One-shot: import dashboards/home.yaml as a UI-managed (storage-mode)
# Lovelace dashboard at url_path /home-ui, so that ha-context-dump.sh
# captures it under context/dashboards-storage.json.
#
# Run inside the HA Core container (SUPERVISOR_TOKEN is injected, and
# both aiohttp and PyYAML are part of Core's runtime). Examples:
#
#   docker exec homeassistant /config/scripts/import-home-to-storage.sh
#   ha core exec /config/scripts/import-home-to-storage.sh   # if exposed
#
# Idempotent: re-running overwrites the saved config but does not
# duplicate the dashboard registry entry.

set -euo pipefail

readonly SOURCE_YAML="${SOURCE_YAML:-/config/dashboards/home.yaml}"
readonly URL_PATH="${URL_PATH:-home-ui}"
readonly TITLE="${TITLE:-Home (UI)}"
readonly ICON="${ICON:-mdi:home-variant}"
readonly HA_WS_URL="${HA_WS_URL:-ws://127.0.0.1:8123/api/websocket}"

if [[ ! -f "$SOURCE_YAML" ]]; then
    echo "error: source dashboard not found: $SOURCE_YAML" >&2
    exit 1
fi

if [[ -z "${SUPERVISOR_TOKEN:-}" && -z "${HA_TOKEN:-}" ]]; then
    echo "error: SUPERVISOR_TOKEN (preferred) or HA_TOKEN must be set" >&2
    echo "       run this from inside the homeassistant Core container, e.g." >&2
    echo "       docker exec homeassistant $0" >&2
    exit 1
fi

export _IMPORT_SOURCE_YAML="$SOURCE_YAML"
export _IMPORT_URL_PATH="$URL_PATH"
export _IMPORT_TITLE="$TITLE"
export _IMPORT_ICON="$ICON"
export _IMPORT_WS_URL="$HA_WS_URL"
export _IMPORT_TOKEN="${SUPERVISOR_TOKEN:-$HA_TOKEN}"

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


with open(SOURCE_YAML) as fh:
    dashboard_config = yaml.safe_load(fh)


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
                sys.exit(f"auth failed: {auth_resp}")

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
