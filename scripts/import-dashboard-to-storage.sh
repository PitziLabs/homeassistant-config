#!/usr/bin/env bash
# Ad-hoc: import a git-managed YAML dashboard into a UI-managed (storage-mode)
# Lovelace dashboard, so it can be hand-tweaked in the HA UI while still
# starting from the repo's "official" dashboard paradigm. After it runs the
# next ha-context-dump.sh snapshot captures the result in
# context/dashboards-storage.json.
#
# Run inside the HA Core container (Python 3, aiohttp, and PyYAML are part of
# Core's runtime; the SSH add-on's Alpine shell has none of them):
#
#   # default: seed dashboards/home.yaml -> "Home (UI Edit)" at /home-ui-edit
#   docker exec homeassistant /config/scripts/import-dashboard-to-storage.sh
#
#   # any dashboard, by name (resolved to /config/dashboards/<name>.yaml):
#   docker exec homeassistant /config/scripts/import-dashboard-to-storage.sh kiosk
#
#   # full control over the storage dashboard's url_path / title / icon:
#   docker exec homeassistant /config/scripts/import-dashboard-to-storage.sh \
#       home home-ui-edit "Home (UI Edit)" mdi:home-edit
#
# Positional args (each falls back to its env var, then to a derived default):
#   1  <source>    dashboard NAME (-> /config/dashboards/<name>.yaml) or an
#                  explicit path. Env: SOURCE_YAML. Default: home
#   2  <url_path>  storage dashboard url_path. Env: URL_PATH.
#                  Default: <name>-ui-edit
#   3  <title>     sidebar title. Env: TITLE. Default: "<Name> (UI Edit)"
#   4  <icon>      mdi icon. Env: ICON. Default: mdi:view-dashboard-edit
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
# Idempotent: re-running overwrites the saved config but does not duplicate
# the dashboard registry entry. NOTE: re-importing OVERWRITES any hand-edits
# made in the UI copy — it is a reseed-from-source operation, by design.

set -euo pipefail

# --- resolve source (arg 1 > $SOURCE_YAML > "home"); bare names expand to
#     /config/dashboards/<name>.yaml, explicit paths pass through unchanged ---
src_in="${1:-${SOURCE_YAML:-home}}"
if [[ "$src_in" == */* || "$src_in" == *.yaml ]]; then
    SOURCE_YAML="$src_in"
else
    SOURCE_YAML="/config/dashboards/${src_in}.yaml"
fi

# url_path / title / icon: arg > env > (empty, derived in Python from the
# source basename so the title-casing isn't at the mercy of busybox sed)
URL_PATH="${2:-${URL_PATH:-}}"
TITLE="${3:-${TITLE:-}}"
ICON="${4:-${ICON:-}}"

readonly HA_WS_URL="${HA_WS_URL:-ws://127.0.0.1:8123/api/websocket}"
readonly SECRETS_YAML="${SECRETS_YAML:-/config/secrets.yaml}"

if [[ ! -f "$SOURCE_YAML" ]]; then
    echo "error: source dashboard not found: $SOURCE_YAML" >&2
    echo "       available dashboards:" >&2
    ls -1 /config/dashboards/*.yaml 2>/dev/null | sed 's#.*/#         #; s#\.yaml$##' >&2 || true
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

# Derive any defaults left empty by the caller from the source basename, e.g.
# /config/dashboards/home.yaml -> name "home" -> url_path "home-ui-edit",
# title "Home (UI Edit)".
name = os.path.splitext(os.path.basename(SOURCE_YAML))[0]
pretty = name.replace("-", " ").replace("_", " ").title()
URL_PATH = URL_PATH or f"{name}-ui-edit"
TITLE = TITLE or f"{pretty} (UI Edit)"
ICON = ICON or "mdi:view-dashboard-edit"


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
