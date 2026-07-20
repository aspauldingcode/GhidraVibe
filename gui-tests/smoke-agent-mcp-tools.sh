#!/usr/bin/env bash
# Mock MCP: ensure control plane can trigger mcp_health / fetch without cloud API.
set -euo pipefail
GUI="${GHIDRA_VIBE_GUI_URL:-http://127.0.0.1:8091}"
if ! curl -fsS --max-time 2 "$GUI/health" >/dev/null 2>&1; then
  echo "SKIP: GuiControlServer not running"
  exit 0
fi
curl -fsS -X POST "$GUI/action" -H 'Content-Type: application/json' -d '{"id":"mcp_health"}' >/dev/null
curl -fsS -X POST "$GUI/action" -H 'Content-Type: application/json' -d '{"id":"fetch_functions"}' >/dev/null
echo "OK smoke-agent-mcp-tools"
