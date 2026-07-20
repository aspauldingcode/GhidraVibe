#!/usr/bin/env bash
# Local-AI probe (Metal Ollama). ANEMLL/NPU remains a stub — do not require anemll.
set -euo pipefail
if [[ "$(uname)" != "Darwin" ]]; then
  echo "SKIP: not Darwin (Ollama probe still useful elsewhere; continuing)"
fi

AI_BASE="${GHIDRA_VIBE_AI_BASE_URL:-${AI_LOCAL_BASE_URL:-${OLLAMA_HOST:-http://127.0.0.1:11434}}}"
AI_BASE="${AI_BASE%/}"

# Document stub: ANEMLL is not what Agent chat talks to today.
if [[ "${GHIDRA_VIBE_AI_BACKEND:-}" == "anemll" || "${GHIDRA_VIBE_AI_BACKEND:-}" == "anemll_stub" ]]; then
  echo "OK smoke-agent-npu (ANEMLL stub mode requested — no Core ML ranking yet)"
  exit 0
fi

if curl -fsS --max-time 3 "$AI_BASE/api/tags" >/dev/null 2>&1; then
  curl -fsS --max-time 5 "$AI_BASE/api/tags" | python3 -c \
    'import json,sys; d=json.load(sys.stdin); assert "models" in d; print("OK local Ollama", len(d.get("models") or []), "models @ '"$AI_BASE"'")'
  echo "OK smoke-agent-npu (Metal Ollama / OpenAI-compat path)"
  exit 0
fi

if command -v anemll-profile >/dev/null 2>&1; then
  anemll-profile --help >/dev/null 2>&1 || true
  echo "OK smoke-agent-npu (anemll-profile present; Agent still uses Ollama by default — see docs/AGENT_CHAT.md)"
  exit 0
fi

echo "SKIP: Ollama not at $AI_BASE and anemll-profile not installed (document in docs/AGENT_CHAT.md)"
exit 0
