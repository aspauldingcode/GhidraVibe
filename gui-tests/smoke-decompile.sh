#!/usr/bin/env bash
# Smoke: compile a tiny Mach-O, analyze, and assert real decompiler C output.
# Covers (1) analyzeHeadless + DumpDecompileSample and (2) analysis MCP when up.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="${GHIDRA_VIBE_DECOMP_WORKDIR:-/tmp/ghidra-vibe-decomp-smoke}"
MCP_URL="${GHIDRA_MCP_URL:-http://127.0.0.1:8089}"
BIN="$WORKDIR/smoke_bin"
SRC="$WORKDIR/smoke.c"
PROJ="$WORKDIR/project"
LOG="$WORKDIR/headless.log"

if [[ -z "${GHIDRA_INSTALL_DIR:-}" && -d "$ROOT/result/lib/ghidra" ]]; then
  export GHIDRA_INSTALL_DIR="$ROOT/result/lib/ghidra"
fi

load_runtime_env() {
  local cand
  for cand in \
    "${GHIDRA_INSTALL_DIR:-}/../../share/ghidra-vibe/runtime.env" \
    "${GHIDRA_INSTALL_DIR:-}/../share/ghidra-vibe/runtime.env"
  do
    if [[ -f "$cand" ]]; then
      set -a
      # shellcheck disable=SC1090
      source "$cand"
      set +a
      return 0
    fi
  done
  return 1
}

# launch.sh needs a JDK without TTY; prefer runtime.env then java_home.
load_runtime_env || true
if [[ -z "${JAVA_HOME:-}" && -x /usr/libexec/java_home ]]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home)"
  export JAVA_HOME
fi
if [[ -n "${JAVA_HOME:-}" ]]; then
  export PATH="${JAVA_HOME}/bin:${PATH}"
fi

resolve_headless() {
  if [[ -n "${GHIDRA_VIBE_HEADLESS:-}" && -x "${GHIDRA_VIBE_HEADLESS}" ]]; then
    echo "${GHIDRA_VIBE_HEADLESS}"
    return
  fi
  if [[ -n "${GHIDRA_INSTALL_DIR:-}" && -x "${GHIDRA_INSTALL_DIR}/../../share/ghidra-vibe/ghidra-vibe-analyzeHeadless" ]]; then
    echo "$(cd "${GHIDRA_INSTALL_DIR}/../../share/ghidra-vibe" && pwd)/ghidra-vibe-analyzeHeadless"
    return
  fi
  if command -v ghidra-vibe-analyzeHeadless >/dev/null 2>&1; then
    command -v ghidra-vibe-analyzeHeadless
    return
  fi
  if command -v ghidra-analyzeHeadless >/dev/null 2>&1; then
    command -v ghidra-analyzeHeadless
    return
  fi
  echo "FAIL: analyzeHeadless not found (set GHIDRA_INSTALL_DIR or GHIDRA_VIBE_HEADLESS)" >&2
  exit 1
}

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR" "$PROJ"

cat >"$SRC" <<'EOF'
#include <stdio.h>
#include <string.h>

int add(int a, int b) {
    return a + b;
}

int secret_check(const char *s) {
    if (s == NULL) return -1;
    if (strcmp(s, "ghidravibe") == 0) return 1;
    return 0;
}

int main(int argc, char **argv) {
    int x = add(argc, 7);
    if (argc > 1 && secret_check(argv[1]) == 1) {
        printf("ok %d\n", x);
        return 0;
    }
    printf("nope %d\n", x);
    return 1;
}
EOF

clang -O0 -g -o "$BIN" "$SRC"
file "$BIN" | tee "$WORKDIR/file.txt"
# Refresh GUI fixture with a real Mach-O (not a 4-byte magic stub).
FIXTURE_BIN="$ROOT/gui-tests/fixtures/Smoke.app/Contents/MacOS/Smoke"
if [[ -d "$(dirname "$FIXTURE_BIN")" ]]; then
  cp -f "$BIN" "$FIXTURE_BIN"
  chmod +x "$FIXTURE_BIN"
fi

mkdir -p "${HOME}/Library/ghidra-vibe/settings"
grep -q '^USER_AGREEMENT=ACCEPT' "${HOME}/Library/ghidra-vibe/settings/preferences" 2>/dev/null \
  || echo 'USER_AGREEMENT=ACCEPT' >"${HOME}/Library/ghidra-vibe/settings/preferences"

HEADLESS="$(resolve_headless)"
export GHIDRA_VIBE_DECOMP_FILTER=secret
export GHIDRA_VIBE_DECOMP_ALLOW_FUN=1

echo "==> headless import + DumpDecompileSample ($HEADLESS)"
"$HEADLESS" "$PROJ" DecompSmoke \
  -import "$BIN" \
  -overwrite \
  -analysisTimeoutPerFile 180 \
  -scriptPath "$ROOT/ghidra_scripts" \
  -postScript DumpDecompileSample.java \
  >"$LOG" 2>&1

if ! grep -q 'DECOMP secret_check' "$LOG"; then
  echo "FAIL: headless did not dump secret_check" >&2
  tail -80 "$LOG" >&2
  exit 1
fi
if ! grep -q 'ghidravibe' "$LOG"; then
  echo "FAIL: decomp missing strcmp literal ghidravibe" >&2
  exit 1
fi
if ! grep -qE 'return local_14|return -1|return 1' "$LOG"; then
  echo "FAIL: decomp missing return structure" >&2
  exit 1
fi
echo "PASS: headless decompile secret_check (DWARF names + C body)"

# --- MCP path (required unless DECOMP_SKIP_MCP=1) ---
mcp_up() {
  curl -fsS --max-time 2 "${MCP_URL}/check_connection" >/dev/null 2>&1 \
    || curl -fsS --max-time 2 "${MCP_URL}/check" >/dev/null 2>&1
}

start_mcp_via_app() {
  echo "==> start analysis MCP via GhidraVibe in-process engine"
  local install="${GHIDRA_VIBE_APP_INSTALL:-$HOME/Applications/GhidraVibe.app}"
  local gpr="$PROJ/DecompSmoke.gpr"
  if [[ -z "${GHIDRA_INSTALL_DIR:-}" ]]; then
    echo "FAIL: GHIDRA_INSTALL_DIR required to start in-process MCP" >&2
    return 1
  fi
  load_runtime_env || true
  if [[ -z "${JAVA_HOME:-}" && -x /usr/libexec/java_home ]]; then
    JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home)"
    export JAVA_HOME
  fi
  if [[ -z "${GHIDRA_VIBE_ENGINE_HOME:-}" ]]; then
    GHIDRA_VIBE_ENGINE_HOME="$(ls -dt /nix/store/*-ghidra-vibe-engine-0.1.0 2>/dev/null | head -1 || true)"
    export GHIDRA_VIBE_ENGINE_HOME
  fi
  if [[ -n "${GHIDRA_VIBE_ENGINE_HOME:-}" ]]; then
    export GHIDRA_VIBE_ENGINE_LIB="${GHIDRA_VIBE_ENGINE_LIB:-$GHIDRA_VIBE_ENGINE_HOME/lib/libghidravibe_engine.dylib}"
    export GHIDRA_VIBE_ENGINE_CLASSPATH_FILE="${GHIDRA_VIBE_ENGINE_CLASSPATH_FILE:-$GHIDRA_VIBE_ENGINE_HOME/share/ghidra-vibe/engine/classpath.txt}"
  fi
  defaults write dev.ghidravibe.app ghidra.vibe.userAgreementAccepted -bool true
  defaults write dev.ghidravibe.app ghidra.vibe.welcomeHelpSeen -bool true
  defaults write dev.ghidravibe.app ghidra.vibe.smokeStartProject -bool true
  defaults delete dev.ghidravibe.app ghidra.vibe.lastProject 2>/dev/null || true
  defaults delete dev.ghidravibe.app ghidra.vibe.lastProgram 2>/dev/null || true
  if [[ -f "$gpr" ]]; then
    defaults write dev.ghidravibe.app ghidra.vibe.lastProject "$gpr"
    defaults write dev.ghidravibe.app ghidra.vibe.lastProgram "smoke_bin"
    export GHIDRA_VIBE_PROJECT="$gpr"
    export GHIDRA_VIBE_PROGRAM="/smoke_bin"
  fi
  if [[ ! -d "$install" ]]; then
    if [[ ! -d "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app" ]]; then
      "$ROOT/macos/GhidraVibe/scripts/package-app.sh" "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app"
    fi
    mkdir -p "$(dirname "$install")"
    rm -rf "$install"
    cp -R "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app" "$install"
  fi
  pkill -x GhidraVibe 2>/dev/null || true
  sleep 1
  export GHIDRA_INSTALL_DIR GHIDRA_VIBE_ENGINE=inprocess GHIDRA_MCP_URL="$MCP_URL"
  export GHIDRA_VIBE_MCP_HEADLESS="${GHIDRA_VIBE_MCP_HEADLESS:-$ROOT/scripts/ghidra-vibe-mcp-headless}"
  "$install/Contents/MacOS/GhidraVibe" >"$WORKDIR/ghidravibe-app.log" 2>&1 &
  echo $! >"$WORKDIR/ghidravibe-app.pid"
  local i
  for i in $(seq 1 90); do
    if mcp_up; then
      echo "analysis MCP up after ${i}s"
      return 0
    fi
    sleep 1
  done
  echo "FAIL: analysis MCP did not start (see $WORKDIR/ghidravibe-app.log)" >&2
  tail -40 "$WORKDIR/ghidravibe-app.log" >&2 || true
  return 1
}

if ! mcp_up; then
  if [[ "${DECOMP_SKIP_MCP:-0}" == "1" ]]; then
    echo "SKIP: analysis MCP not at ${MCP_URL} (DECOMP_SKIP_MCP=1)"
    exit 0
  fi
  start_mcp_via_app
fi

echo "==> MCP open/load + decompile_function"
# Prefer project program from headless import; fall back to load_program.
curl -fsS --max-time 60 -X POST "${MCP_URL}/open_program" \
  -H 'Content-Type: application/json' \
  -d '{"program":"/smoke_bin"}' >"$WORKDIR/mcp-open.json" 2>/dev/null \
  || curl -fsS --max-time 120 -X POST "${MCP_URL}/load_program" \
    -H 'Content-Type: application/json' \
    -d "{\"file\":\"${BIN}\"}" >"$WORKDIR/mcp-load.json"

curl -fsS --max-time 300 -X POST "${MCP_URL}/run_analysis" \
  -H 'Content-Type: application/json' \
  -d '{}' >"$WORKDIR/mcp-analyze.json" 2>/dev/null || true

DECOMP=""
for addr in "100000480" "0x100000480" "00000480"; do
  DECOMP="$(curl -fsS --max-time 90 -G "${MCP_URL}/decompile_function" \
    --data-urlencode "address=${addr}" 2>/dev/null || true)"
  if [[ -n "$DECOMP" && "$DECOMP" != *'"error"'* ]]; then
    break
  fi
done
# Name-based fallback (some MCP builds accept name=)
if [[ -z "$DECOMP" || "$DECOMP" == *'"error"'* ]]; then
  DECOMP="$(curl -fsS --max-time 90 -G "${MCP_URL}/decompile_function" \
    --data-urlencode "name=secret_check" 2>/dev/null || true)"
fi
printf '%s\n' "$DECOMP" >"$WORKDIR/mcp-decomp.txt"

if ! grep -qE 'FUN_|secret_check|undefined4|int ' "$WORKDIR/mcp-decomp.txt"; then
  echo "FAIL: MCP decompile empty/error: $DECOMP" >&2
  exit 1
fi
if ! grep -qE 'return |local_14|param_|ghidravibe' "$WORKDIR/mcp-decomp.txt"; then
  echo "FAIL: MCP decompile missing C structure" >&2
  cat "$WORKDIR/mcp-decomp.txt" >&2
  exit 1
fi
echo "PASS: MCP decompile_function returned C pseudocode"
echo "OK smoke-decompile (headless + MCP)"
exit 0
