#!/usr/bin/env bash
# Smoke: vibe MCP Malimite tools (starts ext if needed for schema only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIBE_URL="${GHIDRA_VIBE_MCP_EXT_URL:-http://127.0.0.1:8092}"
export PYTHONPATH="${ROOT}/scripts/lib${PYTHONPATH:+:$PYTHONPATH}"

started=0
if ! curl -fsS --max-time 1 "${VIBE_URL}/check_connection" >/dev/null 2>&1; then
  "${ROOT}/scripts/ghidra-vibe-mcp-ext" >/tmp/vibe-mcp-ext.log 2>&1 &
  echo $! >/tmp/vibe-mcp-ext.pid
  started=1
  for _ in $(seq 1 30); do
    curl -fsS --max-time 1 "${VIBE_URL}/check_connection" >/dev/null 2>&1 && break
    sleep 0.2
  done
fi

curl -fsS "${VIBE_URL}/mcp/schema" | python3 -c '
import json,sys
d=json.load(sys.stdin)
names={t["name"] for t in d.get("tools",[])}
need={"malimite_analyze","malimite_list_classes","malimite_translate","swift_demangle"}
missing=need-names
assert not missing, missing
print("OK malimite tools in schema", sorted(need))
'

python3 - <<'PY' | curl -fsS -X POST -H "Content-Type: application/json" -d @- \
  "${VIBE_URL}/swift_demangle" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d.get("ok"), d
print("OK swift_demangle", (d.get("data") or {}).get("demangled","")[:80])
'
import json
print(json.dumps({"name": "_$s10Foundation4DataV"}))
PY

curl -fsS -X POST -H "Content-Type: application/json" \
  -d '{}' "${VIBE_URL}/malimite_libraries_list" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d.get("ok"), d
print("OK malimite_libraries_list")
'

if [[ "$started" == "1" && -f /tmp/vibe-mcp-ext.pid ]]; then
  kill "$(cat /tmp/vibe-mcp-ext.pid)" 2>/dev/null || true
fi
echo "smoke-malimite-mcp: PASS"
