# Native macOS GhidraVibe UI — host Xcode (`xcrun swift`) + offline SwiftPM deps.
# Never `swift run` from the flake source tree at runtime (store is read-only).
#
# Deps fetched like swiftpm2nix (macos/GhidraVibe/nix/), then rewritten to path
# packages: Xcode SwiftPM 6.2 (workspace-state v7) still tries to git-clone
# remoteSourceControl deps even when checkouts are seeded.
# Compiler: host Xcode (SwiftUI / macOS 26); not pkgs.swift.
{
  lib,
  stdenvNoCC,
  fetchgit,
  callPackage,
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

  swiftpm2nixHelpers = callPackage ./swiftpm2nix-helpers.nix { inherit fetchgit; };
  generated = swiftpm2nixHelpers.helpers ../../macos/GhidraVibe/nix;
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

  preferLocalBuild = true;
  allowSubstitutes = false;
  __noChroot = true;

  dontStrip = true;

  configurePhase = ''
    runHook preConfigure
    ${generated.configure}

    # Force offline path deps (Xcode SPM will not honor seeded remotes alone).
    # -L: checkouts are symlinks into the store; copy the referent and make writable.
    mkdir -p Vendor
    for name in TintedThemingSwift textual swift-concurrency-extras swiftui-math Yams; do
      rm -rf "Vendor/$name"
      cp -R -L ".build/checkouts/$name" "Vendor/$name"
      chmod -R u+w "Vendor/$name"
    done

    cat > Package.swift <<'EOF'
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GhidraVibe",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "GhidraVibe", targets: ["GhidraVibe"])
    ],
    dependencies: [
        .package(path: "Vendor/TintedThemingSwift"),
        .package(path: "Vendor/textual"),
    ],
    targets: [
        .executableTarget(
            name: "GhidraVibe",
            dependencies: [
                .product(name: "TintedThemingSwift", package: "TintedThemingSwift"),
                .product(name: "Textual", package: "textual"),
            ],
            path: "Sources/GhidraVibe",
            exclude: ["Resources"]
        )
    ]
)
EOF

    cat > Vendor/TintedThemingSwift/Package.swift <<'EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TintedThemingSwift",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .watchOS(.v8),
        .tvOS(.v15)
    ],
    products: [
        .library(name: "TintedThemingSwift", targets: ["TintedThemingSwift"]),
    ],
    dependencies: [
        .package(path: "../Yams"),
    ],
    targets: [
        .target(name: "TintedThemingSwift", dependencies: ["Yams"]),
    ]
)
EOF

    cat > Vendor/textual/Package.swift <<'EOF'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "textual",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
    .tvOS(.v18),
    .watchOS(.v11),
    .visionOS(.v2),
  ],
  products: [
    .library(name: "Textual", targets: ["Textual"])
  ],
  dependencies: [
    .package(path: "../swift-concurrency-extras"),
    .package(path: "../swiftui-math"),
  ],
  targets: [
    .target(
      name: "Textual",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "SwiftUIMath", package: "swiftui-math"),
      ],
      resources: [
        .process("Internal/Highlighter/Prism")
      ],
      swiftSettings: [
        .define(
          "TEXTUAL_ENABLE_LINKS",
          .when(platforms: [.macOS, .macCatalyst, .iOS, .watchOS, .visionOS])),
        .define(
          "TEXTUAL_ENABLE_TEXT_SELECTION",
          .when(platforms: [.macOS, .macCatalyst, .iOS, .visionOS])),
      ]
    ),
  ]
)
EOF

    cat > Vendor/swiftui-math/Package.swift <<'EOF'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "swiftui-math",
  platforms: [
    .macOS(.v14),
    .iOS(.v17),
    .tvOS(.v17),
    .watchOS(.v10),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "SwiftUIMath", targets: ["SwiftUIMath"])
  ],
  targets: [
    .target(
      name: "SwiftUIMath",
      dependencies: [],
      resources: [.copy("mathFonts.bundle")]
    ),
  ]
)
EOF

    rm -f Package.resolved
    rm -rf .build
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    export HOME="$NIX_BUILD_TOP/home"
    export CFFIXED_USER_HOME="$HOME"
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

    /usr/bin/xcrun swift build -c release --product GhidraVibe \
      --disable-sandbox
    BIN="$(/usr/bin/xcrun swift build -c release --product GhidraVibe --show-bin-path --disable-sandbox)"
    test -x "$BIN/GhidraVibe"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    BIN="$(/usr/bin/xcrun swift build -c release --product GhidraVibe --show-bin-path --disable-sandbox)"
    mkdir -p \
      "$out/bin" \
      "$out/Applications/GhidraVibe.app/Contents/MacOS" \
      "$out/Applications/GhidraVibe.app/Contents/Resources"

    install -m755 "$BIN/GhidraVibe" "$out/bin/GhidraVibe"
    install -m755 "$BIN/GhidraVibe" \
      "$out/Applications/GhidraVibe.app/Contents/MacOS/GhidraVibe"

    if [[ -f Resources/AppIcon.icns ]]; then
      cp Resources/AppIcon.icns "$out/Applications/GhidraVibe.app/Contents/Resources/AppIcon.icns"
    else
      cp ${appIcon} "$out/Applications/GhidraVibe.app/Contents/Resources/AppIcon.icns"
    fi
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
