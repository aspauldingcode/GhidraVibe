#!/usr/bin/env bash
# GUI smoke: open whoami in the live GhidraVibe app, decompile entry via GuiControl,
# and assert real C in /state decompilePreview.
#
# Fixture prep may use analyzeHeadless to build a clean .gpr (avoids sticky DSC/AppKit).
# The decompile assertion is GUI-only (GuiControl + in-process engine) — not DumpDecompileSample.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="${GHIDRA_VIBE_WHOAMI_WORKDIR:-/tmp/ghidra-vibe-whoami-gui}"
MCP_URL="${GHIDRA_MCP_URL:-http://127.0.0.1:8089}"
GUI_URL="${GHIDRA_VIBE_GUI_URL:-http://127.0.0.1:8091}"
INSTALL="${GHIDRA_VIBE_APP_INSTALL:-$HOME/Applications/GhidraVibe.app}"
BIN="$WORKDIR/whoami"
PROJ_DIR="$WORKDIR/project"
PROJ_GPR="$PROJ_DIR/WhoamiGUI.gpr"
ARTIFACTS="${AD_ARTIFACTS:-$ROOT/gui-tests/artifacts}"
mkdir -p "$ARTIFACTS"

resolve_ghidra_install_dir() {
  if [[ -n "${GHIDRA_INSTALL_DIR:-}" && -x "${GHIDRA_INSTALL_DIR}/support/launch.sh" ]]; then
    echo "$GHIDRA_INSTALL_DIR"
    return 0
  fi
  if [[ -x "$ROOT/result/lib/ghidra/support/launch.sh" ]]; then
    echo "$ROOT/result/lib/ghidra"
    return 0
  fi
  # Prefer +native nix builds (GUI/in-process), then any ghidra-vibe with launch.sh.
  local d
  for d in \
    $(ls -dt /nix/store/*-ghidra-vibe-*+native-*/lib/ghidra 2>/dev/null || true) \
    $(ls -dt /nix/store/*-ghidra-vibe-*/lib/ghidra 2>/dev/null || true)
  do
    if [[ -x "$d/support/launch.sh" ]]; then
      echo "$d"
      return 0
    fi
  done
  if command -v nix >/dev/null 2>&1; then
    echo "resolving GHIDRA_INSTALL_DIR via nix build .#ghidra-vibe …" >&2
    d="$(nix build "$ROOT#ghidra-vibe" --no-link --print-out-paths 2>/dev/null | head -1 || true)"
    if [[ -n "$d" && -x "$d/lib/ghidra/support/launch.sh" ]]; then
      echo "$d/lib/ghidra"
      return 0
    fi
  fi
  return 1
}

if ! GHIDRA_INSTALL_DIR="$(resolve_ghidra_install_dir)"; then
  echo "FAIL: could not find Ghidra install (set GHIDRA_INSTALL_DIR or nix build .#ghidra-vibe)" >&2
  exit 1
fi
export GHIDRA_INSTALL_DIR
echo "GHIDRA_INSTALL_DIR=$GHIDRA_INSTALL_DIR"

load_runtime_env() {
  local cand
  for cand in \
    "${GHIDRA_INSTALL_DIR}/../../share/ghidra-vibe/runtime.env" \
    "${GHIDRA_INSTALL_DIR}/../share/ghidra-vibe/runtime.env"
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

resolve_headless() {
  if [[ -n "${GHIDRA_VIBE_HEADLESS:-}" && -x "${GHIDRA_VIBE_HEADLESS}" ]]; then
    echo "${GHIDRA_VIBE_HEADLESS}"
    return
  fi
  if [[ -x "${GHIDRA_INSTALL_DIR}/../../share/ghidra-vibe/ghidra-vibe-analyzeHeadless" ]]; then
    echo "$(cd "${GHIDRA_INSTALL_DIR}/../../share/ghidra-vibe" && pwd)/ghidra-vibe-analyzeHeadless"
    return
  fi
  if command -v ghidra-vibe-analyzeHeadless >/dev/null 2>&1; then
    command -v ghidra-vibe-analyzeHeadless
    return
  fi
  echo "FAIL: analyzeHeadless not found (needed for WhoamiGUI fixture)" >&2
  exit 1
}

load_runtime_env || true
if [[ -z "${JAVA_HOME:-}" && -x /usr/libexec/java_home ]]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home)"
  export JAVA_HOME
fi
if [[ -n "${JAVA_HOME:-}" ]]; then
  export PATH="${JAVA_HOME}/bin:${PATH}"
fi
if [[ -z "${GHIDRA_VIBE_ENGINE_HOME:-}" ]]; then
  GHIDRA_VIBE_ENGINE_HOME="$(ls -dt /nix/store/*-ghidra-vibe-engine-0.1.0 2>/dev/null | head -1 || true)"
  export GHIDRA_VIBE_ENGINE_HOME
fi
if [[ -n "${GHIDRA_VIBE_ENGINE_HOME:-}" ]]; then
  export GHIDRA_VIBE_ENGINE_LIB="${GHIDRA_VIBE_ENGINE_LIB:-$GHIDRA_VIBE_ENGINE_HOME/lib/libghidravibe_engine.dylib}"
  export GHIDRA_VIBE_ENGINE_CLASSPATH_FILE="${GHIDRA_VIBE_ENGINE_CLASSPATH_FILE:-$GHIDRA_VIBE_ENGINE_HOME/share/ghidra-vibe/engine/classpath.txt}"
fi

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR" "$PROJ_DIR"

echo "==> prepare whoami binary"
if ! lipo /usr/bin/whoami -thin arm64e -output "$BIN" 2>/dev/null \
  && ! lipo /usr/bin/whoami -thin arm64 -output "$BIN" 2>/dev/null; then
  cp /usr/bin/whoami "$BIN"
fi
chmod +x "$BIN"
file "$BIN" | tee "$WORKDIR/file.txt"

echo "==> fixture: headless import whoami → WhoamiGUI.gpr"
HEADLESS="$(resolve_headless)"
"$HEADLESS" "$PROJ_DIR" WhoamiGUI \
  -import "$BIN" \
  -overwrite \
  -analysisTimeoutPerFile 300 \
  >"$WORKDIR/fixture-import.log" 2>&1
if [[ ! -f "$PROJ_GPR" ]]; then
  echo "FAIL: fixture project missing at $PROJ_GPR" >&2
  tail -40 "$WORKDIR/fixture-import.log" >&2
  exit 1
fi
echo "PASS: fixture $PROJ_GPR"

export GHIDRA_VIBE_PROJECT="$PROJ_GPR"
export GHIDRA_VIBE_PROGRAM="/whoami"
defaults write dev.ghidravibe.app ghidra.vibe.userAgreementAccepted -bool true
defaults write dev.ghidravibe.app ghidra.vibe.welcomeHelpSeen -bool true
defaults write dev.ghidravibe.app ghidra.vibe.smokeStartProject -bool true
defaults write dev.ghidravibe.app ghidra.vibe.lastProject "$PROJ_GPR"
defaults write dev.ghidravibe.app ghidra.vibe.lastProgram "whoami"

mcp_up() {
  curl -fsS --max-time 2 "${MCP_URL}/check_connection" >/dev/null 2>&1 \
    || curl -fsS --max-time 2 "${MCP_URL}/check" >/dev/null 2>&1
}
gui_up() {
  curl -fsS --max-time 2 "${GUI_URL}/health" >/dev/null 2>&1
}

start_gui_app() {
  echo "==> launch GhidraVibe (GuiControl + in-process analysis)"
  if [[ ! -d "$INSTALL" ]]; then
    if [[ ! -d "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app" ]]; then
      "$ROOT/macos/GhidraVibe/scripts/package-app.sh" "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app"
    fi
    mkdir -p "$(dirname "$INSTALL")"
    rm -rf "$INSTALL"
    cp -R "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app" "$INSTALL"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL" || true
  fi

  pkill -x GhidraVibe 2>/dev/null || true
  sleep 1
  export GHIDRA_INSTALL_DIR GHIDRA_VIBE_PROJECT GHIDRA_VIBE_PROGRAM
  export GHIDRA_VIBE_ENGINE=inprocess
  export GHIDRA_MCP_URL="$MCP_URL"
  export GHIDRA_VIBE_MCP_HEADLESS="${GHIDRA_VIBE_MCP_HEADLESS:-$ROOT/scripts/ghidra-vibe-mcp-headless}"
  # Launch from workdir so cwd cannot imply repo VibeDSC.
  (
    cd "$WORKDIR"
    "$INSTALL/Contents/MacOS/GhidraVibe" >"$WORKDIR/ghidravibe-app.log" 2>&1 &
    echo $! >"$WORKDIR/ghidravibe-app.pid"
  )

  local i
  for i in $(seq 1 120); do
    if gui_up && mcp_up; then
      echo "GuiControl + analysis MCP up after ${i}s"
      return 0
    fi
    sleep 1
  done
  echo "FAIL: GUI/MCP did not start (see $WORKDIR/ghidravibe-app.log)" >&2
  tail -60 "$WORKDIR/ghidravibe-app.log" >&2 || true
  return 1
}

if [[ "${WHOAMI_REPACKAGE:-1}" == "1" ]]; then
  echo "==> package GhidraVibe.app"
  "$ROOT/macos/GhidraVibe/scripts/package-app.sh" "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app"
  mkdir -p "$(dirname "$INSTALL")"
  rm -rf "$INSTALL"
  cp -R "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app" "$INSTALL"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL" || true
fi

# Always relaunch so pinned WhoamiGUI project/program take effect.
start_gui_app

echo "==> ensure whoami is the open program"
curl -fsS --max-time 60 -X POST "${MCP_URL}/open_program" \
  -H 'Content-Type: application/json' \
  -d '{"program":"/whoami"}' | tee "$WORKDIR/open.json" | head -c 400 || true
echo

echo "==> GuiControl: CodeBrowser + functions + decompile entry"
curl -fsS --max-time 30 -X POST "${GUI_URL}/navigate" \
  -H 'Content-Type: application/json' \
  -d '{"pane":"codebrowser"}' >"$WORKDIR/nav.json"
curl -fsS --max-time 30 -X POST "${GUI_URL}/action" \
  -H 'Content-Type: application/json' \
  -d '{"id":"fetch_functions"}' >"$WORKDIR/fetch.json"
sleep 2
curl -fsS --max-time 30 -X POST "${GUI_URL}/action" \
  -H 'Content-Type: application/json' \
  -d '{"id":"show_decompiler"}' >"$WORKDIR/show-decomp.json"

SELECT_OK=0
for payload in \
  '{"name":"entry"}' \
  '{"address":"100000588"}' \
  '{"address":"0x100000588"}'
do
  curl -fsS --max-time 30 -X POST "${GUI_URL}/select_function" \
    -H 'Content-Type: application/json' \
    -d "$payload" >"$WORKDIR/select.json" || true
  curl -fsS --max-time 30 -X POST "${GUI_URL}/action" \
    -H 'Content-Type: application/json' \
    -d '{"id":"decompile"}' >"$WORKDIR/decomp-action.json" || true
  for _ in $(seq 1 40); do
    curl -fsS --max-time 10 "${GUI_URL}/state" >"$WORKDIR/state.json"
    if STATE_JSON="$WORKDIR/state.json" python3 - <<'PY'
import json, os, sys
st = json.load(open(os.environ["STATE_JSON"]))
prev = st.get("decompilePreview") or ""
prog = (st.get("currentProgram") or "").lower()
ok = ("whoami" in prog or "whoami" in prev.lower() or "entry" in (st.get("selectedFunction") or "").lower()) and (
    "_strcmp" in prev
    or "strcmp" in prev
    or "void entry" in prev
    or "geteuid" in prev
    or "getuid" in prev
    or "whoami" in prev
)
sys.exit(0 if ok else 1)
PY
    then
      SELECT_OK=1
      break
    fi
    sleep 0.5
  done
  [[ "$SELECT_OK" == "1" ]] && break
done

cp -f "$WORKDIR/state.json" "$ARTIFACTS/whoami-gui-state.json" 2>/dev/null || true
cp -f "$WORKDIR/ghidravibe-app.log" "$ARTIFACTS/whoami-gui-app.log" 2>/dev/null || true

if [[ "$SELECT_OK" != "1" ]]; then
  echo "FAIL: GuiControl decompilePreview missing whoami/entry C" >&2
  STATE_JSON="$WORKDIR/state.json" python3 - <<'PY' || true
import json, os
st = json.load(open(os.environ["STATE_JSON"]))
print("program:", st.get("currentProgram"))
print("selected:", st.get("selectedFunction"), st.get("selectedAddress"))
print("functions:", st.get("functionCount"))
print("preview:", (st.get("decompilePreview") or "")[:800])
print("status:", st.get("statusMessage"))
PY
  tail -40 "$WORKDIR/ghidravibe-app.log" >&2 || true
  exit 1
fi

STATE_JSON="$WORKDIR/state.json" python3 - <<'PY'
import json, os
st = json.load(open(os.environ["STATE_JSON"]))
prev = st.get("decompilePreview") or ""
checks = [
    ("currentProgram mentions whoami", "whoami" in (st.get("currentProgram") or "").lower()),
    ("function list non-empty", int(st.get("functionCount") or 0) > 0),
    (
        "decompile has C markers",
        any(x in prev for x in ("void entry", "_strcmp", "strcmp", "geteuid", "getuid", "whoami")),
    ),
]
for n, ok in checks:
    print(("PASS" if ok else "FAIL"), n)
if any(not ok for _, ok in checks):
    raise SystemExit(1)
print("preview_chars", len(prev))
print(prev[:600])
PY

echo "PASS: GuiControl decompiled whoami entry"
echo "OK smoke-whoami-decompile (GUI)"
exit 0
