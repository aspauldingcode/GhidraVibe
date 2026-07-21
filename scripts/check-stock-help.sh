#!/usr/bin/env bash
# Guard: extracted stock Help bundle meets corpus thresholds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${HELP_OUT:-$ROOT/native-ui/help}"

if [[ -n "${GHIDRA_INSTALL_DIR:-}" ]] || [[ ! -f "$OUT/manifest.json" ]]; then
  python3 "$ROOT/scripts/extract-stock-help.py" --out "$OUT" --quiet
fi

python3 <<PY
import json, sys
from pathlib import Path
out = Path("$OUT")
manifest = out / "manifest.json"
toc = out / "toc.json"
tips = out / "tips.txt"
articles = out / "articles"
fail = []
if not manifest.is_file():
    fail.append("missing manifest.json")
else:
    m = json.loads(manifest.read_text())
    if int(m.get("articles") or 0) < 200:
        fail.append(f"articles {m.get('articles')} < 200")
    if int(m.get("tips") or 0) < 70:
        fail.append(f"tips {m.get('tips')} < 70")
    if int(m.get("mapIds") or 0) < 1000:
        fail.append(f"mapIds {m.get('mapIds')} < 1000")
    if int(m.get("tocNodes") or 0) < 100:
        fail.append(f"tocNodes {m.get('tocNodes')} < 100")
if not toc.is_file():
    fail.append("missing toc.json")
else:
    t = json.loads(toc.read_text())
    if not (t.get("children") or t.get("title")):
        fail.append("toc.json empty root")
if not tips.is_file():
    fail.append("missing tips.txt")
else:
    n = sum(1 for ln in tips.read_text().splitlines() if ln.strip())
    if n < 70:
        fail.append(f"tips.txt lines {n} < 70")
html = list(articles.rglob("*.htm")) + list(articles.rglob("*.html")) if articles.is_dir() else []
if len(html) < 200:
    fail.append(f"on-disk html {len(html)} < 200")
vibe = articles / "vibe" / "mcp.html" if articles.is_dir() else None
if vibe is None or not vibe.is_file():
    fail.append("missing GhidraVibe vibe/mcp.html addendum")
if fail:
    print("FAIL check-stock-help:")
    for f in fail:
        print(" ", f)
    sys.exit(1)
print(f"OK check-stock-help — {len(html)} articles, tips≥70, toc+map present ({out})")
PY
