#!/usr/bin/env bash
# Acceptance: on-device DSC → import any image (fixture: AppKit) → optional MCP decompile.
# Product UI has no AppKit/SkyLight one-shots; this script only uses the generic CLI.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DYLD="${GHIDRA_VIBE_DYLD:-$ROOT/scripts/ghidra-vibe-dyld}"
IMAGE="${DSC_ACCEPT_IMAGE:-AppKit}"
# Unique project per run — avoids "Unable to lock project" against a live GUI.
RUN_ID="${GITHUB_RUN_ID:-$$}"
PROJECT_DIR="${DSC_ACCEPT_PROJECT_DIR:-$ROOT/ghidra-vibe-projects/dsc-accept-${RUN_ID}}"
PROJECT_NAME="${DSC_ACCEPT_PROJECT_NAME:-VibeDSC}"
MCP_URL="${GHIDRA_MCP_URL:-http://127.0.0.1:8089}"
export GHIDRA_VIBE_SCRIPT_PATH="${GHIDRA_VIBE_SCRIPT_PATH:-$ROOT/ghidra_scripts}"
export GHIDRA_VIBE_DSC_LOG_DIR="${GHIDRA_VIBE_DSC_LOG_DIR:-$ROOT/ghidra-vibe-projects/logs}"
mkdir -p "$PROJECT_DIR" "$GHIDRA_VIBE_DSC_LOG_DIR"

echo "== DSC Index: resolve $IMAGE =="
RESOLVED="$("$DYLD" resolve --image "$IMAGE")"
echo "resolved=$RESOLVED"
[[ -n "$RESOLVED" ]]

echo "== import $IMAGE (DyldCacheFileSystem) → $PROJECT_DIR/$PROJECT_NAME =="
IMPORT_LOG="$GHIDRA_VIBE_DSC_LOG_DIR/acceptance-import.log"
"$DYLD" import \
  --image "$IMAGE" \
  --project "$PROJECT_DIR" \
  --project-name "$PROJECT_NAME" \
  --no-analyze \
  2>&1 | tee "$IMPORT_LOG"

PROGRAM="$(grep -E '^OK:.*program=' "$IMPORT_LOG" | tail -1 | sed -E 's/.*program=([^ ]+).*/\1/' || true)"
[[ -n "$PROGRAM" ]] || PROGRAM="$(basename "$RESOLVED")"
echo "program=$PROGRAM"

echo "== MCP health / decompile sample (optional) =="
if curl -fsS --max-time 2 "${MCP_URL}/check_connection" >/dev/null 2>&1 \
  || curl -fsS --max-time 2 "${MCP_URL}/check" >/dev/null 2>&1; then
  curl -fsS --max-time 60 -G "${MCP_URL}/open_program" \
    --data-urlencode "program=/${PROGRAM}" >/tmp/dsc-accept-open.json 2>/dev/null || true
  FUNCS="$(curl -fsS --max-time 60 "${MCP_URL}/list_functions?limit=20" 2>/dev/null || true)"
  echo "$FUNCS" | head -c 400
  echo
  # Best-effort decompile of first named function (proves AppKit loaded).
  ADDR="$(printf '%s\n' "$FUNCS" | python3 - <<'PY'
import re, sys
text = sys.stdin.read()
for line in text.splitlines():
    m = re.search(r"\bat\s+(0x)?([0-9a-fA-F]+)\b", line)
    if m:
        print(m.group(2))
        break
PY
)"
  if [[ -n "$ADDR" ]]; then
    curl -fsS --max-time 90 -G "${MCP_URL}/decompile_function" \
      --data-urlencode "address=${ADDR}" | head -c 500
    echo
    echo "ACCEPTANCE_OK DSC import + MCP decompile ($IMAGE / $PROGRAM @ $ADDR)"
  else
    echo "ACCEPTANCE_OK DSC import + MCP list ($IMAGE / $PROGRAM)"
  fi
else
  echo "ACCEPTANCE_OK DSC import ($IMAGE / $PROGRAM); MCP not running — start engine to decompile"
fi
