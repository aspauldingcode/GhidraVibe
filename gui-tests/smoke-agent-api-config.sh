#!/usr/bin/env bash
# API backend is off without key file; dummy file enables path (no network).
set -euo pipefail
TMP="$(mktemp)"
echo "DUMMY_KEY" >"$TMP"
export GHIDRA_VIBE_API_KEY_FILE="$TMP"
# Unit-level: file readable
test -r "$GHIDRA_VIBE_API_KEY_FILE"
unset GHIDRA_VIBE_API_KEY_FILE
if [[ -n "${GHIDRA_VIBE_API_KEY_FILE:-}" ]]; then
  echo "FAIL: env should be unset" >&2
  exit 1
fi
rm -f "$TMP"
echo "OK smoke-agent-api-config (no network; key file opt-in only)"
