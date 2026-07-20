#!/usr/bin/env bash
# Build the in-process engine jar (+ reuse/copy JNI dylib) without a full nix derivation.
# Use when `nix build .#ghidra-vibe-engine` OOMs or you need a quick CFG jar for GUI smokes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/ghidra-vibe-engine-cfg-local}"
SRC="$ROOT/engine/inprocess"

resolve_ghidra() {
  if [[ -n "${GHIDRA_INSTALL_DIR:-}" && -d "${GHIDRA_INSTALL_DIR}/Ghidra" ]]; then
    echo "$GHIDRA_INSTALL_DIR"
    return 0
  fi
  if [[ -d "$ROOT/result/lib/ghidra/Ghidra" ]]; then
    echo "$ROOT/result/lib/ghidra"
    return 0
  fi
  local d
  for d in $(ls -dt /nix/store/*-ghidra-vibe-*+native-*/lib/ghidra 2>/dev/null || true); do
    if [[ -d "$d/Ghidra" ]]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

if ! GHIDRA_HOME="$(resolve_ghidra)"; then
  echo "FAIL: set GHIDRA_INSTALL_DIR" >&2
  exit 1
fi

JAVA_HOME="${JAVA_HOME:-}"
if [[ -z "$JAVA_HOME" ]]; then
  if [[ -x /usr/libexec/java_home ]]; then
    JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home 2>/dev/null || true)"
  fi
fi
JAVAC="${JAVA_HOME:+$JAVA_HOME/bin/javac}"
JAR="${JAVA_HOME:+$JAVA_HOME/bin/jar}"
JAVAC="${JAVAC:-javac}"
JAR="${JAR:-jar}"

MCP_JAR="$(echo "$GHIDRA_HOME"/Ghidra/Extensions/GhidraMCP/lib/GhidraMCP-*.jar | awk '{print $1}')"
test -f "$MCP_JAR"

COMPILE_CP="$MCP_JAR"
for j in \
  "$GHIDRA_HOME/Ghidra/Framework/Utility/lib/Utility.jar" \
  "$GHIDRA_HOME/Ghidra/Framework/Generic/lib/Generic.jar" \
  "$GHIDRA_HOME/Ghidra/Framework/Project/lib/Project.jar" \
  "$GHIDRA_HOME/Ghidra/Framework/SoftwareModeling/lib/SoftwareModeling.jar" \
  "$GHIDRA_HOME/Ghidra/Features/Base/lib/Base.jar"
do
  COMPILE_CP+=":$j"
done

BUILD="$OUT/_build"
rm -rf "$BUILD"
mkdir -p "$BUILD/classes" "$OUT/lib" "$OUT/share/ghidra-vibe/engine"

"$JAVAC" --release 21 -cp "$COMPILE_CP" -d "$BUILD/classes" \
  "$SRC/src/dev/ghidravibe/engine/InProcessEngine.java"
"$JAR" --create --file "$OUT/share/ghidra-vibe/engine/ghidra-vibe-inprocess.jar" -C "$BUILD/classes" .

# Reuse an existing JNI dylib when present (JNI surface is stable).
DYLIB_SRC=""
for cand in \
  "${GHIDRA_VIBE_ENGINE_LIB:-}" \
  /tmp/ghidra-vibe-engine-cfg-local/lib/libghidravibe_engine.dylib \
  $(ls -dt /nix/store/*-ghidra-vibe-engine-*/lib/libghidravibe_engine.dylib 2>/dev/null || true)
do
  if [[ -n "$cand" && -f "$cand" ]]; then
    DYLIB_SRC="$cand"
    break
  fi
done

if [[ -n "$DYLIB_SRC" ]]; then
  cp "$DYLIB_SRC" "$OUT/lib/libghidravibe_engine.dylib"
else
  # Build JNI from source.
  JNI_INC=""
  if [[ -n "${JAVA_HOME:-}" && -d "$JAVA_HOME/include" ]]; then
    JNI_INC="$JAVA_HOME/include"
  elif [[ -d /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/JavaVM.framework/Headers ]]; then
    JNI_INC="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/JavaVM.framework/Headers"
  fi
  test -n "$JNI_INC"
  clang -shared -fPIC -o "$OUT/lib/libghidravibe_engine.dylib" \
    "$SRC/jni/ghidra_vibe_engine.c" \
    -I"$JNI_INC" -I"$JNI_INC/darwin" \
    -install_name @rpath/libghidravibe_engine.dylib
fi

{
  echo -n "$OUT/share/ghidra-vibe/engine/ghidra-vibe-inprocess.jar"
  find "$GHIDRA_HOME" -name '*.jar' -print | while read -r j; do
    printf ':%s' "$j"
  done
  echo
} >"$OUT/share/ghidra-vibe/engine/classpath.txt"

rm -rf "$BUILD"
echo "OK engine -> $OUT"
echo "  export GHIDRA_VIBE_ENGINE_HOME=$OUT"
echo "  export GHIDRA_VIBE_ENGINE_LIB=$OUT/lib/libghidravibe_engine.dylib"
echo "  export GHIDRA_VIBE_ENGINE_CLASSPATH_FILE=$OUT/share/ghidra-vibe/engine/classpath.txt"
