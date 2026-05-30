#!/usr/bin/env python3
"""Cross-check entity references in YAML dashboards against the entity snapshot.

Dashboards reference entities by ID (e.g. `entity: light.kitchen_main`). Home
Assistant does not validate these at config-check time, so a typo'd or renamed
entity silently renders a blank/unavailable card. This script extracts the
entity IDs referenced in dashboards/*.yaml and flags any that do not exist in
context/entities.json (the entity-registry snapshot, which includes YAML
template entities and light groups because they carry a unique_id).

Usage:
    check-dashboard-entities.py [--entities PATH] [--strict] DASHBOARD.yaml ...

Exit codes:
    0  no unknown references (or --strict not set)
    1  unknown references found and --strict set
    2  usage / load error

Reference extraction is intentionally conservative — it only collects string
values under the keys `entity` and `entity_id`, and string items in lists under
the key `entities`. That captures the standard Lovelace/custom-card entity
references while ignoring jinja templates, service names, and CSS.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml

# A valid entity_id: lowercase domain, dot, object_id. Anything with `{`, `}`,
# whitespace, or uppercase is a template/placeholder and is skipped.
ENTITY_RE = re.compile(r"^[a-z_]+\.[a-z0-9_]+$")

ENTITY_KEYS = {"entity", "entity_id"}
LIST_KEYS = {"entities"}


def collect_refs(node: object, out: set[str]) -> None:
    """Recursively collect entity_id strings from a parsed YAML structure."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key in ENTITY_KEYS:
                _add_strings(value, out)
            elif key in LIST_KEYS and isinstance(value, list):
                for item in value:
                    if isinstance(item, str):
                        _add_strings(item, out)
                    else:
                        collect_refs(item, out)
            else:
                collect_refs(value, out)
    elif isinstance(node, list):
        for item in node:
            collect_refs(item, out)


def _add_strings(value: object, out: set[str]) -> None:
    """Add value(s) that look like entity IDs. Handles scalar or list."""
    if isinstance(value, str):
        if ENTITY_RE.match(value):
            out.add(value)
    elif isinstance(value, list):
        for item in value:
            if isinstance(item, str) and ENTITY_RE.match(item):
                out.add(item)


def load_known_entities(path: Path) -> set[str]:
    data = yaml.safe_load(path.read_text())  # JSON is a subset of YAML
    if not isinstance(data, list):
        raise ValueError(f"{path}: expected a JSON array of entities")
    return {e["entity_id"] for e in data if isinstance(e, dict) and "entity_id" in e}


def load_allowlist(path: Path) -> set[str]:
    """Read newline-delimited entity IDs, ignoring blank lines and # comments."""
    if not path.exists():
        return set()
    out: set[str] = set()
    for line in path.read_text().splitlines():
        entry = line.split("#", 1)[0].strip()
        if entry:
            out.add(entry)
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dashboards", nargs="+", type=Path)
    parser.add_argument(
        "--entities",
        type=Path,
        default=Path("context/entities.json"),
        help="entity snapshot (default: context/entities.json)",
    )
    parser.add_argument(
        "--allowlist",
        type=Path,
        default=None,
        help="file of entity IDs to exempt (valid-but-unsnapshotted or pending "
        "integrations); blank lines and # comments ignored",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="exit non-zero if any unknown references are found",
    )
    args = parser.parse_args(argv)

    try:
        known = load_known_entities(args.entities)
    except (OSError, ValueError, yaml.YAMLError) as exc:
        print(f"error: could not load entities snapshot: {exc}", file=sys.stderr)
        return 2

    allowlist = load_allowlist(args.allowlist) if args.allowlist else set()
    # Entries that have since entered the snapshot are redundant — surface them so
    # the allowlist gets pruned as pending integrations come online (non-fatal).
    stale = sorted(allowlist & known)
    exempt = known | allowlist

    total_unknown = 0
    for dash in args.dashboards:
        try:
            doc = yaml.safe_load(dash.read_text())
        except (OSError, yaml.YAMLError) as exc:
            print(f"error: could not parse {dash}: {exc}", file=sys.stderr)
            return 2
        refs: set[str] = set()
        collect_refs(doc, refs)
        unknown = sorted(r for r in refs if r not in exempt)
        checked = len(refs)
        if unknown:
            total_unknown += len(unknown)
            print(f"{dash}: {len(unknown)} unknown of {checked} referenced entities:")
            for ref in unknown:
                print(f"  - {ref}")
        else:
            print(f"{dash}: OK ({checked} entity references all resolve)")

    if stale:
        print(
            f"\nnote: {len(stale)} allowlisted entity(ies) now exist in "
            f"{args.entities} and can be removed from {args.allowlist}:"
        )
        for ref in stale:
            print(f"  - {ref}")

    if total_unknown:
        print(
            f"\n{total_unknown} dashboard entity reference(s) not found in "
            f"{args.entities}.",
            file=sys.stderr,
        )
        if args.strict:
            print(
                "If these are newly created entities, the snapshot may be stale — "
                "press input_button.ha_context_dump_now and let the drift PR land, "
                "then rebase. Otherwise, fix the typo/rename in the dashboard.",
                file=sys.stderr,
            )
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
