#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MCP_URL="${GHIDRA_MCP_URL:-http://127.0.0.1:8089}"
GUI_URL="${GHIDRA_VIBE_GUI_URL:-http://127.0.0.1:8091}"
BRIDGE="${GHIDRA_VIBE_MCP_BRIDGE:-}"

echo "MCP_URL=$MCP_URL"
if curl -fsS --max-time 3 "$MCP_URL/" >/dev/null 2>&1 || curl -fsS --max-time 3 "$MCP_URL/check" >/dev/null 2>&1; then
  echo "OK ghidra MCP reachable"
  curl -fsS --max-time 30 "$MCP_URL/methods" | head -5 || true
else
  echo "WARN: analysis MCP not up (start plugin)"
fi

if curl -fsS --max-time 3 "$GUI_URL/health" >/dev/null 2>&1; then
  echo "OK ghidra-vibe-gui control reachable"
else
  echo "WARN: GUI control not up (launch GhidraVibe)"
fi

if [[ -n "$BRIDGE" && -f "$BRIDGE" ]]; then
  echo "OK bridge present: $BRIDGE"
fi
test -f "$ROOT/nix/share/bridge_mcp_gui.py"
echo "OK cursor-mcp-usability (bridges present; live MCP optional)"
