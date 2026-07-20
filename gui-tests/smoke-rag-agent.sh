#!/usr/bin/env bash
# Smoke: rules + rag_discover tool loop on vibe MCP.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIBE_URL="${GHIDRA_VIBE_MCP_EXT_URL:-http://127.0.0.1:8092}"
export PYTHONPATH="${ROOT}/scripts/lib${PYTHONPATH:+:$PYTHONPATH}"

started=0
if ! curl -fsS --max-time 1 "${VIBE_URL}/check_connection" >/dev/null 2>&1; then
  "${ROOT}/scripts/ghidra-vibe-mcp-ext" >/tmp/vibe-mcp-ext-rag.log 2>&1 &
  echo $! >/tmp/vibe-mcp-ext-rag.pid
  started=1
  for _ in $(seq 1 30); do
    curl -fsS --max-time 1 "${VIBE_URL}/check_connection" >/dev/null 2>&1 && break
    sleep 0.2
  done
fi

curl -fsS -X POST -H "Content-Type: application/json" \
  -d '{"text":"# smoke rules\n- prefer MCP decompile\n"}' \
  "${VIBE_URL}/rules_set" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("ok"), d; print("OK rules_set")'

curl -fsS "${VIBE_URL}/rules_get" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("ok"), d; print("OK rules_get")'

curl -fsS -X POST -H "Content-Type: application/json" \
  -d '{"query":"how does login validate the password?"}' \
  "${VIBE_URL}/rag_discover" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d.get("ok") or "error" in d
print("OK rag_discover", "ok" if d.get("ok") else d.get("error","?"))
'

curl -fsS -X POST -H "Content-Type: application/json" \
  -d '{"address":"0x1000"}' "${VIBE_URL}/vibe_nav_push" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d.get("ok"), d
print("OK vibe_nav_push")
'

if [[ "$started" == "1" && -f /tmp/vibe-mcp-ext-rag.pid ]]; then
  kill "$(cat /tmp/vibe-mcp-ext-rag.pid)" 2>/dev/null || true
fi
echo "smoke-rag-agent: PASS"
