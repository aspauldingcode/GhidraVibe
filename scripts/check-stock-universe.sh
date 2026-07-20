#!/usr/bin/env bash
# STOCK_UNIVERSE tools/providers must be represented in chrome contracts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -n "${GHIDRA_INSTALL_DIR:-}" ]]; then
  python3 "$ROOT/scripts/extract-stock-universe.py" >/dev/null
elif [[ ! -f "$ROOT/native-ui/parity/STOCK_UNIVERSE.json" ]]; then
  echo "FAIL: missing STOCK_UNIVERSE.json (set GHIDRA_INSTALL_DIR to regenerate)" >&2
  exit 1
fi

python3 <<'PY'
import json, sys
from pathlib import Path
root = Path(".")
u = json.loads((root / "native-ui/parity/STOCK_UNIVERSE.json").read_text())
chrome_map = {
    "CodeBrowser": root / "native-ui/parity/CodeBrowser.chrome.json",
    "Debugger": root / "native-ui/parity/Debugger.chrome.json",
    "Emulator": root / "native-ui/parity/Emulator.chrome.json",
    "Version Tracking": root / "native-ui/parity/VersionTracking.chrome.json",
}
fail = []
for tool in u["tools"]:
    tid = tool["id"]
    path = chrome_map.get(tid)
    if not path or not path.is_file():
        fail.append(f"missing chrome for {tid}")
        continue
    ch = json.loads(path.read_text())
    listed = set()
    listed |= set(ch.get("defaultActiveProviders") or [])
    listed |= set(ch.get("windowMenuProviders") or [])
    for p in ch.get("providers") or []:
        if isinstance(p, dict):
            listed.add(p.get("title") or p.get("name") or "")
    # Normalize
    def norm(s: str) -> str:
        s = (s or "").rstrip(": ").strip()
        if s.startswith("Bytes"):
            return "Bytes"
        if s.startswith("Listing"):
            return "Listing"
        if s == "[Dynamic]":
            return "Dynamic"
        return s
    listed_n = {norm(x) for x in listed}
    missing = []
    for p in tool["providers"]:
        t = norm(p["title"])
        if t and t not in listed_n:
            missing.append(t)
    if missing:
        fail.append(f"{tid}: {len(missing)} providers not in chrome: {missing[:8]}")

fe = json.loads((root / "native-ui/parity/FrontEnd.chrome.json").read_text())
for t in ["CodeBrowser", "Debugger", "Emulator", "Version Tracking"]:
    if t not in fe.get("defaultTools", []):
        fail.append(f"FrontEnd missing Tool Chest entry: {t}")

if fail:
    print("FAIL: stock universe not covered by chrome:", file=sys.stderr)
    for f in fail:
        print(f"  {f}", file=sys.stderr)
    sys.exit(1)
print(f"OK: stock universe ({u['summary']['tool_count']} tools) ⊆ chrome contracts")
PY
