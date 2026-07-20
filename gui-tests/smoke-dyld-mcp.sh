#!/usr/bin/env bash
# Smoke: dyld_* vibe MCP tools (list/find; import optional).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIBE_URL="${GHIDRA_VIBE_MCP_EXT_URL:-http://127.0.0.1:8092}"
export PYTHONPATH="${ROOT}/scripts/lib${PYTHONPATH:+:$PYTHONPATH}"
export GHIDRA_VIBE_DYLD="${GHIDRA_VIBE_DYLD:-${ROOT}/scripts/ghidra-vibe-dyld}"

started=0
if ! curl -fsS --max-time 1 "${VIBE_URL}/check_connection" >/dev/null 2>&1; then
  "${ROOT}/scripts/ghidra-vibe-mcp-ext" >/tmp/vibe-mcp-ext-dyld.log 2>&1 &
  echo $! >/tmp/vibe-mcp-ext-dyld.pid
  started=1
  for _ in $(seq 1 30); do
    curl -fsS --max-time 1 "${VIBE_URL}/check_connection" >/dev/null 2>&1 && break
    sleep 0.2
  done
fi

curl -fsS "${VIBE_URL}/dyld_find_cache" | python3 -c '
import json,sys
d=json.load(sys.stdin)
print("dyld_find_cache:", "ok" if d.get("ok") else d)
'

curl -fsS -X POST -H "Content-Type: application/json" \
  -d '{"query":"AppKit"}' "${VIBE_URL}/dyld_list_images" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d.get("ok") or "data" in d or "error" in d
rows=d.get("data") or []
print("OK dyld_list_images rows", len(rows) if isinstance(rows,list) else type(rows))
'

if [[ "$started" == "1" && -f /tmp/vibe-mcp-ext-dyld.pid ]]; then
  kill "$(cat /tmp/vibe-mcp-ext-dyld.pid)" 2>/dev/null || true
fi
echo "smoke-dyld-mcp: PASS"
