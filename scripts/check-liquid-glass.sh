#!/usr/bin/env bash
# Fail if forbidden fake-glass APIs appear in macOS sources; require Liquid Glass helpers.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 <<PY
import sys
from pathlib import Path
root = Path(r"""$ROOT""") / "macos/GhidraVibe/Sources"
for f in root.rglob("*.swift"):
    text = f.read_text(errors="ignore")
    if "NSVisualEffectView" in text or "CABackdropLayer" in text:
        print(f"FAIL: forbidden VisualEffect / backdrop blur in {f}", file=sys.stderr)
        sys.exit(1)
    if "CIFilter" in text and "blur" in text.lower():
        print(f"FAIL: forbidden VisualEffect / backdrop blur in {f}", file=sys.stderr)
        sys.exit(1)
cb = root / "GhidraVibe/CodeBrowserDockView.swift"
text = cb.read_text(errors="ignore") if cb.is_file() else ""
needles = ("LiquidGlass.Bar", "GlassToolbarButton", "GlassMnemonicButton", ".buttonStyle(.glass")
if not any(n in text for n in needles):
    print("FAIL: CodeBrowserDockView must use Liquid Glass helpers", file=sys.stderr)
    sys.exit(1)
lg = root / "GhidraVibe/LiquidGlass.swift"
lg_text = lg.read_text(errors="ignore") if lg.is_file() else ""
if "glassEffect" not in lg_text and ".buttonStyle(.glass" not in lg_text:
    print("FAIL: LiquidGlass.swift missing glass APIs", file=sys.stderr)
    sys.exit(1)
print("OK: Liquid Glass gate")
PY
