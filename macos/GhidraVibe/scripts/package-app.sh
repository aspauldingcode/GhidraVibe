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

xcrun swift build -c release --product GhidraVibe

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$RES"
cp "$BIN_DIR/GhidraVibe" "$APP_BIN"
chmod +x "$APP_BIN"

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
