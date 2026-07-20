#!/usr/bin/env bash
# Agent sidebar / GuiControl /agent/* smoke (+ optional live Ollama).
set -euo pipefail
GUI_URL="${GHIDRA_VIBE_GUI_URL:-http://127.0.0.1:8091}"
AI_BASE="${GHIDRA_VIBE_AI_BASE_URL:-${AI_LOCAL_BASE_URL:-${OLLAMA_HOST:-http://127.0.0.1:11434}}}"
AI_BASE="${AI_BASE%/}"

# Always: repo bridge tool list includes agent_* (ignore stale nix-store bridges).
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE="$REPO_ROOT/nix/share/bridge_mcp_gui.py"
test -f "$BRIDGE"
python3 - <<PY
from pathlib import Path
text = Path(r"$BRIDGE").read_text()
assert "agent_send" in text and "agent_status" in text and "agent_playbook" in text
print("OK bridge agent tools present")
PY

# Optional: GuiControl live
if curl -fsS --max-time 2 "$GUI_URL/health" >/dev/null 2>&1; then
  st="$(curl -fsS --max-time 5 "$GUI_URL/agent/status")"
  echo "$st" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("ok") is True; print("OK /agent/status")'
  # Soft send — should queue even without Ollama
  curl -fsS --max-time 5 -X POST -H 'Content-Type: application/json' \
    -d '{"text":"smoke: list functions briefly"}' \
    "$GUI_URL/agent/send" >/dev/null
  echo "OK /agent/send queued"
else
  echo "SKIP GuiControl ($GUI_URL not up)"
fi

# Optional: Ollama tags (Metal local-ai)
if curl -fsS --max-time 2 "$AI_BASE/api/tags" >/dev/null 2>&1; then
  curl -fsS --max-time 5 "$AI_BASE/api/tags" | python3 -c \
    'import json,sys; d=json.load(sys.stdin); assert "models" in d; print("OK Ollama /api/tags", len(d.get("models") or []), "models")'
else
  echo "SKIP Ollama ($AI_BASE/api/tags not up)"
fi

echo "OK smoke-agent-sidebar"
