#!/usr/bin/env bash
# Smoke whole-bundle enumeration via vibe MCP (malimite_list_bundle_binaries).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
URL="${GHIDRA_VIBE_MCP_EXT_URL:-http://127.0.0.1:8092}"
FIXTURE="${GHIDRA_VIBE_SMOKE_APP:-$ROOT/gui-tests/fixtures/Smoke.app}"

if [[ ! -d "$FIXTURE" ]]; then
  mkdir -p "$FIXTURE/Contents/MacOS"
  printf '\xcf\xfa\xed\xfe' >"$FIXTURE/Contents/MacOS/Smoke"
  cat >"$FIXTURE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Smoke</string>
  <key>CFBundleIdentifier</key><string>dev.ghidravibe.Smoke</string>
</dict></plist>
PLIST
fi

if ! curl -sf "$URL/check_connection" >/dev/null 2>&1 && ! curl -sf "$URL/vibe_health" >/dev/null 2>&1; then
  echo "SKIP: vibe MCP not running at $URL"
  exit 0
fi

body=$(curl -sf -X POST "$URL/malimite_list_bundle_binaries" \
  -H 'Content-Type: application/json' \
  -d "{\"path\":\"$FIXTURE\"}" || true)
if echo "$body" | grep -q '"ok"[[:space:]]*:[[:space:]]*true'; then
  echo "PASS: malimite_list_bundle_binaries on Smoke.app"
  echo "$body" | head -c 400
  echo
  exit 0
fi
echo "FAIL: malimite_list_bundle_binaries → $body" >&2
exit 1
