#!/usr/bin/env python3
"""Ensure a11y catalog contains ids for all stock inventory toolbar/provider controls."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "native-ui/a11y/catalog.json"
INVS = list((ROOT / "native-ui/parity").glob("*.inventory.json"))


def main() -> int:
    cat = json.loads(CATALOG.read_text())
    by_id = {e["id"]: e for e in cat["entries"]}
    added = 0
    for inv_path in INVS:
        inv = json.loads(inv_path.read_text())
        for e in inv.get("entries", []):
            eid = e["id"]
            if eid in by_id:
                continue
            if e.get("surface") not in (
                "main_toolbar",
                "provider_toolbar",
                "provider_body",
                "project_toolbar",
                "tool_chest",
                "project_body",
                "startup",
            ):
                continue
            by_id[eid] = {
                "id": eid,
                "label": e.get("label") or eid.split(".")[-1],
                "hint": e.get("hint") or e.get("label") or eid,
                "traits": ["button"] if "toolbar" in e.get("surface", "") or e.get("surface") == "tool_chest" else ["group"],
                "stock": e.get("stock", True),
            }
            added += 1
    cat["entries"] = sorted(by_id.values(), key=lambda e: e["id"])
    CATALOG.write_text(json.dumps(cat, indent=2) + "\n")
    print(f"Catalog entries={len(cat['entries'])} (+{added})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
