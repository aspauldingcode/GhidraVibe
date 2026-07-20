#!/usr/bin/env bash
# GUI smoke: open DSC AppKit in the live GhidraVibe app, decompile a named
# function via GuiControl, and assert real C in /state decompilePreview.
#
# Fixture prep uses ghidra-vibe-dyld (DyldCacheFileSystem, no full auto-analyze by
# default). The decompile assertion is GUI-only (GuiControl + in-process engine).
set -euo pipefail
# Keep a sane PATH (some agent shells drop /usr/bin).
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="${GHIDRA_VIBE_APPKIT_WORKDIR:-/tmp/ghidra-vibe-appkit-gui}"
MCP_URL="${GHIDRA_MCP_URL:-http://127.0.0.1:8089}"
GUI_URL="${GHIDRA_VIBE_GUI_URL:-http://127.0.0.1:8091}"
INSTALL="${GHIDRA_VIBE_APP_INSTALL:-$HOME/Applications/GhidraVibe.app}"
IMAGE="${APPKIT_SMOKE_IMAGE:-AppKit}"
PROJ_DIR="$WORKDIR/project"
PROJ_NAME="AppKitGUI"
PROJ_GPR="$PROJ_DIR/${PROJ_NAME}.gpr"
DYLD="${GHIDRA_VIBE_DYLD:-$ROOT/scripts/ghidra-vibe-dyld}"
ARTIFACTS="${AD_ARTIFACTS:-$ROOT/gui-tests/artifacts}"
mkdir -p "$ARTIFACTS" "$WORKDIR"

resolve_ghidra_install_dir() {
  if [[ -n "${GHIDRA_INSTALL_DIR:-}" && -x "${GHIDRA_INSTALL_DIR}/support/launch.sh" ]]; then
    echo "$GHIDRA_INSTALL_DIR"
    return 0
  fi
  if [[ -x "$ROOT/result/lib/ghidra/support/launch.sh" ]]; then
    echo "$ROOT/result/lib/ghidra"
    return 0
  fi
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

# Headless wrapper for dyld import (MAXMEM-aware).
if [[ -z "${GHIDRA_VIBE_HEADLESS:-}" ]]; then
  if [[ -x "$ROOT/scripts/ghidra-vibe-analyzeHeadless" ]]; then
    export GHIDRA_VIBE_HEADLESS="$ROOT/scripts/ghidra-vibe-analyzeHeadless"
  elif [[ -x "${GHIDRA_INSTALL_DIR}/../../share/ghidra-vibe/ghidra-vibe-analyzeHeadless" ]]; then
    export GHIDRA_VIBE_HEADLESS="$(cd "${GHIDRA_INSTALL_DIR}/../../share/ghidra-vibe" && pwd)/ghidra-vibe-analyzeHeadless"
  fi
fi
export GHIDRA_VIBE_SCRIPT_PATH="${GHIDRA_VIBE_SCRIPT_PATH:-$ROOT/ghidra_scripts}"
export GHIDRA_VIBE_DYLD="$DYLD"

ensure_appkit_fixture() {
  if [[ -f "$PROJ_GPR" && "${APPKIT_FORCE_IMPORT:-0}" != "1" ]]; then
    echo "PASS: reuse fixture $PROJ_GPR (set APPKIT_FORCE_IMPORT=1 to rebuild)"
    return 0
  fi
  if [[ ! -x "$DYLD" ]]; then
    echo "FAIL: ghidra-vibe-dyld missing at $DYLD" >&2
    exit 1
  fi
  echo "==> fixture: DSC import $IMAGE → ${PROJ_NAME}.gpr (no full auto-analyze)"
  mkdir -p "$PROJ_DIR"
  # Apple symbols on; analyze off (IDA-like snappy module load). First import can take minutes.
  "$DYLD" import \
    --image "$IMAGE" \
    --project "$PROJ_DIR" \
    --project-name "$PROJ_NAME" \
    --no-analyze \
    2>&1 | tee "$WORKDIR/fixture-import.log"
  if [[ ! -f "$PROJ_GPR" ]]; then
    echo "FAIL: fixture project missing at $PROJ_GPR" >&2
    tail -60 "$WORKDIR/fixture-import.log" >&2 || true
    exit 1
  fi
  if ! grep -E -q 'OK: imported|OK:' "$WORKDIR/fixture-import.log" 2>/dev/null; then
    echo "FAIL: dyld import did not report OK" >&2
    tail -60 "$WORKDIR/fixture-import.log" >&2 || true
    exit 1
  fi
  echo "PASS: fixture $PROJ_GPR"
}

ensure_appkit_fixture

# Program leaf name from dyld import (usually "AppKit").
PROGRAM_LEAF="${APPKIT_SMOKE_PROGRAM:-$IMAGE}"
export GHIDRA_VIBE_PROJECT="$PROJ_GPR"
export GHIDRA_VIBE_PROGRAM="/${PROGRAM_LEAF}"
defaults write dev.ghidravibe.app ghidra.vibe.userAgreementAccepted -bool true
defaults write dev.ghidravibe.app ghidra.vibe.welcomeHelpSeen -bool true
defaults write dev.ghidravibe.app ghidra.vibe.smokeStartProject -bool true
defaults write dev.ghidravibe.app ghidra.vibe.lastProject "$PROJ_GPR"
defaults write dev.ghidravibe.app ghidra.vibe.lastProgram "$PROGRAM_LEAF"

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
  export GHIDRA_VIBE_DYLD
  (
    cd "$WORKDIR"
    "$INSTALL/Contents/MacOS/GhidraVibe" >"$WORKDIR/ghidravibe-app.log" 2>&1 &
    echo $! >"$WORKDIR/ghidravibe-app.pid"
  )

  local i
  for i in $(seq 1 180); do
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

if [[ "${APPKIT_REPACKAGE:-0}" == "1" ]]; then
  echo "==> package GhidraVibe.app"
  "$ROOT/macos/GhidraVibe/scripts/package-app.sh" "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app"
  mkdir -p "$(dirname "$INSTALL")"
  rm -rf "$INSTALL"
  cp -R "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app" "$INSTALL"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL" || true
fi

start_gui_app

echo "==> ensure $PROGRAM_LEAF is the open program"
# Try common open_program shapes used by this MCP build.
curl -fsS --max-time 90 -G "${MCP_URL}/open_program" \
  --data-urlencode "program=/${PROGRAM_LEAF}" >"$WORKDIR/open.json" 2>/dev/null \
  || curl -fsS --max-time 90 -G "${MCP_URL}/open_program" \
    --data-urlencode "path=/${PROGRAM_LEAF}" >"$WORKDIR/open.json" 2>/dev/null \
  || curl -fsS --max-time 90 -X POST "${MCP_URL}/open_program" \
    -H 'Content-Type: application/json' \
    -d "{\"program\":\"/${PROGRAM_LEAF}\"}" >"$WORKDIR/open.json" 2>/dev/null \
  || true
head -c 400 "$WORKDIR/open.json" 2>/dev/null || true
echo

echo "==> pick a decompile target from list_functions"
curl -fsS --max-time 120 "${MCP_URL}/list_functions?limit=200" >"$WORKDIR/funcs.json" || \
  curl -fsS --max-time 120 "${MCP_URL}/methods?limit=200" >"$WORKDIR/funcs.json" || \
  echo '[]' >"$WORKDIR/funcs.json"

TARGET_JSON="$(FUNCS_JSON="$WORKDIR/funcs.json" IMAGE="$IMAGE" python3 - <<'PY'
import json, os, re
raw = open(os.environ["FUNCS_JSON"]).read()
pairs = []  # (name, addr)

def add(name, addr=""):
    name = (name or "").strip()
    if not name:
        return
    pairs.append((name, str(addr or "").strip()))

# Plain-text MCP shape: "name at aabbccdd"
for line in raw.splitlines():
    line = line.strip()
    if not line:
        continue
    m = re.match(r"^(.+?)\s+at\s+([0-9a-fA-Fx]+)\s*$", line)
    if m:
        add(m.group(1), m.group(2))
    elif not line.startswith("{") and not line.startswith("["):
        add(line)

# JSON shapes
try:
    data = json.loads(raw)
except Exception:
    data = None
if isinstance(data, list):
    for x in data:
        if isinstance(x, dict):
            add(x.get("name") or x.get("function") or x.get("signature"), x.get("address") or x.get("entry") or "")
        else:
            add(str(x))
elif isinstance(data, dict):
    for k in ("functions", "methods", "items", "result", "data"):
        v = data.get(k)
        if isinstance(v, list):
            for x in v:
                if isinstance(x, dict):
                    add(x.get("name") or x.get("function"), x.get("address") or x.get("entry") or "")
                else:
                    add(str(x))
            break

# Prefer AppKit/ObjC names with addresses (no-analyze import often lacks ObjC methods).
prefer = [
    r"sharedApplication",
    r"NSApplicationMain",
    r"NSApplication",
    r"NSWindow",
    r"objc_msgSend$",
    r"objc_msgSend",
    r"objc_retain$",
    r"^\+\[",
    r"^-\[",
]
chosen = None
for pat in prefer:
    rx = re.compile(pat, re.I)
    for n, a in pairs:
        if rx.search(n) and a:
            chosen = (n, a)
            break
    if chosen:
        break
if not chosen:
    for n, a in pairs:
        if a and not n.startswith("FUN_"):
            chosen = (n, a)
            break
if not chosen:
    for n, a in pairs:
        if a:
            chosen = (n, a)
            break
if not chosen:
    chosen = ("_objc_msgSend", "180095800")
print(json.dumps({"name": chosen[0], "address": chosen[1], "count": len(pairs)}))
PY
)"
echo "target=$TARGET_JSON"
printf '%s\n' "$TARGET_JSON" >"$WORKDIR/target.json"
TARGET_NAME="$(TARGET_JSON_PATH="$WORKDIR/target.json" python3 -c 'import json,os; print(json.load(open(os.environ["TARGET_JSON_PATH"]))["name"])')"
TARGET_ADDR="$(TARGET_JSON_PATH="$WORKDIR/target.json" python3 -c 'import json,os; print(json.load(open(os.environ["TARGET_JSON_PATH"])).get("address") or "")')"

echo "==> GuiControl: CodeBrowser + decompile ($TARGET_NAME @ $TARGET_ADDR)"
curl -fsS --max-time 30 -X POST "${GUI_URL}/navigate" \
  -H 'Content-Type: application/json' \
  -d '{"pane":"codebrowser"}' >"$WORKDIR/nav.json"
curl -fsS --max-time 90 -X POST "${GUI_URL}/action" \
  -H 'Content-Type: application/json' \
  -d '{"id":"fetch_functions"}' >"$WORKDIR/fetch.json"
# Wait until the GUI function list is populated (async MCP fetch).
for _ in $(seq 1 60); do
  curl -fsS --max-time 10 "${GUI_URL}/state" >"$WORKDIR/state.json"
  if STATE_JSON="$WORKDIR/state.json" python3 -c 'import json,os,sys; st=json.load(open(os.environ["STATE_JSON"])); sys.exit(0 if int(st.get("functionCount") or 0)>0 else 1)'; then
    echo "functionCount ready"
    break
  fi
  sleep 0.5
done
curl -fsS --max-time 30 -X POST "${GUI_URL}/action" \
  -H 'Content-Type: application/json' \
  -d '{"id":"show_decompiler"}' >"$WORKDIR/show-decomp.json"

SELECT_OK=0
PAYLOADS=()
if [[ -n "$TARGET_ADDR" ]]; then
  ADDR_RAW="${TARGET_ADDR#0x}"
  ADDR_RAW="${ADDR_RAW#0X}"
  for a in "$TARGET_ADDR" "0x${ADDR_RAW}" "$ADDR_RAW"; do
    PAYLOADS+=("$(A="$a" python3 -c 'import json,os; print(json.dumps({"address":os.environ["A"]}))')")
  done
fi
if [[ -n "$TARGET_NAME" ]]; then
  PAYLOADS+=("$(TARGET_NAME="$TARGET_NAME" python3 -c 'import json,os; print(json.dumps({"name":os.environ["TARGET_NAME"]}))')")
fi
# If selection fails, decompile whatever fetch_functions auto-selected.
PAYLOADS+=('{}')

for payload in "${PAYLOADS[@]}"; do
  echo "    try payload $payload"
  if [[ "$payload" != '{}' ]]; then
    curl -fsS --max-time 30 -X POST "${GUI_URL}/select_function" \
      -H 'Content-Type: application/json' \
      -d "$payload" >"$WORKDIR/select.json" || true
  fi
  curl -fsS --max-time 30 -X POST "${GUI_URL}/action" \
    -H 'Content-Type: application/json' \
    -d '{"id":"decompile"}' >"$WORKDIR/decomp-action.json" || true
  for _ in $(seq 1 80); do
    curl -fsS --max-time 15 "${GUI_URL}/state" >"$WORKDIR/state.json"
    if STATE_JSON="$WORKDIR/state.json" IMAGE="$IMAGE" python3 - <<'PY'
import json, os, sys
st = json.load(open(os.environ["STATE_JSON"]))
prev = st.get("decompilePreview") or ""
prog = (st.get("currentProgram") or "").lower()
img = (os.environ.get("IMAGE") or "AppKit").lower()
ok_prog = img in prog or "appkit" in prog
ok_c = any(
    x in prev
    for x in (
        "NSApplication",
        "sharedApplication",
        "objc_",
        "_objc_",
        "id ",
        "void ",
        "undefined",
        "return ",
        "FUN_",
        "@selector",
        "Class ",
        "ulong ",
        "undefined8",
    )
)
bad = (
    not prev.strip()
    or "Select a function" in prev
    or prev.strip() == "// No Function"
    or '"error"' in prev.lower()
    or "<html" in prev.lower()
    or "404 not found" in prev.lower()
)
sys.exit(0 if ok_prog and ok_c and not bad else 1)
PY
    then
      SELECT_OK=1
      break
    fi
    sleep 0.5
  done
  [[ "$SELECT_OK" == "1" ]] && break
done

cp -f "$WORKDIR/state.json" "$ARTIFACTS/appkit-gui-state.json" 2>/dev/null || true
cp -f "$WORKDIR/ghidravibe-app.log" "$ARTIFACTS/appkit-gui-app.log" 2>/dev/null || true
cp -f "$WORKDIR/funcs.json" "$ARTIFACTS/appkit-gui-funcs.json" 2>/dev/null || true

if [[ "$SELECT_OK" != "1" ]]; then
  echo "FAIL: GuiControl decompilePreview missing AppKit C" >&2
  STATE_JSON="$WORKDIR/state.json" python3 - <<'PY' || true
import json, os
st = json.load(open(os.environ["STATE_JSON"]))
print("program:", st.get("currentProgram"))
print("selected:", st.get("selectedFunction"), st.get("selectedAddress"))
print("functions:", st.get("functionCount"))
print("preview:", (st.get("decompilePreview") or "")[:1000])
print("status:", st.get("statusMessage"))
PY
  tail -60 "$WORKDIR/ghidravibe-app.log" >&2 || true
  exit 1
fi

STATE_JSON="$WORKDIR/state.json" IMAGE="$IMAGE" python3 - <<'PY'
import json, os
st = json.load(open(os.environ["STATE_JSON"]))
prev = st.get("decompilePreview") or ""
img = (os.environ.get("IMAGE") or "AppKit").lower()
checks = [
    ("currentProgram mentions AppKit", img in (st.get("currentProgram") or "").lower()),
    ("function list non-empty", int(st.get("functionCount") or 0) > 0),
    (
        "decompile has C/ObjC markers",
        any(
            x in prev
            for x in (
                "NSApplication",
                "sharedApplication",
                "objc_",
                "void ",
                "undefined",
                "return ",
                "@selector",
            )
        ),
    ),
]
for n, ok in checks:
    print(("PASS" if ok else "FAIL"), n)
if any(not ok for _, ok in checks):
    raise SystemExit(1)
print("selected:", st.get("selectedFunction"), st.get("selectedAddress"))
print("preview_chars", len(prev))
print(prev[:800])
PY

echo "PASS: GuiControl decompiled AppKit function"
echo "OK smoke-appkit-decompile (GUI)"
exit 0
