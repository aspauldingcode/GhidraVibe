#!/usr/bin/env bash
# Smoke: analysis MCP provider endpoints (requires headless MCP up).
set -euo pipefail
MCP_URL="${GHIDRA_MCP_URL:-http://127.0.0.1:8089}"
fail=0
check() {
  local path="$1"
  if curl -fsS --max-time 5 "${MCP_URL}/${path}" >/tmp/ghidra-vibe-smoke-$$.txt 2>/dev/null; then
    echo "OK  analysis/${path}"
  else
    echo "WARN analysis/${path} (MCP down or tool missing)"
    fail=$((fail + 1))
  fi
}
if ! curl -fsS --max-time 2 "${MCP_URL}/check_connection" >/dev/null 2>&1 \
  && ! curl -fsS --max-time 2 "${MCP_URL}/check" >/dev/null 2>&1; then
  echo "SKIP: analysis MCP not reachable at ${MCP_URL}"
  exit 0
fi
for p in list_functions list_segments list_strings list_bookmarks list_exports list_namespaces; do
  check "$p"
done
echo "smoke-providers-mcp: soft-fail count=${fail}"
exit 0
