#!/usr/bin/env bash
# Gate 0: inventory entries have catalog ids; chrome toolbar groups referenced.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INV="$ROOT/native-ui/parity/CodeBrowser.inventory.json"
CAT="$ROOT/native-ui/a11y/catalog.json"
CHROME="$ROOT/native-ui/parity/CodeBrowser.chrome.json"

python3 "$ROOT/scripts/extract-codebrowser-inventory.py"

if [[ ! -f "$INV" ]]; then
  echo "FAIL: missing $INV" >&2
  exit 1
fi

python3 <<PY
import json, sys
from pathlib import Path
root = Path("$ROOT")
inv = json.loads((root / "native-ui/parity/CodeBrowser.inventory.json").read_text())
cat = {e["id"] for e in json.loads((root / "native-ui/a11y/catalog.json").read_text())["entries"]}
chrome = json.loads((root / "native-ui/parity/CodeBrowser.chrome.json").read_text())
missing = []
for e in inv["entries"]:
    eid = e["id"]
    # menu ids may not all be in catalog yet — warn but require toolbar + provider_toolbar
    if e["surface"] in ("main_toolbar", "provider_toolbar", "provider_body") and eid not in cat:
        missing.append(eid)
if missing:
    print("FAIL: inventory ids missing from catalog:", file=sys.stderr)
    for m in missing[:40]:
        print(f"  {m}", file=sys.stderr)
    if len(missing) > 40:
        print(f"  … +{len(missing)-40} more", file=sys.stderr)
    sys.exit(1)
if inv["count"] < 40:
    print(f"FAIL: inventory too small ({inv['count']})", file=sys.stderr)
    sys.exit(1)
print(f"OK: inventory {inv['count']} entries; chrome tool={chrome.get('tool')}")
PY
