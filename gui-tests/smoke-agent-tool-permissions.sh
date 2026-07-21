#!/usr/bin/env bash
# Agent advanced tool calling + Cursor-style permissions (GuiControl).
set -euo pipefail
GUI="${GHIDRA_VIBE_GUI_URL:-http://127.0.0.1:8091}"
if ! curl -fsS --max-time 2 "$GUI/health" >/dev/null 2>&1; then
  echo "SKIP: GuiControlServer not running"
  exit 0
fi

# Reset to known defaults.
curl -fsS -X POST "$GUI/agent/permissions/reset" -H 'Content-Type: application/json' -d '{}' >/dev/null

# Default profile should ask on mutate/network.
perm="$(curl -fsS "$GUI/agent/permissions")"
echo "$perm" | grep -q '"profile":"askWrites"' || {
  echo "FAIL: expected askWrites after reset: $perm" >&2
  exit 1
}
echo "$perm" | grep -q '"sandbox":true' || {
  echo "FAIL: expected sandbox on after reset: $perm" >&2
  exit 1
}

# Read tool should run without approval (promptIfNeeded=false still allows reads).
read_out="$(curl -fsS -X POST "$GUI/agent/tool" -H 'Content-Type: application/json' \
  -d '{"name":"gui_state","args":{}}')"
echo "$read_out" | grep -q '"ok"' || echo "$read_out" | grep -qi 'toolMode\|currentProgram\|agentEnabled' || {
  echo "FAIL: gui_state should execute under askWrites: $read_out" >&2
  exit 1
}

# Write tool without auto_approve should require approval (not hang).
write_out="$(curl -fsS -X POST "$GUI/agent/tool" -H 'Content-Type: application/json' \
  -d '{"name":"rename_function","args":{"new_name":"smoke_denied","address":"0x0"},"auto_approve":false}')"
echo "$write_out" | grep -q 'needs_approval\|approval required' || {
  echo "FAIL: rename_function should need approval: $write_out" >&2
  exit 1
}

# Network tool should also ask under askWrites.
net_out="$(curl -fsS -X POST "$GUI/agent/tool" -H 'Content-Type: application/json' \
  -d '{"name":"web_search","args":{"query":"ghidra","limit":1},"auto_approve":false}')"
echo "$net_out" | grep -q 'needs_approval\|approval required' || {
  echo "FAIL: web_search should need approval: $net_out" >&2
  exit 1
}

# Always-allow profile + auto_approve path for advanced calling.
curl -fsS -X POST "$GUI/agent/permissions" -H 'Content-Type: application/json' \
  -d '{"profile":"allowAlways"}' >/dev/null
allowed="$(curl -fsS -X POST "$GUI/agent/tool" -H 'Content-Type: application/json' \
  -d '{"name":"gui_state","args":{},"auto_approve":true}')"
echo "$allowed" | grep -Eq 'ok|toolMode|agentEnabled|currentProgram' || {
  echo "FAIL: gui_state with allowAlways failed: $allowed" >&2
  exit 1
}

# Always deny a specific tool.
curl -fsS -X POST "$GUI/agent/permissions" -H 'Content-Type: application/json' \
  -d '{"tool":"web_search","decision":"alwaysDeny"}' >/dev/null
denied="$(curl -fsS -X POST "$GUI/agent/tool" -H 'Content-Type: application/json' \
  -d '{"name":"web_search","args":{"query":"x"},"auto_approve":true}')"
echo "$denied" | grep -qi 'deny\|denied' || {
  echo "FAIL: alwaysDeny web_search should block even with auto_approve: $denied" >&2
  exit 1
}

# Reset restores askWrites.
curl -fsS -X POST "$GUI/agent/permissions/reset" -H 'Content-Type: application/json' -d '{}' >/dev/null
perm2="$(curl -fsS "$GUI/agent/permissions")"
echo "$perm2" | grep -q '"profile":"askWrites"' || {
  echo "FAIL: reset did not restore askWrites: $perm2" >&2
  exit 1
}

echo "OK smoke-agent-tool-permissions"
