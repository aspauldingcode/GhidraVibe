#!/usr/bin/env bash
# GUI smoke: native Function Graph CFG (blocks + edges) via GuiControl.
# Requires a whoami (or DecompSmoke) .gpr and in-process engine with BasicBlockModel CFG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="${GHIDRA_VIBE_GRAPH_WORKDIR:-/tmp/ghidra-vibe-graph-smoke}"
WHOAMI_WORKDIR="${GHIDRA_VIBE_WHOAMI_WORKDIR:-/tmp/ghidra-vibe-whoami-gui}"
MCP_URL="${GHIDRA_MCP_URL:-http://127.0.0.1:8089}"
GUI_URL="${GHIDRA_VIBE_GUI_URL:-http://127.0.0.1:8091}"
INSTALL="${GHIDRA_VIBE_APP_INSTALL:-$HOME/Applications/GhidraVibe.app}"
ARTIFACTS="${AD_ARTIFACTS:-$ROOT/gui-tests/artifacts}"
mkdir -p "$WORKDIR" "$ARTIFACTS"

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
  return 1
}

if ! GHIDRA_INSTALL_DIR="$(resolve_ghidra_install_dir)"; then
  echo "FAIL: set GHIDRA_INSTALL_DIR or nix build .#ghidra-vibe" >&2
  exit 1
fi
export GHIDRA_INSTALL_DIR

for cand in \
  "${GHIDRA_INSTALL_DIR}/../../share/ghidra-vibe/runtime.env" \
  "${GHIDRA_INSTALL_DIR}/../share/ghidra-vibe/runtime.env"
do
  if [[ -f "$cand" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$cand"
    set +a
    break
  fi
done

# Prefer a local CFG engine jar. Full nix engine builds often OOM; store jars may still be stubs (~7k).
ENGINE_HOME_CAND="${GHIDRA_VIBE_ENGINE_HOME:-/tmp/ghidra-vibe-engine-cfg-local}"
ENGINE_JAR="$ENGINE_HOME_CAND/share/ghidra-vibe/engine/ghidra-vibe-inprocess.jar"
ENGINE_SRC="$ROOT/engine/inprocess/src/dev/ghidravibe/engine/InProcessEngine.java"
need_rebuild=0
if [[ "${GRAPH_REBUILD_ENGINE:-auto}" == "1" ]]; then
  need_rebuild=1
elif [[ "${GRAPH_REBUILD_ENGINE:-auto}" == "auto" ]]; then
  if [[ ! -f "$ENGINE_JAR" ]]; then
    need_rebuild=1
  elif [[ "$ENGINE_SRC" -nt "$ENGINE_JAR" ]]; then
    need_rebuild=1
  elif [[ "$(wc -c <"$ENGINE_JAR")" -lt 12000 ]]; then
    need_rebuild=1
  fi
fi
if [[ "$need_rebuild" == "1" ]]; then
  chmod +x "$ROOT/scripts/build-engine-local.sh"
  if ! "$ROOT/scripts/build-engine-local.sh" "$ENGINE_HOME_CAND"; then
    if [[ -f "$ENGINE_JAR" && "$(wc -c <"$ENGINE_JAR")" -ge 12000 ]]; then
      echo "WARN: engine rebuild failed; reusing existing CFG jar at $ENGINE_JAR" >&2
    else
      echo "FAIL: need CFG engine jar (build-engine-local.sh or GHIDRA_VIBE_ENGINE_HOME)" >&2
      exit 1
    fi
  fi
fi
if [[ -z "${GHIDRA_VIBE_ENGINE_HOME:-}" && -f "$ENGINE_JAR" ]]; then
  export GHIDRA_VIBE_ENGINE_HOME="$ENGINE_HOME_CAND"
fi
if [[ -n "${GHIDRA_VIBE_ENGINE_HOME:-}" ]]; then
  export GHIDRA_VIBE_ENGINE_LIB="${GHIDRA_VIBE_ENGINE_LIB:-$GHIDRA_VIBE_ENGINE_HOME/lib/libghidravibe_engine.dylib}"
  export GHIDRA_VIBE_ENGINE_CLASSPATH_FILE="${GHIDRA_VIBE_ENGINE_CLASSPATH_FILE:-$GHIDRA_VIBE_ENGINE_HOME/share/ghidra-vibe/engine/classpath.txt}"
fi
export GHIDRA_VIBE_ENGINE="${GHIDRA_VIBE_ENGINE:-inprocess}"
export GHIDRA_MCP_URL="$MCP_URL"

PROJ_GPR=""
PROGRAM_LEAF=""
for cand in \
  "$WHOAMI_WORKDIR/project/WhoamiGUI.gpr" \
  /tmp/ghidra-vibe-decomp-smoke/project/DecompSmoke.gpr
do
  if [[ -f "$cand" ]]; then
    PROJ_GPR="$cand"
    if [[ "$cand" == *Whoami* ]]; then PROGRAM_LEAF=whoami; else PROGRAM_LEAF=smoke_bin; fi
    break
  fi
done

if [[ -z "$PROJ_GPR" ]]; then
  echo "whoami fixture missing — running smoke-whoami-decompile.sh first …"
  "$ROOT/gui-tests/smoke-whoami-decompile.sh" || true
  PROJ_GPR="$WHOAMI_WORKDIR/project/WhoamiGUI.gpr"
  PROGRAM_LEAF=whoami
fi
if [[ ! -f "$PROJ_GPR" ]]; then
  echo "FAIL: no fixture project (.gpr)" >&2
  exit 1
fi

export GHIDRA_VIBE_PROJECT="$PROJ_GPR"
export GHIDRA_VIBE_PROGRAM="/$PROGRAM_LEAF"

if [[ "${GRAPH_REPACKAGE:-1}" == "1" ]]; then
  "$ROOT/macos/GhidraVibe/scripts/package-app.sh" "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app"
  rm -rf "$INSTALL"
  cp -R "$ROOT/macos/GhidraVibe/.build/GhidraVibe.app" "$INSTALL"
fi

defaults write dev.ghidravibe.app ghidra.vibe.userAgreementAccepted -bool true
defaults write dev.ghidravibe.app ghidra.vibe.welcomeHelpSeen -bool true
defaults write dev.ghidravibe.app ghidra.vibe.smokeStartProject -bool true
defaults write dev.ghidravibe.app ghidra.vibe.lastProject "$PROJ_GPR"
defaults write dev.ghidravibe.app ghidra.vibe.lastProgram "$PROGRAM_LEAF"

pkill -x GhidraVibe 2>/dev/null || true
sleep 1
nohup "$INSTALL/Contents/MacOS/GhidraVibe" >"$WORKDIR/app.log" 2>&1 &
disown || true

for i in $(seq 1 90); do
  if curl -fsS --max-time 2 "$GUI_URL/health" >/dev/null 2>&1 \
    && curl -fsS --max-time 2 "$MCP_URL/check_connection" >/dev/null 2>&1; then
    echo "ready at ${i}s"
    break
  fi
  sleep 1
done
curl -fsS "$GUI_URL/health" >/dev/null

curl -fsS -X POST "$GUI_URL/navigate" -H 'Content-Type: application/json' -d '{"pane":"codebrowser"}' >/dev/null
curl -fsS -X POST "$GUI_URL/action" -H 'Content-Type: application/json' -d '{"id":"fetch_functions"}' >/dev/null
sleep 2
curl -fsS -X POST "$GUI_URL/select_function" -H 'Content-Type: application/json' -d '{"name":"entry"}' >/dev/null \
  || curl -fsS -X POST "$GUI_URL/select_function" -H 'Content-Type: application/json' -d '{"name":"_main"}' >/dev/null
curl -fsS -X POST "$GUI_URL/refresh_function_graph" -H 'Content-Type: application/json' -d '{}' \
  >"$WORKDIR/graph.json"
cp "$WORKDIR/graph.json" "$ARTIFACTS/function-graph-state.json"

python3 - <<'PY'
import json, sys
path = "/tmp/ghidra-vibe-graph-smoke/graph.json"
st = json.load(open(path))
if "state" in st:
    st = st["state"]
nodes = int(st.get("functionGraphNodeCount") or 0)
edges = int(st.get("functionGraphEdgeCount") or 0)
fn = st.get("functionGraphFunction") or ""
status = st.get("statusMessage") or ""
print(f"function={fn} nodes={nodes} edges={edges}")
print(f"status={status}")
# Real CFG: more than the old single-node stub, with flow edges.
if nodes < 2 or edges < 1:
    print("FAIL: expected multi-block CFG with edges (native Function Graph)", file=sys.stderr)
    sys.exit(1)
if "blocks" not in status and nodes > 0:
    # status format: "Function Graph: name — N blocks, M edges"
    pass
print("OK smoke-function-graph (GUI)")
PY
