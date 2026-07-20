#!/usr/bin/env bash
# Gate: CAPABILITY_MATRIX covers every stock wired inventory id + universe module; no orphans.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 "$ROOT/scripts/generate-capability-matrix.py" >/dev/null

python3 <<'PY'
import json, sys
from pathlib import Path
root = Path(".")
matrix = json.loads((root / "native-ui/parity/CAPABILITY_MATRIX.json").read_text())
ids = {c["id"] for c in matrix["cases"]}
missing = []
for inv_path in sorted((root / "native-ui/parity").glob("*.inventory.json")):
    inv = json.loads(inv_path.read_text())
    for e in inv.get("entries", []):
        if not e.get("stock", True):
            continue
        macos = (e.get("platforms") or {}).get("macos", e.get("behavior"))
        if macos != "wired":
            continue
        if e["id"] not in ids:
            missing.append(f"inventory:{e['id']}")
uni = json.loads((root / "native-ui/parity/STOCK_UNIVERSE.json").read_text())
import re
for cat, names in (uni.get("modules") or {}).items():
    for name in names:
        eid = (
            f"ghidra.vibe.module.{cat.lower()}."
            + re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
        )
        if eid not in ids:
            missing.append(f"module:{eid}")
unmapped = [c["id"] for c in matrix["cases"] if not c.get("probe")]
if missing:
    print("FAIL: wired stock ids missing from CAPABILITY_MATRIX:", file=sys.stderr)
    for m in missing[:40]:
        print(f"  {m}", file=sys.stderr)
    sys.exit(1)
if unmapped:
    print("FAIL: matrix cases without probe:", file=sys.stderr)
    for u in unmapped[:20]:
        print(f"  {u}", file=sys.stderr)
    sys.exit(1)
print(f"OK: capability matrix {matrix['count']} cases; probes={matrix.get('counts_by_probe')}")
PY
