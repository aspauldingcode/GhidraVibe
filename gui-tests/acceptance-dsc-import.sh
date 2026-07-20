#!/usr/bin/env bash
# Acceptance: on-device DSC → import any image (fixture: AppKit) → MCP decompile.
# Product UI has no AppKit/SkyLight one-shots; this script only uses the generic CLI.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DYLD="${GHIDRA_VIBE_DYLD:-$ROOT/scripts/ghidra-vibe-dyld}"
IMAGE="${DSC_ACCEPT_IMAGE:-AppKit}"
PROJECT="${DSC_ACCEPT_PROJECT:-$ROOT/ghidra-vibe-projects/dsc-accept/VibeDSC.gpr}"

echo "== DSC Index: resolve $IMAGE =="
RESOLVED="$("$DYLD" resolve --image "$IMAGE")"
echo "resolved=$RESOLVED"
[[ -n "$RESOLVED" ]]

echo "== import $IMAGE (DyldCacheFileSystem) =="
"$DYLD" import --image "$IMAGE" --project "$PROJECT" || \
  "$DYLD" import --image "$IMAGE"

echo "== MCP health (optional) =="
if curl -fsS --max-time 2 http://127.0.0.1:8089/check_connection >/dev/null 2>&1; then
  curl -fsS "http://127.0.0.1:8089/list_functions?limit=5" | head -c 200
  echo
  echo "ACCEPTANCE_OK DSC import + MCP list ($IMAGE)"
else
  echo "ACCEPTANCE_OK DSC import ($IMAGE); MCP not running — start ghidra-vibe-mcp-headless to decompile"
fi
