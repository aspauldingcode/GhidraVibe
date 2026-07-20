#!/usr/bin/env python3
"""Rebuild TRACKED_GAPS.json from inventory disabled_honest + shell-depth entries."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "native-ui/parity/TRACKED_GAPS.json"


def main() -> int:
    gaps: list[dict] = []
    seen: set[str] = set()
    for inv_path in sorted((ROOT / "native-ui/parity").glob("*.inventory.json")):
        inv = json.loads(inv_path.read_text())
        tool = inv.get("tool", inv_path.stem)
        for e in inv.get("entries", []):
            if not e.get("stock", True):
                continue
            macos = (e.get("platforms") or {}).get("macos", e.get("behavior"))
            depth = e.get("depth", "stock")
            # Only track unfinished work — not stock-depth wired controls
            needs = macos == "disabled_honest" or (
                depth in ("shell", "partial") and macos != "wired"
            )
            if not needs:
                continue
            eid = e["id"]
            if eid in seen:
                continue
            seen.add(eid)
            wave = "B"
            if "debugger" in eid or "emulator" in eid:
                wave = "D"
            elif "version_tracking" in eid or ".vt." in eid or "versiontracking" in eid.replace("_", ""):
                wave = "D"
            elif eid.startswith("ghidra.vibe.project.toolbar.vc_"):
                wave = "C"
            elif "bsim" in eid or "function_graph" in eid or "script" in eid or "python" in eid:
                wave = "E"
            elif e.get("surface") in ("menubar", "main_toolbar", "provider_toolbar"):
                wave = "A" if "listing_" in eid or "toolbar" in eid else "B"
            gaps.append(
                {
                    "id": eid,
                    "tool": tool,
                    "surface": e.get("surface"),
                    "label": e.get("label"),
                    "wave": wave,
                    "depth": depth,
                    "owner": "native-gui",
                    "note": e.get("hint") or "Below stock depth — see docs/STOCK_PARITY.md",
                }
            )
    gaps.sort(key=lambda g: g["id"])
    payload = {
        "version": 2,
        "description": "CI-enforced stock gaps (disabled_honest or depth shell/partial). Ratchet max_stock_disabled down as waves land.",
        "max_stock_disabled": len(gaps),
        "gaps": gaps,
    }
    OUT.write_text(json.dumps(payload, indent=2) + "\n")
    print(f"Wrote {OUT.relative_to(ROOT)} gaps={len(gaps)} max={len(gaps)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
