#!/usr/bin/env bash
# Build GhidraVibe as a proper .app so agent-device can open it by name/path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
OUT="${1:-$ROOT/.build/GhidraVibe.app}"
BIN_DIR="$ROOT/.build/release"
APP_BIN="$OUT/Contents/MacOS/GhidraVibe"
PLIST="$OUT/Contents/Info.plist"
RES="$OUT/Contents/Resources"

cd "$ROOT"
# Keep Resources JSON in sync with native-ui
mkdir -p "$ROOT/Sources/GhidraVibe/Resources"
cp -f "$REPO/native-ui/layout/CodeBrowser.tool.json" \
      "$REPO/native-ui/a11y/catalog.json" \
      "$REPO/native-ui/menus/actions.json" \
      "$REPO/native-ui/parity/CodeBrowser.chrome.json" \
      "$REPO/native-ui/parity/Debugger.chrome.json" \
      "$REPO/native-ui/parity/Emulator.chrome.json" \
      "$REPO/native-ui/parity/VersionTracking.chrome.json" \
      "$ROOT/Sources/GhidraVibe/Resources/"

# If SKIP_SWIFT_BUILD is set (e.g., using pre-built nix binary), skip the Swift build
if [[ "${SKIP_SWIFT_BUILD:-}" != "1" ]]; then
  xcrun swift build -c release --product GhidraVibe
fi

# Remove old build, handling read-only files from Nix store
chmod -R u+w "$OUT" 2>/dev/null || true
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$RES"

# If using a pre-built app, copy it as the base
if [[ "${SKIP_SWIFT_BUILD:-}" == "1" && -f "$ROOT/.build/GhidraVibe.app/Contents/MacOS/GhidraVibe" ]]; then
  # Copy and make writable (Nix store files are read-only)
  echo "Using pre-built app from $ROOT/.build/GhidraVibe.app"
  cp -R "$ROOT/.build/GhidraVibe.app/." "$OUT/"
  chmod -R u+w "$OUT"
  # Pre-built app already has basic resources, skip to runtime.env generation
  # But we still need to add help and other runtime-specific files below
elif [[ -f "$BIN_DIR/GhidraVibe" ]]; then
  # Use the freshly Swift-built binary
  echo "Using freshly built binary from $BIN_DIR/GhidraVibe"
  cp "$BIN_DIR/GhidraVibe" "$APP_BIN"
  chmod +x "$APP_BIN"
  
  # Add resources for fresh build
  # Official Ghidra dragon icon + UI catalogs (read via Bundle.main / file paths)
  if [[ -f "$REPO/native-ui/icons/AppIcon.icns" ]]; then
    cp "$REPO/native-ui/icons/AppIcon.icns" "$RES/AppIcon.icns"
  elif [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$RES/AppIcon.icns"
  fi
  cp -f "$REPO/native-ui/icons/png/GhidraIcon256.png" "$RES/"
  cp -f "$REPO/native-ui/a11y/catalog.json" \
        "$REPO/native-ui/menus/actions.json" \
        "$REPO/native-ui/layout/CodeBrowser.tool.json" \
        "$REPO/native-ui/parity/CodeBrowser.chrome.json" \
        "$REPO/native-ui/parity/Debugger.chrome.json" \
        "$REPO/native-ui/parity/Emulator.chrome.json" \
        "$REPO/native-ui/parity/VersionTracking.chrome.json" \
        "$RES/"
else
  echo "ERROR: No GhidraVibe binary found. Either build with Swift or provide pre-built app." >&2
  exit 1
fi

# Stock JavaHelp corpus → Contents/Resources/help (package-time extract).
HELP_OUT="$REPO/native-ui/help"
if [[ -x "$REPO/scripts/extract-stock-help.py" ]] || [[ -f "$REPO/scripts/extract-stock-help.py" ]]; then
  python3 "$REPO/scripts/extract-stock-help.py" --out "$HELP_OUT" --quiet \
    || echo "warning: extract-stock-help failed — Help UI will use vibe fallback" >&2
fi
if [[ -d "$HELP_OUT/articles" && -f "$HELP_OUT/toc.json" ]]; then
  rm -rf "$RES/help"
  mkdir -p "$RES/help"
  cp -R "$HELP_OUT/." "$RES/help/"
  echo "bundled help → $RES/help"
else
  echo "warning: native-ui/help missing — open Help shows fallback topics only" >&2
fi

# Sidecar fallback + detect-maxmem (Finder/`open` has no nix --env).
mkdir -p "$RES/bin" "$RES/lib"
cp -f "$REPO/scripts/ghidra-vibe-mcp-headless" "$RES/bin/ghidra-vibe-mcp-headless"
chmod +x "$RES/bin/ghidra-vibe-mcp-headless"
if [[ -f "$REPO/scripts/lib/detect-maxmem.sh" ]]; then
  cp -f "$REPO/scripts/lib/detect-maxmem.sh" "$RES/lib/detect-maxmem.sh"
fi

# Bake paths so double-click works without `nix run`.
write_runtime_env() {
  local install="" engine="" java="" headless="$RES/bin/ghidra-vibe-mcp-headless" vibe_lib="$RES/lib"
  if [[ -n "${GHIDRA_INSTALL_DIR:-}" && -d "${GHIDRA_INSTALL_DIR}/Ghidra" ]]; then
    install="$GHIDRA_INSTALL_DIR"
  else
    install="$(ls -dt /nix/store/*-ghidra-vibe-*+native-*/lib/ghidra 2>/dev/null | head -1 || true)"
  fi
  if [[ -z "$install" || ! -d "$install/Ghidra" ]]; then
    install="$(ls -dt /nix/store/*-ghidra-vibe-*/lib/ghidra 2>/dev/null | head -1 || true)"
  fi
  if [[ -n "${GHIDRA_VIBE_ENGINE_HOME:-}" && -f "${GHIDRA_VIBE_ENGINE_HOME}/lib/libghidravibe_engine.dylib" ]]; then
    engine="$GHIDRA_VIBE_ENGINE_HOME"
  else
    engine="$(ls -dt /nix/store/*-ghidra-vibe-engine-* 2>/dev/null | head -1 || true)"
  fi
  if [[ -z "$engine" || ! -f "$engine/lib/libghidravibe_engine.dylib" ]]; then
    if [[ -f /tmp/ghidra-vibe-engine-cfg-local/lib/libghidravibe_engine.dylib ]]; then
      engine="/tmp/ghidra-vibe-engine-cfg-local"
    fi
  fi
  # Prefer a HotSpot home (`java_home`), not a bare nix JDK derivation root.
  if [[ -x /usr/libexec/java_home ]]; then
    java="$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home 2>/dev/null || true)"
  fi
  if [[ -n "${JAVA_HOME:-}" && -f "${JAVA_HOME}/lib/libjli.dylib" ]]; then
    java="$JAVA_HOME"
  fi

  if [[ -z "$install" || ! -d "$install/Ghidra" ]]; then
    echo "warning: GHIDRA_INSTALL_DIR not found — app will probe /nix/store at launch" >&2
  fi
  if [[ -z "$engine" || ! -f "$engine/lib/libghidravibe_engine.dylib" ]]; then
    echo "warning: engine home missing — trying local build…" >&2
    if [[ -x "$REPO/scripts/build-engine-local.sh" ]]; then
      "$REPO/scripts/build-engine-local.sh" /tmp/ghidra-vibe-engine-cfg-local || true
      if [[ -f /tmp/ghidra-vibe-engine-cfg-local/lib/libghidravibe_engine.dylib ]]; then
        engine="/tmp/ghidra-vibe-engine-cfg-local"
      fi
    fi
  fi

  # Bundle repo DSC import scripts so package-app picks up lock/retry fixes without a nix rebuild.
  local bundled_scripts="$RES/ghidra_scripts"
  local bundled_dyld="$RES/bin/ghidra-vibe-dyld"
  if [[ -f "$REPO/ghidra_scripts/ImportDyldCacheImage.java" ]]; then
    mkdir -p "$bundled_scripts"
    cp -f "$REPO/ghidra_scripts/"*.java "$bundled_scripts/"
  fi
  if [[ -x "$REPO/scripts/ghidra-vibe-dyld" ]]; then
    mkdir -p "$RES/bin"
    cp -f "$REPO/scripts/ghidra-vibe-dyld" "$bundled_dyld"
    chmod +x "$bundled_dyld"
  fi
  if [[ -x "$REPO/scripts/ghidra-vibe-analyzeHeadless" ]]; then
    mkdir -p "$RES/bin"
    cp -f "$REPO/scripts/ghidra-vibe-analyzeHeadless" "$RES/bin/ghidra-vibe-analyzeHeadless"
    chmod +x "$RES/bin/ghidra-vibe-analyzeHeadless"
  fi

  {
    echo "# Generated by package-app.sh — loaded by VibeRuntime on launch"
    [[ -n "$install" ]] && echo "GHIDRA_INSTALL_DIR=$install"
    [[ -n "$java" ]] && echo "JAVA_HOME=$java"
    [[ -n "$engine" ]] && echo "GHIDRA_VIBE_ENGINE_HOME=$engine"
    [[ -n "$engine" ]] && echo "GHIDRA_VIBE_ENGINE_LIB=$engine/lib/libghidravibe_engine.dylib"
    [[ -n "$engine" ]] && echo "GHIDRA_VIBE_ENGINE_CLASSPATH_FILE=$engine/share/ghidra-vibe/engine/classpath.txt"
    echo "GHIDRA_VIBE_MCP_HEADLESS=$headless"
    echo "GHIDRA_VIBE_LIB=$vibe_lib"
    echo "GHIDRA_VIBE_ENGINE=inprocess"
    echo "GHIDRA_MCP_URL=http://127.0.0.1:8089"
    echo "GHIDRA_VIBE_GUI_URL=http://127.0.0.1:8091"
    # Prefer bundled repo scripts (DSC lock/retry + overwrite) over nix store copies.
    if [[ -f "$bundled_scripts/ImportDyldCacheImage.java" ]]; then
      echo "GHIDRA_VIBE_SCRIPT_PATH=$bundled_scripts"
    fi
    if [[ -x "$bundled_dyld" ]]; then
      echo "GHIDRA_VIBE_DYLD=$bundled_dyld"
    fi
    if [[ -x "$RES/bin/ghidra-vibe-analyzeHeadless" ]]; then
      echo "GHIDRA_VIBE_HEADLESS=$RES/bin/ghidra-vibe-analyzeHeadless"
    fi
    if [[ -n "$install" ]]; then
      local root
      root="$(cd "$install/../.." && pwd)"
      if [[ ! -f "$bundled_scripts/ImportDyldCacheImage.java" && -d "$root/share/ghidra-vibe/ghidra_scripts" ]]; then
        echo "GHIDRA_VIBE_SCRIPT_PATH=$root/share/ghidra-vibe/ghidra_scripts"
      fi
      if [[ ! -x "$bundled_dyld" && -x "$root/bin/ghidra-vibe-dyld" ]]; then
        echo "GHIDRA_VIBE_DYLD=$root/bin/ghidra-vibe-dyld"
      fi
      [[ -x "$root/bin/ghidra-vibe-apple" ]] && echo "GHIDRA_VIBE_APPLE=$root/bin/ghidra-vibe-apple"
      [[ -x "$root/bin/ghidra-vibe-jspace" ]] && echo "GHIDRA_VIBE_JSPACE=$root/bin/ghidra-vibe-jspace"
      # Prefer packaged detect-maxmem from the ghidra-vibe share tree when present.
      if [[ -f "$root/share/ghidra-vibe/lib/detect-maxmem.sh" ]]; then
        echo "GHIDRA_VIBE_LIB=$root/share/ghidra-vibe/lib"
      fi
    fi
  } >"$RES/runtime.env"
  echo "wrote $RES/runtime.env"
}

write_runtime_env

cat >"$PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>GhidraVibe</string>
  <key>CFBundleIdentifier</key>
  <string>dev.ghidravibe.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>GhidraVibe</string>
  <key>CFBundleDisplayName</key>
  <string>GhidraVibe</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAccessibilitySupportsNonInteractiveElements</key>
  <true/>
</dict>
</plist>
EOF

echo "$OUT"
