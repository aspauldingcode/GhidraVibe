#!/usr/bin/env bash
# Every inventory main_toolbar / provider_toolbar id must appear in Swift or GTK sources.
# Stock tool (Debugger/Emulator/VT) toolbar ids may live in StockToolShellView.swift.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/scripts/extract-stock-inventory.py" >/dev/null
python3 <<PY
import json, sys
from pathlib import Path
root = Path("$ROOT")
blob = ""
for p in [
    root / "macos/GhidraVibe/Sources",
    root / "linux/GhidraVibe/src",
]:
    if not p.is_dir():
        continue
    for f in p.rglob("*"):
        if f.suffix in {".swift", ".c", ".h"}:
            blob += f.read_text(errors="ignore")
missing = []
checked = 0
for inv_path in sorted((root / "native-ui/parity").glob("*.inventory.json")):
    inv = json.loads(inv_path.read_text())
    for e in inv["entries"]:
        if e["surface"] not in ("main_toolbar", "provider_toolbar", "project_toolbar", "tool_chest"):
            continue
        checked += 1
        if e["id"] not in blob:
            missing.append(f"{inv_path.name}: {e['id']}")
if missing:
    print("FAIL: inventory controls not referenced in Swift/GTK:", file=sys.stderr)
    for m in missing[:50]:
        print(f"  {m}", file=sys.stderr)
    if len(missing) > 50:
        print(f"  … +{len(missing)-50}", file=sys.stderr)
    sys.exit(1)
print(f"OK: {checked} toolbar/tool-chest controls present in sources")
PY
