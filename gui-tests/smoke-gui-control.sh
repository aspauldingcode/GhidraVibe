#!/usr/bin/env bash
# HTTP control plane smoke (app must be running with GuiControlServer).
set -euo pipefail
GUI="${GHIDRA_VIBE_GUI_URL:-http://127.0.0.1:8091}"

if ! curl -fsS --max-time 2 "$GUI/health" >/dev/null 2>&1; then
  echo "SKIP: GuiControlServer not running at $GUI (launch GhidraVibe)"
  exit 0
fi

curl -fsS "$GUI/health" | tee /tmp/ghidra-vibe-gui-health.json
grep -q '"ok"' /tmp/ghidra-vibe-gui-health.json

curl -fsS -X POST "$GUI/navigate" -H 'Content-Type: application/json' -d '{"pane":"functions"}' >/tmp/nav.json
curl -fsS "$GUI/state" | tee /tmp/state.json
grep -q 'sidebar' /tmp/state.json

curl -fsS -X POST "$GUI/action" -H 'Content-Type: application/json' -d '{"id":"mcp_health"}' >/dev/null
curl -fsS "$GUI/dyld/caches" | tee /tmp/caches.json

echo "OK smoke-gui-control"
