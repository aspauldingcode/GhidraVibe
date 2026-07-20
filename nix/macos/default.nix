# Native macOS GhidraVibe UI — built with Xcode's SwiftPM into the Nix store.
# Never `swift run` from the flake source tree at runtime (store is read-only).
{
  lib,
  stdenvNoCC,
}:

assert stdenvNoCC.isDarwin;

let
  appIcon = ../../native-ui/icons/AppIcon.icns;
  a11yCatalog = ../../native-ui/a11y/catalog.json;
  actionsJson = ../../native-ui/menus/actions.json;
  layoutJson = ../../native-ui/layout/CodeBrowser.tool.json;
  chromeJson = ../../native-ui/parity/CodeBrowser.chrome.json;
  debuggerChromeJson = ../../native-ui/parity/Debugger.chrome.json;
  emulatorChromeJson = ../../native-ui/parity/Emulator.chrome.json;
  vtChromeJson = ../../native-ui/parity/VersionTracking.chrome.json;
  ghidraIconPng = ../../native-ui/icons/png/GhidraIcon256.png;
in
stdenvNoCC.mkDerivation rec {
  pname = "ghidra-vibe-app";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = ../../macos/GhidraVibe;
    filter =
      path: type:
      let
        base = baseNameOf path;
      in
      !(
        base == ".build"
        || lib.hasSuffix ".app" base
        || base == ".DS_Store"
      );
  };

  # Needs host Xcode (`xcrun swift`) + AppKit/SwiftUI; not pkgs.swift.
  # Build with: nix build .#ghidra-vibe-app --option sandbox false
  # (SwiftPM nested sandbox-exec is incompatible with the Nix builder sandbox.)
  preferLocalBuild = true;
  allowSubstitutes = false;
  __noChroot = true;

  dontConfigure = true;
  dontStrip = true;

  buildPhase = ''
    runHook preBuild
    # SwiftPM / swiftc use $HOME and nested sandbox-exec; keep everything under the build tree.
    export HOME="$NIX_BUILD_TOP/home"
    export TMPDIR="$NIX_BUILD_TOP/tmp"
    export TMP="$TMPDIR"
    export TEMP="$TMPDIR"
    export XDG_CACHE_HOME="$HOME/Library/Caches"
    export XDG_CONFIG_HOME="$HOME/Library/Preferences"
    export SWIFTPM_CACHE="$XDG_CACHE_HOME/org.swift.swiftpm"
    export CLANG_MODULE_CACHE_PATH="$NIX_BUILD_TOP/clang-module-cache"
    export SWIFT_MODULE_CACHE_PATH="$NIX_BUILD_TOP/swift-module-cache"
    export SWIFTPM_DISABLE_SANDBOX=1
    mkdir -p \
      "$HOME/Library/Caches/org.swift.swiftpm" \
      "$HOME/Library/org.swift.swiftpm/configuration" \
      "$HOME/Library/org.swift.swiftpm/security" \
      "$TMPDIR" \
      "$CLANG_MODULE_CACHE_PATH" \
      "$SWIFT_MODULE_CACHE_PATH"

    BUILD_DIR="$NIX_BUILD_TOP/swift-build"
    /usr/bin/xcrun swift build -c release --product GhidraVibe \
      --build-path "$BUILD_DIR" \
      --disable-sandbox
    test -x "$BUILD_DIR/release/GhidraVibe"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    BUILD_DIR="$NIX_BUILD_TOP/swift-build"
    mkdir -p \
      "$out/bin" \
      "$out/Applications/GhidraVibe.app/Contents/MacOS" \
      "$out/Applications/GhidraVibe.app/Contents/Resources"

    install -m755 "$BUILD_DIR/release/GhidraVibe" "$out/bin/GhidraVibe"
    install -m755 "$BUILD_DIR/release/GhidraVibe" \
      "$out/Applications/GhidraVibe.app/Contents/MacOS/GhidraVibe"

    if [[ -f Resources/AppIcon.icns ]]; then
      cp Resources/AppIcon.icns "$out/Applications/GhidraVibe.app/Contents/Resources/AppIcon.icns"
    else
      cp ${appIcon} "$out/Applications/GhidraVibe.app/Contents/Resources/AppIcon.icns"
    fi
    # Explicit basenames — nix store paths are hash-prefixed.
    cp ${a11yCatalog} "$out/Applications/GhidraVibe.app/Contents/Resources/catalog.json"
    cp ${actionsJson} "$out/Applications/GhidraVibe.app/Contents/Resources/actions.json"
    cp ${layoutJson} "$out/Applications/GhidraVibe.app/Contents/Resources/CodeBrowser.tool.json"
    cp ${chromeJson} "$out/Applications/GhidraVibe.app/Contents/Resources/CodeBrowser.chrome.json"
    cp ${debuggerChromeJson} "$out/Applications/GhidraVibe.app/Contents/Resources/Debugger.chrome.json"
    cp ${emulatorChromeJson} "$out/Applications/GhidraVibe.app/Contents/Resources/Emulator.chrome.json"
    cp ${vtChromeJson} "$out/Applications/GhidraVibe.app/Contents/Resources/VersionTracking.chrome.json"
    cp ${ghidraIconPng} "$out/Applications/GhidraVibe.app/Contents/Resources/GhidraIcon256.png"

    cat > "$out/Applications/GhidraVibe.app/Contents/Info.plist" <<'EOF'
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
</dict>
</plist>
EOF

    ln -s GhidraVibe "$out/bin/ghidra-vibe-gui"
    runHook postInstall
  '';

  meta = with lib; {
    description = "GhidraVibe native SwiftUI shell (macOS)";
    platforms = platforms.darwin;
    mainProgram = "GhidraVibe";
    license = licenses.asl20;
  };
}
