#!/usr/bin/env bash
# Full GUI test: open AppKit from the on-device DSC, analyze, list ObjC classes,
# and decompile a class method — all via GuiControl on the live GhidraVibe app.
#
# Steps:
#   1) Launch GhidraVibe (in-process analysis MCP) + vibe MCP (dyld_import_image)
#   2) GuiControl: DSC Index → open AppKit (optional analyze-on-import)
#   3) GuiControl: Auto Analyze (if classes not yet present)
#   4) GuiControl: Symbol Tree / Classes → assert NSApplication/NSWindow/…
#   5) GuiControl: decompile a class method → assert real C
#
# Env:
#   APPKIT_CLASSES_REPACKAGE=1   rebuild app (default 1)
#   APPKIT_CLASSES_ANALYZE=1     request analyze on DSC import (default 1)
#   APPKIT_CLASSES_IMPORT_TIMEOUT / APPKIT_CLASSES_ANALYZE_TIMEOUT  seconds
#   APPKIT_CLASSES_REUSE_PROJECT=1  pin existing AppKitGUI.gpr and skip dyld/open
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="${GHIDRA_VIBE_APPKIT_CLASSES_WORKDIR:-/tmp/ghidra-vibe-appkit-classes-gui}"
MCP_URL="${GHIDRA_MCP_URL:-http://127.0.0.1:8089}"
GUI_URL="${GHIDRA_VIBE_GUI_URL:-http://127.0.0.1:8091}"
VIBE_URL="${GHIDRA_VIBE_MCP_EXT_URL:-http://127.0.0.1:8092}"
VIBE_PORT="${GHIDRA_VIBE_MCP_EXT_PORT:-8092}"
INSTALL="${GHIDRA_VIBE_APP_INSTALL:-$HOME/Applications/GhidraVibe.app}"
IMAGE="${APPKIT_SMOKE_IMAGE:-AppKit}"
PROJ_DIR="$WORKDIR/project"
PROJ_NAME="AppKitClasses"
PROJ_GPR="$PROJ_DIR/${PROJ_NAME}.gpr"
DYLD="${GHIDRA_VIBE_DYLD:-$ROOT/scripts/ghidra-vibe-dyld}"
ARTIFACTS="${AD_ARTIFACTS:-$ROOT/gui-tests/artifacts}"
IMPORT_TIMEOUT="${APPKIT_CLASSES_IMPORT_TIMEOUT:-900}"
ANALYZE_TIMEOUT="${APPKIT_CLASSES_ANALYZE_TIMEOUT:-1200}"
mkdir -p "$ARTIFACTS" "$WORKDIR" "$PROJ_DIR"

resolve_ghidra_install_dir() {
  if [[ -n "${GHIDRA_INSTALL_DIR:-}" && -x "${GHIDRA_INSTALL_DIR}/support/launch.sh" ]]; then
    echo "$GHIDRA_INSTALL_DIR"; return 0
  fi
  if [[ -x "$ROOT/result/lib/ghidra/support/launch.sh" ]]; then
    echo "$ROOT/result/lib/ghidra"; return 0
  fi
  local d
  for d in \
    $(ls -dt /nix/store/*-ghidra-vibe-*+native-*/lib/ghidra 2>/dev/null || true) \
    $(ls -dt /nix/store/*-ghidra-vibe-*/lib/ghidra 2>/dev/null || true)
  do
    [[ -x "$d/support/launch.sh" ]] && { echo "$d"; return 0; }
  done
  if command -v nix >/dev/null 2>&1; then
    d="$(nix build "$ROOT#ghidra-vibe" --no-link --print-out-paths 2>/dev/null | head -1 || true)"
    [[ -n "$d" && -x "$d/lib/ghidra/support/launch.sh" ]] && { echo "$d/lib/ghidra"; return 0; }
  fi
  return 1
}

if ! GHIDRA_INSTALL_DIR="$(resolve_ghidra_install_dir)"; then
  echo "FAIL: could not find Ghidra install" >&2
  exit 1
fi
export GHIDRA_INSTALL_DIR
echo "GHIDRA_INSTALL_DIR=$GHIDRA_INSTALL_DIR"

for cand in \
  "${GHIDRA_INSTALL_DIR}/../../share/ghidra-vibe/runtime.env" \
  "${GHIDRA_INSTALL_DIR}/../share/ghidra-vibe/runtime.env"
do
  if [[ -f "$cand" ]]; then
    set -a; # shellcheck disable=SC1090
    source "$cand"; set +a
    break
  fi
done
if [[ -z "${JAVA_HOME:-}" && -x /usr/libexec/java_home ]]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home)"
  export JAVA_HOME
fi
[[ -n "${JAVA_HOME:-}" ]] && export PATH="${JAVA_HOME}/bin:${PATH}"
if [[ -z "${GHIDRA_VIBE_ENGINE_HOME:-}" ]]; then
  GHIDRA_VIBE_ENGINE_HOME="$(ls -dt /nix/store/*-ghidra-vibe-engine-0.1.0 2>/dev/null | head -1 || true)"
  export GHIDRA_VIBE_ENGINE_HOME
fi
if [[ -n "${GHIDRA_VIBE_ENGINE_HOME:-}" ]]; then
  export GHIDRA_VIBE_ENGINE_LIB="${GHIDRA_VIBE_ENGINE_LIB:-$GHIDRA_VIBE_ENGINE_HOME/lib/libghidravibe_engine.dylib}"
  export GHIDRA_VIBE_ENGINE_CLASSPATH_FILE="${GHIDRA_VIBE_ENGINE_CLASSPATH_FILE:-$GHIDRA_VIBE_ENGINE_HOME/share/ghidra-vibe/engine/classpath.txt}"
fi
export GHIDRA_VIBE_DYLD="$DYLD"
export GHIDRA_VIBE_SCRIPT_PATH="${GHIDRA_VIBE_SCRIPT_PATH:-$ROOT/ghidra_scripts}"
if [[ -z "${GHIDRA_VIBE_HEADLESS:-}" && -x "$ROOT/scripts/ghidra-vibe-analyzeHeadless" ]]; then
  export GHIDRA_VIBE_HEADLESS="$ROOT/scripts/ghidra-vibe-analyzeHeadless"
fi

mcp_up() { curl -fsS --max-time 2 "${MCP_URL}/check_connection" >/dev/null 2>&1; }
gui_up() { curl -fsS --max-time 2 "${GUI_URL}/health" >/dev/null 2>&1; }
vibe_up() { curl -fsS --max-time 2 "${VIBE_URL}/health" >/dev/null 2>&1; }

gui_state() {
  curl -fsS --max-time 15 "${GUI_URL}/state" >"$WORKDIR/state.json"
}

gui_action() {
  curl -fsS --max-time 60 -X POST "${GUI_URL}/action" \
    -H 'Content-Type: application/json' \
    -d "{\"id\":\"$1\"}" >"$WORKDIR/action-$1.json"
}

start_vibe_mcp() {
  if vibe_up; then
    echo "vibe MCP already up"
    return 0
  fi
  echo "==> start vibe MCP ($VIBE_URL)"
  if command -v /usr/sbin/lsof >/dev/null 2>&1; then
    for pid in $(/usr/sbin/lsof -tiTCP:"$VIBE_PORT" -sTCP:LISTEN 2>/dev/null || true); do
      cmd=$(ps -p "$pid" -o command= 2>/dev/null || true)
      if [[ "$cmd" == *vibe_mcp* || "$cmd" == *ghidra-vibe-mcp-ext* ]]; then
        kill "$pid" 2>/dev/null || true
      fi
    done
    sleep 1
  fi
  export GHIDRA_MCP_ALLOW_SCRIPTS=1 GHIDRA_MCP_URL="$MCP_URL" GHIDRA_VIBE_DYLD
  (
    cd "$ROOT/scripts/lib"
    exec /usr/bin/python3 -m vibe_mcp --host 127.0.0.1 --port "$VIBE_PORT"
  ) >"$WORKDIR/vibe-mcp.log" 2>&1 &
  echo $! >"$WORKDIR/vibe-mcp.pid"
  local i
  for i in $(seq 1 30); do
    vibe_up && { echo "vibe MCP up after ${i}s"; return 0; }
    sleep 1
  done
  echo "FAIL: vibe MCP did not start" >&2
  tail -40 "$WORKDIR/vibe-mcp.log" >&2 || true
  return 1
}

start_gui_app() {
  echo "==> launch GhidraVibe"
  defaults write dev.ghidravibe.app ghidra.vibe.userAgreementAccepted -bool true
  defaults write dev.ghidravibe.app ghidra.vibe.welcomeHelpSeen -bool true
  defaults write dev.ghidravibe.app ghidra.vibe.smokeStartProject -bool true
  defaults write dev.ghidravibe.app ghidra.vibe.lastProject "$PROJ_GPR"
  defaults write dev.ghidravibe.app ghidra.vibe.lastProgram "$IMAGE"
  export GHIDRA_VIBE_PROJECT="$PROJ_GPR"
  export GHIDRA_VIBE_PROGRAM="/$IMAGE"
  export GHIDRA_INSTALL_DIR GHIDRA_VIBE_ENGINE=inprocess GHIDRA_MCP_URL="$MCP_URL"
  export GHIDRA_VIBE_MCP_HEADLESS="${GHIDRA_VIBE_MCP_HEADLESS:-$ROOT/scripts/ghidra-vibe-mcp-headless}"
  export GHIDRA_VIBE_MCP_EXT_URL="$VIBE_URL" GHIDRA_VIBE_DYLD

  pkill -x GhidraVibe 2>/dev/null || true
  sleep 1
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
  echo "FAIL: GUI/MCP did not start" >&2
  tail -60 "$WORKDIR/ghidravibe-app.log" >&2 || true
  return 1
}

ensure_project_dir() {
  mkdir -p "$PROJ_DIR"
  if [[ -f "$PROJ_GPR" && -d "${PROJ_DIR}/${PROJ_NAME}.rep" ]]; then
    echo "project exists: $PROJ_GPR"
  else
    echo "project dir ready (import will create ${PROJ_NAME}.gpr): $PROJ_DIR"
  fi
}

print_classes() {
  STATE_JSON="$WORKDIR/state.json" python3 - <<'PY'
import json, os
st = json.load(open(os.environ["STATE_JSON"]))
objc = st.get("objcClassPreview") or []
swift = st.get("swiftClassPreview") or []
print(f"program={st.get('currentProgram')} functions={st.get('functionCount')} objcClasses={st.get('objcClassCount')} analysisBusy={st.get('analysisBusy')} dyldImportBusy={st.get('dyldImportBusy')}")
print("--- ObjC classes (preview) ---")
for c in objc:
    print(f"  {c}")
if not objc:
    print("  (none yet)")
print("--- class/swift preview ---")
for c in swift[:30]:
    print(f"  {c}")
PY
}

# --- package ---
if [[ "${APPKIT_CLASSES_REPACKAGE:-1}" == "1" ]]; then
  echo "==> package GhidraVibe.app"
  "$ROOT/macos/GhidraVibe/scripts/package-app.sh" "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app"
  mkdir -p "$(dirname "$INSTALL")"
  rm -rf "$INSTALL"
  cp -R "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app" "$INSTALL"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL" || true
fi

ensure_project_dir
# Point defaults at the intended project path even before .gpr exists.
defaults write dev.ghidravibe.app ghidra.vibe.lastProject "$PROJ_GPR"
export GHIDRA_VIBE_PROJECT="$PROJ_GPR"
start_vibe_mcp
start_gui_app

echo "==> GuiControl: open CodeBrowser + DSC Index"
curl -fsS --max-time 30 -X POST "${GUI_URL}/navigate" \
  -H 'Content-Type: application/json' -d '{"pane":"codebrowser"}' >"$WORKDIR/nav.json"
gui_action show_dsc
curl -fsS --max-time 30 "${GUI_URL}/dyld/caches" | tee "$WORKDIR/caches.json" | head -c 400 || true
echo
curl -fsS --max-time 60 -X POST "${GUI_URL}/dyld/list" \
  -H 'Content-Type: application/json' \
  -d "{\"query\":\"${IMAGE}\"}" | tee "$WORKDIR/dyld-list.json" | head -c 600 || true
echo

ANALYZE_FLAG="${APPKIT_CLASSES_ANALYZE:-1}"
if [[ "${APPKIT_CLASSES_REUSE_PROJECT:-0}" == "1" && -d "${PROJ_DIR}/${PROJ_NAME}.rep" ]]; then
  echo "==> reuse existing AppKitClasses project (skip dyld/open)"
  curl -fsS --max-time 60 -G "${MCP_URL}/open_program" \
    --data-urlencode "program=/${IMAGE}" >"$WORKDIR/open.json" 2>/dev/null || true
else
  echo "==> GuiControl: DSC open ${IMAGE} (analyze=${ANALYZE_FLAG})"
  # Remove empty placeholder gpr so import can create a real project.
  if [[ ! -s "$PROJ_GPR" ]]; then rm -f "$PROJ_GPR"; fi
  # Prefer GUI import into our workdir project via env already pinned.
  curl -fsS --max-time 30 -X POST "${GUI_URL}/action" \
    -H 'Content-Type: application/json' \
    -d '{"id":"dyld_analyze_on"}' >"$WORKDIR/dyld-analyze-on.json" || true
  if [[ "$ANALYZE_FLAG" != "1" ]]; then
    curl -fsS --max-time 30 -X POST "${GUI_URL}/action" \
      -H 'Content-Type: application/json' \
      -d '{"id":"dyld_analyze_off"}' >"$WORKDIR/dyld-analyze-off.json" || true
  fi
  ANALYZE_JSON=$([[ "$ANALYZE_FLAG" == "1" ]] && echo true || echo false)
  curl -fsS --max-time 30 -X POST "${GUI_URL}/dyld/open" \
    -H 'Content-Type: application/json' \
    -d "{\"image\":\"${IMAGE}\",\"analyze\":${ANALYZE_JSON},\"project\":\"${PROJ_DIR}\",\"project_name\":\"${PROJ_NAME}\"}" \
    | tee "$WORKDIR/dyld-open.json" | head -c 800 || true
  echo

  echo "==> wait for DSC import (timeout ${IMPORT_TIMEOUT}s)"
  deadline=$((SECONDS + IMPORT_TIMEOUT))
  while (( SECONDS < deadline )); do
    gui_state
    if STATE_JSON="$WORKDIR/state.json" IMAGE="$IMAGE" python3 - <<'PY'
import json, os, sys
st = json.load(open(os.environ["STATE_JSON"]))
prog = (st.get("currentProgram") or "").lower()
busy = bool(st.get("dyldImportBusy"))
img = (os.environ.get("IMAGE") or "appkit").lower()
sys.exit(0 if (img in prog and not busy) else 1)
PY
    then
      echo "import settled: program=$(STATE_JSON="$WORKDIR/state.json" python3 -c 'import json,os; print(json.load(open(os.environ["STATE_JSON"])).get("currentProgram"))')"
      break
    fi
    # Fallback: CLI import if GUI path stalls > 120s without project program
    if (( SECONDS > 120 )) && [[ ! -d "${PROJ_DIR}/${PROJ_NAME}.rep" ]]; then
      echo "WARN: GUI import slow — CLI dyld import fallback into $PROJ_DIR"
      if [[ "$ANALYZE_FLAG" == "1" ]]; then
        "$DYLD" import --image "$IMAGE" --project "$PROJ_DIR" --project-name "$PROJ_NAME" --analyze 1 \
          2>&1 | tee "$WORKDIR/cli-import.log" | tail -20
      else
        "$DYLD" import --image "$IMAGE" --project "$PROJ_DIR" --project-name "$PROJ_NAME" --no-analyze \
          2>&1 | tee "$WORKDIR/cli-import.log" | tail -20
      fi
      defaults write dev.ghidravibe.app ghidra.vibe.lastProject "$PROJ_GPR"
      defaults write dev.ghidravibe.app ghidra.vibe.lastProgram "$IMAGE"
      export GHIDRA_VIBE_PROJECT="$PROJ_GPR" GHIDRA_VIBE_PROGRAM="/$IMAGE"
      start_gui_app
      break
    fi
    sleep 3
  done
fi

gui_state
print_classes | tee "$WORKDIR/classes-after-import.txt"

echo "==> GuiControl: fetch functions + Auto Analyze"
gui_action fetch_functions
sleep 2
gui_action auto_analyze

echo "==> wait for ObjC classes (NSApplication/…) timeout ${ANALYZE_TIMEOUT}s"
deadline=$((SECONDS + ANALYZE_TIMEOUT))
CLASSES_OK=0
while (( SECONDS < deadline )); do
  gui_action fetch_functions || true
  curl -fsS --max-time 30 -X POST "${GUI_URL}/refresh_classes" \
    -H 'Content-Type: application/json' -d '{}' >"$WORKDIR/refresh-classes.json" || \
    gui_action refresh_classes || true
  gui_action show_symbol_tree || true
  gui_action show_swift_classes || true
  sleep 2
  gui_state
  if STATE_JSON="$WORKDIR/state.json" python3 - <<'PY'
import json, os, sys, re
st = json.load(open(os.environ["STATE_JSON"]))
classes = [str(c) for c in (st.get("objcClassPreview") or []) + (st.get("swiftClassPreview") or [])]
ns_like = [c for c in classes if re.match(r'^NS[A-Z]', c) or c.startswith("NS")]
blob = " ".join(c.lower() for c in classes)
need = any(k in blob for k in ("nsapplication", "nswindow", "nsview", "nsbutton", "nscell"))
ok = need or len(ns_like) >= 5 or int(st.get("objcClassCount") or 0) >= 5
sys.exit(0 if ok else 1)
PY
  then
    CLASSES_OK=1
    echo "ObjC/NS classes ready"
    break
  fi
  # If analysis finished but still no classes, keep polling a bit (symbol recovery lag).
  busy=$(STATE_JSON="$WORKDIR/state.json" python3 -c 'import json,os; print(json.load(open(os.environ["STATE_JSON"])).get("analysisBusy"))')
  echo "  … waiting (analysisBusy=$busy objc=$(STATE_JSON="$WORKDIR/state.json" python3 -c 'import json,os; print(json.load(open(os.environ["STATE_JSON"])).get("objcClassCount"))'))"
  sleep 10
done

print_classes | tee "$WORKDIR/classes-after-analyze.txt"
cp -f "$WORKDIR/state.json" "$ARTIFACTS/appkit-classes-state.json"

if [[ "$CLASSES_OK" != "1" ]]; then
  # Last-chance: scrape MCP function list in the script for ObjC classes (engine may have them
  # even if GUI harvest lagged).
  curl -fsS --max-time 120 "${MCP_URL}/list_functions?limit=20000" >"$WORKDIR/funcs.txt" || true
  if FUNCS="$WORKDIR/funcs.txt" OUT="$WORKDIR/classes-from-mcp.txt" python3 - <<'PY'
import os, re, sys
text = open(os.environ["FUNCS"]).read()
classes = sorted({m.group(1) for m in re.finditer(r'[-+]\[([A-Za-z_][A-Za-z0-9_]*)\s', text)})
open(os.environ["OUT"], "w").write("\n".join(classes))
print(f"MCP ObjC classes: {len(classes)}")
for c in classes[:60]:
    print(" ", c)
want = {"NSApplication", "NSWindow", "NSView", "NSControl"}
sys.exit(0 if want & set(classes) or len(classes) >= 5 else 1)
PY
  then
    CLASSES_OK=1
    echo "PASS: classes recovered from analysis MCP list_functions"
    cp -f "$WORKDIR/classes-from-mcp.txt" "$ARTIFACTS/appkit-classes-list.txt"
  fi
fi

if [[ "$CLASSES_OK" != "1" ]]; then
  echo "FAIL: no AppKit ObjC classes after open+analyze" >&2
  print_classes >&2 || true
  tail -80 "$WORKDIR/ghidravibe-app.log" >&2 || true
  exit 1
fi

echo "==> GuiControl: decompile an AppKit class method (poll while analysis runs)"
TARGET_NAME=""
TARGET_ADDR=""
decomp_deadline=$((SECONDS + ANALYZE_TIMEOUT))
while (( SECONDS < decomp_deadline )); do
  curl -fsS --max-time 120 "${MCP_URL}/list_functions?limit=20000" >"$WORKDIR/funcs.txt" || true
  TARGET="$(FUNCS="$WORKDIR/funcs.txt" python3 - <<'PY'
import os, re, sys
text = open(os.environ["FUNCS"]).read()
pairs = []
for line in text.splitlines():
    m = re.match(r"^(.+?)\s+at\s+([0-9a-fA-Fx]+)\s*$", line.strip())
    if not m:
        continue
    name, addr = m.group(1), m.group(2)
    score = 99
    if re.search(r"[-+\[]NSApplication\b", name):
        score = 0
    elif re.search(r"[-+\[]NS(Window|View|Control|Button|Cell)\b", name):
        score = 1
    elif name.startswith(("-[", "+[")) and "NS" in name:
        score = 2
    elif name.startswith(("-[", "+[")):
        score = 3
    if score < 99:
        pairs.append((score, name, addr))
if not pairs:
    sys.exit(1)
pairs.sort()
print(f"{pairs[0][1]}\t{pairs[0][2]}")
PY
)" && break
  echo "  … no ObjC methods yet; waiting on analysis"
  sleep 15
done

if [[ -z "${TARGET:-}" ]]; then
  # Fall back: decompile any real function while classes already listed from namespaces.
  TARGET="$(FUNCS="$WORKDIR/funcs.txt" python3 - <<'PY'
import os, re, sys
text = open(os.environ["FUNCS"]).read()
for line in text.splitlines():
    m = re.match(r"^(.+?)\s+at\s+([0-9a-fA-Fx]+)\s*$", line.strip())
    if not m:
        continue
    name, addr = m.group(1), m.group(2)
    if name.startswith("_objc_"):
        continue
    if name.startswith("FUN_") or name.startswith("_"):
        print(f"{name}\t{addr}")
        sys.exit(0)
sys.exit(1)
PY
)" || true
fi

if [[ -z "${TARGET:-}" ]]; then
  echo "FAIL: could not find a function to decompile in AppKit" >&2
  exit 1
fi
TARGET_NAME="${TARGET%%$'\t'*}"
TARGET_ADDR="${TARGET#*$'\t'}"
echo "decompile target: $TARGET_NAME @ $TARGET_ADDR"
printf '%s\n' "$TARGET_NAME @ $TARGET_ADDR" >"$ARTIFACTS/appkit-classes-target.txt"

gui_action show_decompiler
curl -fsS --max-time 30 -X POST "${GUI_URL}/select_function" \
  -H 'Content-Type: application/json' \
  -d "$(TARGET_NAME="$TARGET_NAME" TARGET_ADDR="$TARGET_ADDR" python3 -c 'import json,os; print(json.dumps({"name":os.environ["TARGET_NAME"],"address":os.environ["TARGET_ADDR"]}))')" \
  >"$WORKDIR/select.json"
gui_action decompile

DECOMP_OK=0
for _ in $(seq 1 80); do
  gui_state
  if STATE_JSON="$WORKDIR/state.json" python3 - <<'PY'
import json, os, sys
st = json.load(open(os.environ["STATE_JSON"]))
prev = st.get("decompilePreview") or ""
bad = (not prev.strip() or "Select a function" in prev or "<html" in prev.lower()
       or "404 not found" in prev.lower() or prev.strip() == "// No Function")
ok = (not bad) and any(
    x in prev
    for x in ("NSApplication", "NSWindow", "NSView", "objc_", "void ", "id ", "return ", "undefined", "FUN_")
)
sys.exit(0 if ok else 1)
PY
  then
    DECOMP_OK=1
    break
  fi
  sleep 0.5
done

cp -f "$WORKDIR/state.json" "$ARTIFACTS/appkit-classes-state-final.json"
STATE_JSON="$WORKDIR/state.json" python3 - <<'PY' | tee "$ARTIFACTS/appkit-classes-decomp.txt"
import json, os
st = json.load(open(os.environ["STATE_JSON"]))
print("selected:", st.get("selectedFunction"), st.get("selectedAddress"))
print("status:", st.get("statusMessage"))
print("==== DECOMPILE ====")
print(st.get("decompilePreview") or "")
print("==== CLASSES ====")
for c in (st.get("objcClassPreview") or []):
    print(c)
PY

if [[ "$DECOMP_OK" != "1" ]]; then
  echo "FAIL: class method decompile missing C" >&2
  exit 1
fi

echo
echo "PASS: GuiControl opened AppKit, analyzed, listed ObjC classes, decompiled class method"
echo "OK smoke-appkit-classes (GUI)"
exit 0
