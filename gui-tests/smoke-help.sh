#!/usr/bin/env bash
# Verify packaged Help corpus + optional GuiControl open.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="${GHIDRA_VIBE_APP:-$HOME/Applications/GhidraVibe.app}"
HELP="$APP/Contents/Resources/help"
GUI="${GHIDRA_VIBE_GUI_URL:-http://127.0.0.1:8091}"

if [[ ! -d "$HELP/articles" ]]; then
  echo "Help not in $APP — packaging…"
  "$REPO/macos/GhidraVibe/scripts/package-app.sh" "$REPO/macos/GhidraVibe/.build/GhidraVibe.app"
  APP="$REPO/macos/GhidraVibe/.build/GhidraVibe.app"
  HELP="$APP/Contents/Resources/help"
fi

test -f "$HELP/toc.json"
test -f "$HELP/map.json"
test -f "$HELP/tips.txt"
test -f "$HELP/manifest.json"
test -d "$HELP/articles"

python3 <<PY
import json
from pathlib import Path
help_dir = Path("$HELP")
m = json.loads((help_dir / "manifest.json").read_text())
assert int(m.get("articles") or 0) >= 200, m
tips = [ln for ln in (help_dir / "tips.txt").read_text().splitlines() if ln.strip()]
assert len(tips) >= 70, len(tips)
toc = json.loads((help_dir / "toc.json").read_text())
assert toc.get("children") or toc.get("title")
welcome = help_dir / "articles" / "topics" / "Misc" / "Welcome_to_Help.htm"
assert welcome.is_file(), welcome
print(f"OK corpus articles={m['articles']} tips={len(tips)} default={m.get('defaultPath')}")
PY

if curl -fsS --max-time 2 "$GUI/health" >/dev/null 2>&1; then
  curl -fsS -X POST "$GUI/action" -H 'Content-Type: application/json' \
    -d '{"id":"show_help"}' >/dev/null || true
  echo "OK GuiControl show_help posted"
else
  echo "SKIP live Help UI (GuiControl not running)"
fi

echo "OK smoke-help"
