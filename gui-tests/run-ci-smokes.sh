#!/usr/bin/env bash
# Run the same smoke/acceptance steps as .github/workflows/gui-smoke.yml + dsc-acceptance.yml.
# Usage: ./gui-tests/run-ci-smokes.sh [--skip-package] [--skip-appkit] [--skip-ax]
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/nix/var/nix/profiles/default/bin:${PATH:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SKIP_PACKAGE=0
SKIP_APPKIT=0
SKIP_AX=0
for a in "$@"; do
  case "$a" in
    --skip-package) SKIP_PACKAGE=1 ;;
    --skip-appkit) SKIP_APPKIT=1 ;;
    --skip-ax) SKIP_AX=1 ;;
  esac
done

REPORT="${CI_SMOKE_REPORT:-$ROOT/gui-tests/artifacts/ci-smoke-report.txt}"
mkdir -p "$(dirname "$REPORT")" "$ROOT/gui-tests/artifacts"
: >"$REPORT"

pass=0
fail=0
skip=0

log() { printf '%s\n' "$*" | tee -a "$REPORT"; }

run_step() {
  local name="$1"
  shift
  log ""
  log "======== $name ========"
  local start=$SECONDS
  if "$@"; then
    local elapsed=$((SECONDS - start))
    log "PASS ($elapsed s): $name"
    pass=$((pass + 1))
    return 0
  else
    local rc=$?
    local elapsed=$((SECONDS - start))
    log "FAIL rc=$rc ($elapsed s): $name"
    fail=$((fail + 1))
    return "$rc"
  fi
}

# --- env (same as CI) ---
chmod +x gui-tests/*.sh scripts/*.sh 2>/dev/null || true
export GHIDRA_VIBE_DYLD="${GHIDRA_VIBE_DYLD:-$ROOT/scripts/ghidra-vibe-dyld}"
export GHIDRA_VIBE_SCRIPT_PATH="${GHIDRA_VIBE_SCRIPT_PATH:-$ROOT/ghidra_scripts}"
export GHIDRA_VIBE_HEADLESS="${GHIDRA_VIBE_HEADLESS:-$ROOT/scripts/ghidra-vibe-analyzeHeadless}"

if [[ -z "${GHIDRA_INSTALL_DIR:-}" ]]; then
  if [[ -d "$ROOT/result/lib/ghidra" ]]; then
    export GHIDRA_INSTALL_DIR="$ROOT/result/lib/ghidra"
  else
    cand="$(ls -dt /nix/store/*-ghidra-vibe-*+native-*/lib/ghidra 2>/dev/null | head -1 || true)"
    [[ -n "$cand" ]] && export GHIDRA_INSTALL_DIR="$cand"
  fi
fi
if [[ -z "${JAVA_HOME:-}" && -x /usr/libexec/java_home ]]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home)"
  export JAVA_HOME
fi
if [[ -z "${GHIDRA_VIBE_ENGINE_HOME:-}" ]]; then
  eng="$(ls -dt /nix/store/*-ghidra-vibe-engine-0.1.0 2>/dev/null | head -1 || true)"
  [[ -n "$eng" ]] && export GHIDRA_VIBE_ENGINE_HOME="$eng"
fi
if [[ -z "${GHIDRA_VIBE_DSC_INDEX:-}" && -x "$ROOT/rust/target/release/ghidra-vibe-dsc-index" ]]; then
  export GHIDRA_VIBE_DSC_INDEX="$ROOT/rust/target/release/ghidra-vibe-dsc-index"
fi

log "GHIDRA_INSTALL_DIR=${GHIDRA_INSTALL_DIR:-}"
log "JAVA_HOME=${JAVA_HOME:-}"
log "GHIDRA_VIBE_ENGINE_HOME=${GHIDRA_VIBE_ENGINE_HOME:-}"
log "GHIDRA_VIBE_DSC_INDEX=${GHIDRA_VIBE_DSC_INDEX:-}"

# Kill leftover app so fixture imports aren't locked.
pkill -x GhidraVibe 2>/dev/null || true
sleep 1

if [[ "$SKIP_PACKAGE" -eq 0 ]]; then
  run_step "package-app" ./macos/GhidraVibe/scripts/package-app.sh || true
  run_step "register-app" bash -c '
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/GhidraVibe.app"
    cp -R macos/GhidraVibe/.build/GhidraVibe.app "$HOME/Applications/"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/GhidraVibe.app"
  ' || true
else
  log "SKIP: package/register (--skip-package)"
  skip=$((skip + 2))
fi

run_step "smoke-agent-api-config" ./gui-tests/smoke-agent-api-config.sh || true
run_step "smoke-agent-welcome" ./gui-tests/smoke-agent-welcome.sh || true
run_step "smoke-agent-sidebar" ./gui-tests/smoke-agent-sidebar.sh || true
run_step "smoke-agent-tool-permissions" ./gui-tests/smoke-agent-tool-permissions.sh || true
run_step "smoke-agent-npu" ./gui-tests/smoke-agent-npu.sh || true
run_step "smoke-help" ./gui-tests/smoke-help.sh || true
run_step "check-stock-help" ./scripts/check-stock-help.sh || true

run_step "smoke-decompile" ./gui-tests/smoke-decompile.sh || true
run_step "smoke-whoami-decompile" ./gui-tests/smoke-whoami-decompile.sh || true
run_step "smoke-function-graph" env GRAPH_REPACKAGE=0 ./gui-tests/smoke-function-graph.sh || true

if [[ "$SKIP_APPKIT" -eq 0 ]]; then
  run_step "smoke-appkit-decompile" env APPKIT_FORCE_IMPORT=1 ./gui-tests/smoke-appkit-decompile.sh || true
  run_step "smoke-appkit-classes" ./gui-tests/smoke-appkit-classes.sh || true
  run_step "acceptance-dsc-import" ./gui-tests/acceptance-dsc-import.sh || true
else
  log "SKIP: AppKit / DSC acceptance (--skip-appkit)"
  skip=$((skip + 3))
fi

run_step "check-capability-matrix" ./scripts/check-capability-matrix.sh || true
run_step "run-stock-capability-suite" ./gui-tests/run-stock-capability-suite.sh || true

if [[ "$SKIP_AX" -eq 0 ]]; then
  export AGENT_DEVICE_MACOS_HELPER_BIN="${AGENT_DEVICE_MACOS_HELPER_BIN:-$HOME/.agent-device/macos-helper/current/agent-device-macos-helper}"
  run_step "run-smoke (AX)" ./gui-tests/run-smoke.sh || true
else
  log "SKIP: AX run-smoke (--skip-ax)"
  skip=$((skip + 1))
fi

log ""
log "======== SUMMARY ========"
log "pass=$pass fail=$fail skip=$skip"
log "report=$REPORT"

if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
