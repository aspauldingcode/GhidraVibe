#!/usr/bin/env bash
# Run every stock capability probe from CAPABILITY_MATRIX.json.
# Requires GHIDRA_INSTALL_DIR. Analysis MCP preferred; GuiControl optional unless CAPABILITY_REQUIRE_GUI=1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ARTIFACTS="${CAPABILITY_ARTIFACTS:-$ROOT/gui-tests/artifacts}"
WORKDIR="${GHIDRA_VIBE_DECOMP_WORKDIR:-/tmp/ghidra-vibe-capability}"
MATRIX="$ROOT/native-ui/parity/CAPABILITY_MATRIX.json"
GAPS="$ROOT/native-ui/parity/RUNTIME_GAPS.json"
REPORT="$ARTIFACTS/CAPABILITY_REPORT.json"
mkdir -p "$ARTIFACTS" "$WORKDIR"

if [[ -z "${GHIDRA_INSTALL_DIR:-}" ]]; then
  if [[ -d "$ROOT/result/lib/ghidra" ]]; then
    export GHIDRA_INSTALL_DIR="$ROOT/result/lib/ghidra"
  else
    echo "FAIL: set GHIDRA_INSTALL_DIR" >&2
    exit 1
  fi
fi

echo "==> regenerate capability matrix"
python3 "$ROOT/scripts/generate-capability-matrix.py"

# Compile fixture binary (same shape as smoke-decompile)
BIN="$WORKDIR/smoke_bin"
if [[ ! -x "$BIN" ]]; then
  cat >"$WORKDIR/smoke.c" <<'EOF'
#include <stdio.h>
#include <string.h>
int add(int a, int b) { return a + b; }
int secret_check(const char *s) {
  if (!s) return -1;
  return strcmp(s, "ghidravibe") == 0 ? 1 : 0;
}
int main(int argc, char **argv) {
  int x = add(argc, 7);
  if (argc > 1 && secret_check(argv[1]) == 1) { printf("ok %d\n", x); return 0; }
  printf("nope %d\n", x);
  return 1;
}
EOF
  /usr/bin/clang -O0 -g -o "$BIN" "$WORKDIR/smoke.c"
fi

# Headless-import fixture into a clean project so in-process engine opens smoke_bin
# (not a sticky DSC/AppKit lastProgram).
PROJ_DIR="$WORKDIR/CapProj"
PROJ_GPR="$PROJ_DIR/CapSmoke.gpr"
if [[ ! -f "$PROJ_GPR" ]]; then
  echo "==> headless import fixture → CapSmoke project"
  mkdir -p "$PROJ_DIR"
  if [[ -z "${JAVA_HOME:-}" && -x /usr/libexec/java_home ]]; then
    JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home)"
    export JAVA_HOME
  fi
  HEADLESS="${GHIDRA_VIBE_HEADLESS:-}"
  if [[ -z "$HEADLESS" && -x "${GHIDRA_INSTALL_DIR}/../../share/ghidra-vibe/ghidra-vibe-analyzeHeadless" ]]; then
    HEADLESS="$(cd "${GHIDRA_INSTALL_DIR}/../../share/ghidra-vibe" && pwd)/ghidra-vibe-analyzeHeadless"
  fi
  if [[ -z "$HEADLESS" ]]; then
    HEADLESS="$(command -v ghidra-vibe-analyzeHeadless || true)"
  fi
  if [[ -n "$HEADLESS" && -x "$HEADLESS" ]]; then
    "$HEADLESS" "$PROJ_DIR" CapSmoke \
      -import "$BIN" \
      -overwrite \
      -analysisTimeoutPerFile 120 \
      >"$WORKDIR/headless-import.log" 2>&1 \
      || echo "WARN: headless import failed (see $WORKDIR/headless-import.log)" >&2
  else
    echo "WARN: analyzeHeadless not found — fixture will use load_program only" >&2
  fi
fi
# Always pin the capability fixture project (ignore sticky shell env / DSC paths).
if [[ "${CAPABILITY_KEEP_PROJECT:-0}" != "1" ]]; then
  export GHIDRA_VIBE_PROJECT="$PROJ_GPR"
  export GHIDRA_VIBE_PROGRAM="/smoke_bin"
fi
# Clear sticky DSC selections that steal the current program.
defaults delete dev.ghidravibe.app ghidra.vibe.lastProject 2>/dev/null || true
defaults delete dev.ghidravibe.app ghidra.vibe.lastProgram 2>/dev/null || true
defaults write dev.ghidravibe.app ghidra.vibe.lastProject "$GHIDRA_VIBE_PROJECT"
defaults write dev.ghidravibe.app ghidra.vibe.lastProgram "smoke_bin"

# Analysis MCP (:8089) — required for M3. Prefer an already-running server; otherwise
# start via packaged app in-process engine (headless launch.sh ClassNotFound is flaky
# on this nix Ghidra tree). Set CAPABILITY_LAUNCH_GUI=1 to also wait on GuiControl.
GUI_URL="${GHIDRA_VIBE_GUI_URL:-http://127.0.0.1:8091}"
MCP_URL="${GHIDRA_MCP_URL:-http://127.0.0.1:8089}"
INSTALL="${GHIDRA_VIBE_APP_INSTALL:-$HOME/Applications/GhidraVibe.app}"

# Load nix runtime.env next to GHIDRA_INSTALL_DIR when present (engine helpers, bridges).
load_runtime_env() {
  local cand
  for cand in \
    "${GHIDRA_INSTALL_DIR}/../../share/ghidra-vibe/runtime.env" \
    "${GHIDRA_INSTALL_DIR}/../share/ghidra-vibe/runtime.env"
  do
    if [[ -f "$cand" ]]; then
      # shellcheck disable=SC1090
      set -a
      # shellcheck source=/dev/null
      source "$cand"
      set +a
      return 0
    fi
  done
  return 1
}

resolve_engine_home() {
  if [[ -n "${GHIDRA_VIBE_ENGINE_HOME:-}" && -f "${GHIDRA_VIBE_ENGINE_HOME}/lib/libghidravibe_engine.dylib" ]]; then
    echo "$GHIDRA_VIBE_ENGINE_HOME"
    return
  fi
  # Latest built engine derivation (dev machines); prefer explicit env in CI.
  local hit
  hit="$(ls -dt /nix/store/*-ghidra-vibe-engine-0.1.0 2>/dev/null | head -1 || true)"
  if [[ -n "$hit" && -f "$hit/lib/libghidravibe_engine.dylib" ]]; then
    echo "$hit"
    return
  fi
  return 1
}

start_analysis_via_app() {
  echo "==> start analysis MCP via GhidraVibe in-process engine"
  defaults write dev.ghidravibe.app ghidra.vibe.userAgreementAccepted -bool true
  defaults write dev.ghidravibe.app ghidra.vibe.welcomeHelpSeen -bool true
  defaults write dev.ghidravibe.app ghidra.vibe.smokeStartProject -bool true
  if [[ ! -d "$INSTALL" ]]; then
    if [[ ! -d "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app" ]]; then
      "$ROOT/macos/GhidraVibe/scripts/package-app.sh" "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app"
    fi
    mkdir -p "$(dirname "$INSTALL")"
    rm -rf "$INSTALL"
    cp -R "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app" "$INSTALL"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL" || true
  fi

  load_runtime_env || true
  export GHIDRA_INSTALL_DIR
  export GHIDRA_VIBE_ENGINE=inprocess
  export GHIDRA_MCP_URL="$MCP_URL"
  export GHIDRA_VIBE_MCP_HEADLESS="${GHIDRA_VIBE_MCP_HEADLESS:-$ROOT/scripts/ghidra-vibe-mcp-headless}"
  export GHIDRA_VIBE_PROJECT
  export GHIDRA_VIBE_PROGRAM
  if eng_home="$(resolve_engine_home)"; then
    export GHIDRA_VIBE_ENGINE_HOME="$eng_home"
    export GHIDRA_VIBE_ENGINE_LIB="${GHIDRA_VIBE_ENGINE_LIB:-$eng_home/lib/libghidravibe_engine.dylib}"
    export GHIDRA_VIBE_ENGINE_CLASSPATH_FILE="${GHIDRA_VIBE_ENGINE_CLASSPATH_FILE:-$eng_home/share/ghidra-vibe/engine/classpath.txt}"
  fi
  if [[ -z "${JAVA_HOME:-}" ]]; then
    if [[ -x /usr/libexec/java_home ]]; then
      JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home 2>/dev/null || true)"
      export JAVA_HOME
    fi
  fi

  pkill -x GhidraVibe 2>/dev/null || true
  sleep 1
  # Direct exec keeps env (open(1) often drops GHIDRA_* for sandboxed LaunchServices).
  # Do not reuse $BIN — that name is the fixture Mach-O for probes.
  APP_BIN="$INSTALL/Contents/MacOS/GhidraVibe"
  if [[ ! -x "$APP_BIN" ]]; then
    echo "FAIL: missing $APP_BIN" >&2
    return 1
  fi
  echo "    ENGINE_HOME=${GHIDRA_VIBE_ENGINE_HOME:-unset} PROJECT=${GHIDRA_VIBE_PROJECT:-unset}"
  "$APP_BIN" >"$ARTIFACTS/ghidravibe-app.log" 2>&1 &
  echo $! >"$ARTIFACTS/ghidravibe-app.pid"
  for i in $(seq 1 120); do
    if curl -fsS --max-time 2 "$MCP_URL/check_connection" >/dev/null 2>&1; then
      echo "analysis MCP up after ${i}s (in-process)"
      return 0
    fi
    sleep 1
  done
  echo "WARN: app log tail:" >&2
  tail -40 "$ARTIFACTS/ghidravibe-app.log" >&2 || true
  return 1
}

if [[ "${CAPABILITY_LAUNCH_GUI:-0}" == "1" ]]; then
  echo "==> package + launch GhidraVibe for GuiControl + analysis"
  defaults write dev.ghidravibe.app ghidra.vibe.userAgreementAccepted -bool true
  defaults write dev.ghidravibe.app ghidra.vibe.welcomeHelpSeen -bool true
  defaults write dev.ghidravibe.app ghidra.vibe.smokeStartProject -bool true
  "$ROOT/macos/GhidraVibe/scripts/package-app.sh" "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app"
  rm -rf "$INSTALL"
  cp -R "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app" "$INSTALL"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL" || true
  export GHIDRA_VIBE_ENGINE="${GHIDRA_VIBE_ENGINE:-inprocess}"
  open -n -a "$INSTALL" --env GHIDRA_INSTALL_DIR="$GHIDRA_INSTALL_DIR" \
    --env GHIDRA_VIBE_ENGINE=inprocess \
    --env GHIDRA_MCP_URL="$MCP_URL" 2>/dev/null \
    || open -n "$INSTALL"
  for i in $(seq 1 90); do
    if curl -fsS --max-time 2 "$GUI_URL/health" >/dev/null 2>&1; then
      echo "GuiControl up after ${i}s"
      export CAPABILITY_REQUIRE_GUI=1
      break
    fi
    sleep 1
  done
fi

if curl -fsS --max-time 2 "$MCP_URL/check_connection" >/dev/null 2>&1; then
  echo "==> analysis MCP reachable"
elif [[ "${CAPABILITY_START_ANALYSIS:-1}" == "1" ]]; then
  if ! start_analysis_via_app; then
    echo "FAIL: could not start analysis MCP at $MCP_URL" >&2
    exit 1
  fi
else
  echo "FAIL: analysis MCP not at $MCP_URL (set CAPABILITY_START_ANALYSIS=1 or start engine)" >&2
  exit 1
fi

# Ensure vibe MCP is up for vibe_list_* / debugger_list / comments / scripts probes.
# Prefer repo PYTHONPATH so capability fallbacks (vibe_list_comments, debugger_list, …) are present.
VIBE_URL="${GHIDRA_VIBE_MCP_EXT_URL:-http://127.0.0.1:8092}"
VIBE_PORT="${GHIDRA_VIBE_MCP_EXT_PORT:-8092}"
need_vibe_restart=0
if ! curl -fsS --max-time 2 "$VIBE_URL/health" >/dev/null 2>&1; then
  need_vibe_restart=1
elif ! curl -fsS --max-time 5 -X POST "$VIBE_URL/debugger_list" \
    -H 'Content-Type: application/json' -d '{"provider":"breakpoints"}' 2>/dev/null \
    | grep -q 'has_target'; then
  echo "==> vibe MCP stale (missing debugger_list) — restarting from repo"
  need_vibe_restart=1
fi
if [[ "$need_vibe_restart" == "1" ]]; then
  if command -v /usr/sbin/lsof >/dev/null 2>&1; then
    for pid in $(/usr/sbin/lsof -tiTCP:"$VIBE_PORT" -sTCP:LISTEN 2>/dev/null || true); do
      # Only kill python vibe_mcp listeners — never touch analysis MCP (:8089).
      cmd=$(ps -p "$pid" -o command= 2>/dev/null || true)
      if [[ "$cmd" == *vibe_mcp* || "$cmd" == *ghidra-vibe-mcp-ext* ]]; then
        kill "$pid" 2>/dev/null || true
      fi
    done
    sleep 1
  fi
  echo "==> start vibe MCP ($VIBE_URL) from repo scripts/lib"
  # Run from scripts/lib so `python3 -m vibe_mcp` cannot pick a stale site-packages build.
  export GHIDRA_MCP_ALLOW_SCRIPTS="${GHIDRA_MCP_ALLOW_SCRIPTS:-1}"
  export GHIDRA_MCP_URL="$MCP_URL"
  (
    cd "$ROOT/scripts/lib"
    exec /usr/bin/python3 -m vibe_mcp --host 127.0.0.1 --port "$VIBE_PORT"
  ) >"$ARTIFACTS/vibe-mcp.log" 2>&1 &
  echo $! >"$ARTIFACTS/vibe-mcp.pid"
  for i in $(seq 1 20); do
    if curl -fsS --max-time 2 "$VIBE_URL/health" >/dev/null 2>&1; then
      echo "vibe MCP up after ${i}s"
      break
    fi
    sleep 1
  done
else
  echo "==> vibe MCP reachable (capability handlers present)"
fi

if ! curl -fsS --max-time 2 "${GHIDRA_MCP_URL:-http://127.0.0.1:8089}/check_connection" >/dev/null 2>&1; then
  echo "FAIL: analysis MCP went down before probes (required for M3)" >&2
  exit 1
fi

echo "==> run capability probes"
set +e
python3 "$ROOT/scripts/lib/capability_probes.py" "$BIN"
rc=$?
set -e

python3 - <<PY
import json, sys
from pathlib import Path
rep = json.loads(Path("$REPORT").read_text())
c = rep["counts"]
pc = rep.get("pass_class") or {}
print(
    f"Capability report: total={rep['total']} passed={c.get('passed')} "
    f"failed={c.get('failed')} unmapped={c.get('unmapped')} "
    f"runtime_gap={c.get('runtime_gap')} coverage={rep.get('coverage_pct')}% "
    f"hard={rep.get('hard_coverage_pct')}% "
    f"(hard={pc.get('hard')} honest={pc.get('honest')} catalog={pc.get('catalog')} "
    f"soft={pc.get('soft')} deferred={pc.get('deferred')})"
)
fails = [r for r in rep["results"] if r["status"] in ("failed", "unmapped")]
for r in fails[:40]:
    print(f"  FAIL {r['id']}: {r.get('detail','')[:120]}")
if len(fails) > 40:
    print(f"  … +{len(fails)-40} more")
sys.exit($rc)
PY
exit "$rc"
