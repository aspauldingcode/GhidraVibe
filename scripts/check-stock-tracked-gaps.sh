#!/usr/bin/env bash
# Every stock disabled_honest inventory entry must be listed in TRACKED_GAPS.json.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 "$ROOT/scripts/extract-stock-inventory.py" >/dev/null
python3 "$ROOT/scripts/sync-tracked-gaps.py" >/dev/null

python3 <<'PY'
import json, sys
from pathlib import Path
root = Path(".")
gaps_path = root / "native-ui/parity/TRACKED_GAPS.json"
if not gaps_path.is_file():
    print("FAIL: missing TRACKED_GAPS.json", file=sys.stderr)
    sys.exit(1)
gaps = json.loads(gaps_path.read_text())
tracked = {g["id"] for g in gaps.get("gaps", [])}
orphan = []
gap_ids = []
for inv_path in sorted((root / "native-ui/parity").glob("*.inventory.json")):
    inv = json.loads(inv_path.read_text())
    for e in inv.get("entries", []):
        if not e.get("stock", True):
            continue
        macos = (e.get("platforms") or {}).get("macos", e.get("behavior"))
        depth = e.get("depth", "stock")
        if macos != "disabled_honest" and depth not in ("shell", "partial"):
            continue
        gap_ids.append(e["id"])
        if e["id"] not in tracked:
            orphan.append(f"{inv_path.name}: {e['id']}")

stale = sorted(tracked - set(gap_ids))
max_allowed = gaps.get("max_stock_disabled", 10**9)
if len(gap_ids) > max_allowed:
    print(
        f"FAIL: stock gaps={len(gap_ids)} > max_stock_disabled={max_allowed}",
        file=sys.stderr,
    )
    sys.exit(1)
if orphan:
    print("FAIL: inventory gaps not in TRACKED_GAPS:", file=sys.stderr)
    for o in orphan[:40]:
        print(f"  {o}", file=sys.stderr)
    if len(orphan) > 40:
        print(f"  … +{len(orphan)-40}", file=sys.stderr)
    sys.exit(1)
if stale:
    print(f"WARN: {len(stale)} TRACKED_GAPS ids no longer in inventory (re-sync)", file=sys.stderr)
print(f"OK: {len(gap_ids)} stock gaps tracked (max={max_allowed})")
PY
