{
  description = "GhidraVibe — full Ghidra from source, native GUI, optional MCP, dyld/Malimite";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Full NSA Ghidra source tree (same rev nixpkgs builds). Documented for
    # product identity — engine build still uses pkgs.ghidra (Gradle + deps.json).
    ghidra-src = {
      url = "github:NationalSecurityAgency/Ghidra/Ghidra_12.1.2_build";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ghidra-src,
      ...
    }:
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ]
      (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          java = pkgs.openjdk21;
          # Full Ghidra engine — Gradle from-source (nixpkgs build.nix). Never ghidra-bin.
          # ghidra-src flake input pins the same upstream tree for docs / future patches.
          ghidraFromSource = pkgs.ghidra;
          _ghidraSrcPin = ghidra-src; # keep input live for `nix flake metadata`
          ghidraMcpExtension = pkgs.callPackage ./nix/extensions/ghidra-mcp.nix { };
          ghidraVibeTools = pkgs.callPackage ./nix/rust/default.nix { };
          ghidraVibe = pkgs.callPackage ./nix/ghidra/default.nix {
            ghidra = ghidraFromSource;
            inherit ghidraMcpExtension ghidraVibeTools;
          };

          # In-process engine (JNI) for the native GUI — not the headless sidecar.
          ghidraVibeEngine = pkgs.callPackage ./nix/engine/default.nix {
            inherit ghidraVibe;
          };

          # macOS SwiftUI shell — Nix-built binary in the store (not `swift run` from source).
          ghidraVibeApp =
            if pkgs.stdenv.isDarwin then
              pkgs.callPackage ./nix/macos/default.nix { }
            else
              null;

          extractDyld = pkgs.writeShellScriptBin "extract" ''
            set -euo pipefail
            if [[ "$(uname)" != "Darwin" ]]; then
              echo "dyld extraction is macOS-only. Prefer on-device DSC via ghidra-vibe-dyld."
              exit 1
            fi
            # Generic: extract <install-path> [outdir]
            # Discouraged vs Window → Shared Cache (DyldCacheFileSystem + Apple symbols).
            IMAGE="''${1:-}"
            if [[ -z "$IMAGE" || "$IMAGE" == "-h" || "$IMAGE" == "--help" ]]; then
              echo "Usage: extract <dyld-image-install-path> [outdir]"
              echo "Prefer: ghidra-vibe-dyld import --image <name|path>"
              exit 1
            fi
            for c in \
              "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e" \
              "/System/Library/dyld/dyld_shared_cache_arm64e" \
              "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_x86_64" \
              "/System/Library/dyld/dyld_shared_cache_x86_64"; do
              if [[ -f "$c" ]]; then DYLD_CACHE="$c"; break; fi
            done
            if [[ -z "''${DYLD_CACHE:-}" ]]; then
              echo "Could not find a dyld shared cache."
              exit 1
            fi
            BASE="$(basename "$IMAGE")"
            OUT_DIR="''${2:-$PWD/dyld-extracted/$BASE}"
            mkdir -p "$OUT_DIR"
            nix shell nixpkgs#ipsw -c ipsw dyld extract "$DYLD_CACHE" "$IMAGE" -o "$OUT_DIR" --force
            echo "output: $OUT_DIR"
          '';

          ghidraVibeGtk =
            if pkgs.stdenv.isLinux then
              pkgs.stdenv.mkDerivation {
                pname = "ghidra-vibe-gtk";
                version = "0.1.0";
                src = ./linux/GhidraVibe;
                nativeBuildInputs = [
                  pkgs.meson
                  pkgs.ninja
                  pkgs.pkg-config
                  pkgs.wrapGAppsHook4
                ];
                buildInputs = [
                  pkgs.gtk4
                  pkgs.libadwaita
                  pkgs.json-glib
                ];
                postInstall = ''
                  mkdir -p $out/share/ghidra-vibe
                  cp ${./native-ui/layout/CodeBrowser.tool.json} $out/share/ghidra-vibe/
                  cp ${./native-ui/a11y/catalog.json} $out/share/ghidra-vibe/
                  cp ${./native-ui/menus/actions.json} $out/share/ghidra-vibe/
                  cp ${./native-ui/parity/CodeBrowser.chrome.json} $out/share/ghidra-vibe/
                  mkdir -p $out/share/icons/hicolor/256x256/apps
                  cp ${./native-ui/icons/png/GhidraIcon256.png} $out/share/icons/hicolor/256x256/apps/ghidra.png
                '';
                meta = with pkgs.lib; {
                  description = "GhidraVibe GTK shell";
                  platforms = platforms.linux;
                  mainProgram = "ghidra-vibe";
                };
              }
            else
              null;

          # Prefer packaged dyld (sets SCRIPT_PATH). Thin wrapper keeps repo script for fast iteration.
          dyldHelper = pkgs.writeShellScriptBin "ghidra-vibe-dyld" ''
            export GHIDRA_VIBE_SCRIPT_PATH="''${GHIDRA_VIBE_SCRIPT_PATH:-${./ghidra_scripts}}"
            export GHIDRA_VIBE_DSC_INDEX="''${GHIDRA_VIBE_DSC_INDEX:-${ghidraVibe}/bin/ghidra-vibe-dsc-index}"
            export GHIDRA_VIBE_HEADLESS="''${GHIDRA_VIBE_HEADLESS:-${ghidraVibe}/share/ghidra-vibe/ghidra-vibe-analyzeHeadless}"
            export GHIDRA_INSTALL_DIR="''${GHIDRA_INSTALL_DIR:-${ghidraVibe}/lib/ghidra}"
            exec ${./scripts/ghidra-vibe-dyld} "$@"
          '';

          appleHelper = pkgs.writeShellScriptBin "ghidra-vibe-apple" ''
            export PYTHONPATH="${./scripts/lib}''${PYTHONPATH:+:$PYTHONPATH}"
            export GHIDRA_VIBE_SCRIPT_PATH="''${GHIDRA_VIBE_SCRIPT_PATH:-${./ghidra_scripts}}"
            export GHIDRA_VIBE_HEADLESS="''${GHIDRA_VIBE_HEADLESS:-${ghidraVibe}/share/ghidra-vibe/ghidra-vibe-analyzeHeadless}"
            exec ${./scripts/ghidra-vibe-apple} "$@"
          '';

          mcpExtHelper = pkgs.writeShellScriptBin "ghidra-vibe-mcp-ext" ''
            export PYTHONPATH="${./scripts/lib}''${PYTHONPATH:+:$PYTHONPATH}"
            export GHIDRA_VIBE_DYLD="''${GHIDRA_VIBE_DYLD:-${dyldHelper}/bin/ghidra-vibe-dyld}"
            export GHIDRA_VIBE_JSPACE="''${GHIDRA_VIBE_JSPACE:-${ghidraVibe}/bin/ghidra-vibe-jspace}"
            export GHIDRA_VIBE_SCRIPT_PATH="''${GHIDRA_VIBE_SCRIPT_PATH:-${./ghidra_scripts}}"
            export GHIDRA_VIBE_HEADLESS="''${GHIDRA_VIBE_HEADLESS:-${ghidraVibe}/share/ghidra-vibe/ghidra-vibe-analyzeHeadless}"
            exec ${./scripts/ghidra-vibe-mcp-ext} "$@"
          '';

          mcpHeadlessHelper = pkgs.writeShellScriptBin "ghidra-vibe-mcp-headless" ''
            export GHIDRA_INSTALL_DIR="''${GHIDRA_INSTALL_DIR:-${ghidraVibe}/lib/ghidra}"
            export JAVA_HOME="''${JAVA_HOME:-${java}}"
            # Script is a lone store path — point it at packaged lib/detect-maxmem.sh.
            export GHIDRA_VIBE_LIB="''${GHIDRA_VIBE_LIB:-${ghidraVibe}/share/ghidra-vibe/lib}"
            exec ${./scripts/ghidra-vibe-mcp-headless} "$@"
          '';

          runGhidra =
            let
              guiApp =
                if ghidraVibeApp != null then
                  "${ghidraVibeApp}/Applications/GhidraVibe.app"
                else
                  null;
              guiExec =
                if ghidraVibeApp != null then
                  "${ghidraVibeApp}/bin/GhidraVibe"
                else
                  null;
            in
            pkgs.writeShellScriptBin "ghidra-vibe" ''
              set -euo pipefail
              export GHIDRA_INSTALL_DIR="${ghidraVibe}/lib/ghidra"
              # Always the flake JDK (.home) — do not inherit a broken shell JAVA_HOME.
              export JAVA_HOME="${java.home}"
              export GHIDRA_VIBE_BIN="${ghidraVibe}/bin/ghidra"
              export GHIDRA_VIBE_HEADLESS="${ghidraVibe}/bin/ghidra-analyzeHeadless"
              export GHIDRA_VIBE_MCP_BRIDGE="${ghidraVibe}/share/ghidra-mcp/bridge_mcp_ghidra.py"
              export GHIDRA_VIBE_MCP_HEADLESS="${mcpHeadlessHelper}/bin/ghidra-vibe-mcp-headless"
              # GUI default: embed JVM in GhidraVibe. Headless CLI stays mcp-headless.
              export GHIDRA_VIBE_ENGINE="''${GHIDRA_VIBE_ENGINE:-inprocess}"
              export GHIDRA_VIBE_ENGINE_HOME="${ghidraVibeEngine}"
              export GHIDRA_VIBE_ENGINE_LIB="${ghidraVibeEngine}/lib/libghidravibe_engine${
                if pkgs.stdenv.isDarwin then ".dylib" else ".so"
              }"
              export GHIDRA_VIBE_ENGINE_CLASSPATH_FILE="${ghidraVibeEngine}/share/ghidra-vibe/engine/classpath.txt"
              export GHIDRA_VIBE_EXTRACT="${extractDyld}/bin/extract"
              export GHIDRA_VIBE_DYLD="${dyldHelper}/bin/ghidra-vibe-dyld"
              export GHIDRA_VIBE_APPLE="${appleHelper}/bin/ghidra-vibe-apple"
              export GHIDRA_VIBE_MCP_EXT="${mcpExtHelper}/bin/ghidra-vibe-mcp-ext"
              export GHIDRA_VIBE_MCP_EXT_URL="''${GHIDRA_VIBE_MCP_EXT_URL:-http://127.0.0.1:8092}"
              export GHIDRA_VIBE_SCRIPT_PATH="${ghidraVibe}/share/ghidra-vibe/ghidra_scripts"
              export GHIDRA_VIBE_JSPACE="${ghidraVibe}/bin/ghidra-vibe-jspace"
              export GHIDRA_VIBE_JSPACE_BIN="${ghidraVibe}/bin/ghidra-vibe-jspace"
              export GHIDRA_VIBE_DSC_INDEX="${ghidraVibe}/bin/ghidra-vibe-dsc-index"
              export GHIDRA_VIBE_RAG_MCP="${ghidraVibe}/bin/ghidra-vibe-rag-mcp"
              # Prefer RAM-aware headless wrapper (not stock 2G nix analyzeHeadless).
              export GHIDRA_VIBE_HEADLESS="${ghidraVibe}/share/ghidra-vibe/ghidra-vibe-analyzeHeadless"
              export GHIDRA_MCP_URL="''${GHIDRA_MCP_URL:-''${GHIDRA_MCP_SERVER:-http://127.0.0.1:8089}}"
              export GHIDRA_MCP_SERVER="$GHIDRA_MCP_URL"
              export GHIDRA_VIBE_GUI_URL="''${GHIDRA_VIBE_GUI_URL:-http://127.0.0.1:8091}"
              export GHIDRA_VIBE_NATIVE_UI=1
              # Prefer Xcode swift demangler for Swift/SwiftUI RE
              export PATH="/usr/bin:/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:''${PATH}"

              if [[ "$(uname)" == "Darwin" ]]; then
                ${
                  if guiApp != null && guiExec != null then
                    ''
                      # LaunchServices activation (Dock + key window). Fall back to bare exec.
                      if [[ "''${GHIDRA_VIBE_OPEN_APP:-1}" == "1" && -d "${guiApp}" ]]; then
                        # Pass through analysis env — `open` does not inherit the shell env.
                        exec /usr/bin/open -n "${guiApp}" \
                          --env GHIDRA_INSTALL_DIR="$GHIDRA_INSTALL_DIR" \
                          --env JAVA_HOME="$JAVA_HOME" \
                          --env GHIDRA_VIBE_BIN="$GHIDRA_VIBE_BIN" \
                          --env GHIDRA_VIBE_HEADLESS="$GHIDRA_VIBE_HEADLESS" \
                          --env GHIDRA_VIBE_MCP_BRIDGE="$GHIDRA_VIBE_MCP_BRIDGE" \
                          --env GHIDRA_VIBE_MCP_HEADLESS="$GHIDRA_VIBE_MCP_HEADLESS" \
                          --env GHIDRA_VIBE_ENGINE="$GHIDRA_VIBE_ENGINE" \
                          --env GHIDRA_VIBE_ENGINE_HOME="$GHIDRA_VIBE_ENGINE_HOME" \
                          --env GHIDRA_VIBE_ENGINE_LIB="$GHIDRA_VIBE_ENGINE_LIB" \
                          --env GHIDRA_VIBE_ENGINE_CLASSPATH_FILE="$GHIDRA_VIBE_ENGINE_CLASSPATH_FILE" \
                          --env GHIDRA_VIBE_LIB="${ghidraVibe}/share/ghidra-vibe/lib" \
                          --env GHIDRA_VIBE_EXTRACT="$GHIDRA_VIBE_EXTRACT" \
                          --env GHIDRA_VIBE_DYLD="$GHIDRA_VIBE_DYLD" \
                          --env GHIDRA_VIBE_APPLE="$GHIDRA_VIBE_APPLE" \
                          --env GHIDRA_VIBE_MCP_EXT="$GHIDRA_VIBE_MCP_EXT" \
                          --env GHIDRA_VIBE_MCP_EXT_URL="$GHIDRA_VIBE_MCP_EXT_URL" \
                          --env GHIDRA_VIBE_SCRIPT_PATH="$GHIDRA_VIBE_SCRIPT_PATH" \
                          --env GHIDRA_VIBE_HEADLESS="$GHIDRA_VIBE_HEADLESS" \
                          --env GHIDRA_VIBE_JSPACE="$GHIDRA_VIBE_JSPACE" \
                          --env GHIDRA_VIBE_JSPACE_BIN="$GHIDRA_VIBE_JSPACE_BIN" \
                          --env GHIDRA_VIBE_DSC_INDEX="$GHIDRA_VIBE_DSC_INDEX" \
                          --env GHIDRA_VIBE_RAG_MCP="$GHIDRA_VIBE_RAG_MCP" \
                          --env GHIDRA_MCP_URL="$GHIDRA_MCP_URL" \
                          --env GHIDRA_MCP_SERVER="$GHIDRA_MCP_SERVER" \
                          --env GHIDRA_VIBE_GUI_URL="$GHIDRA_VIBE_GUI_URL" \
                          --env GHIDRA_VIBE_NATIVE_UI=1 \
                          --env GHIDRA_VIBE_UI_DATA="${guiApp}/Contents/Resources" \
                          --args "$@"
                      fi
                      export GHIDRA_VIBE_UI_DATA="''${GHIDRA_VIBE_UI_DATA:-${guiApp}/Contents/Resources}"
                      exec "${guiExec}" "$@"
                    ''
                  else
                    ''
                      echo "GhidraVibe.app missing — native macOS UI is required (Swing is not shipped)." >&2
                      exit 1
                    ''
                }
              fi
              ${
                if ghidraVibeGtk != null then
                  ''
                    export GHIDRA_VIBE_UI_DATA="${ghidraVibeGtk}/share/ghidra-vibe"
                    exec "${ghidraVibeGtk}/bin/ghidra-vibe" "$@"
                  ''
                else
                  ''
                    echo "GhidraVibe GTK UI not built for this system. Swing FrontEnd is not shipped." >&2
                    echo "Use headless: ghidra-analyzeHeadless / ghidra-vibe-dyld" >&2
                    exit 1
                  ''
              }
            '';

          srcRoot = ./.;
        in
        {
          packages = {
            default = runGhidra;
            ghidra-vibe = ghidraVibe;
            ghidra-vibe-engine = ghidraVibeEngine;
            ghidra-vibe-tools = ghidraVibeTools;
            extract = extractDyld;
            dyld = dyldHelper;
            mcp-headless = mcpHeadlessHelper;
          }
          // pkgs.lib.optionalAttrs (ghidraVibeApp != null) {
            ghidra-vibe-app = ghidraVibeApp;
          }
          // pkgs.lib.optionalAttrs (ghidraVibeGtk != null) {
            ghidra-vibe-gtk = ghidraVibeGtk;
          };

          apps.default = flake-utils.lib.mkApp {
            drv = runGhidra;
            name = "ghidra-vibe";
          };

          devShells.default = pkgs.mkShell {
            buildInputs = [
              ghidraVibe
              runGhidra
              java
              dyldHelper
              extractDyld
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.swift ];
            JAVA_HOME = "${java}";
            GHIDRA_INSTALL_DIR = "${ghidraVibe}/lib/ghidra";
          };

          checks = {
            ghidraMcpBundled = pkgs.runCommand "check-ghidra-mcp-bundled" { } ''
              test -d "${ghidraVibe}/lib/ghidra/Ghidra/Extensions/GhidraMCP"
              test -f "${ghidraVibe}/share/ghidra-mcp/bridge_mcp_ghidra.py"
              test -f "${ghidraVibe}/share/ghidra-mcp/bridge_mcp_gui.py"
              test -x "${ghidraVibe}/share/ghidra-mcp/bridge_mcp_rag.py"
              test -x "${ghidraVibe}/bin/ghidra-vibe-jspace"
              test -x "${ghidraVibe}/bin/ghidra-vibe-dsc-index"
              test -x "${ghidraVibe}/bin/ghidra-vibe-rag-mcp"
              test -f "${ghidraVibe}/share/ghidra-vibe/lib/detect-maxmem.sh"
              touch $out
            '';

            licenseFiles = pkgs.runCommand "check-license-files" { } ''
              grep -q "Apache License" ${./LICENSE}
              grep -qi "Ghidra" ${./NOTICE}
              grep -qi "Apache" ${./NOTICE}
              touch $out
            '';

            a11yIds = pkgs.runCommand "check-a11y-ids" {
              nativeBuildInputs = [
                pkgs.ripgrep
                pkgs.bash
                pkgs.coreutils
                pkgs.gnugrep
              ];
              src = srcRoot;
            } ''
              export PATH="${pkgs.ripgrep}/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:$PATH"
              export CHECK_A11Y_ROOT="$src"
              export CHECK_A11Y_OUTDIR="$TMPDIR"
              bash "$src/scripts/check-a11y-ids.sh"
              touch $out
            '';

            guiControlSchema = pkgs.runCommand "check-gui-control-schema" { } ''
              test -f ${./gui-tests/gui-control-schema.json}
              grep -q "/navigate" ${./gui-tests/gui-control-schema.json}
              grep -q "/dyld/open" ${./gui-tests/gui-control-schema.json}
              grep -q "/rag/discover" ${./gui-tests/gui-control-schema.json}
              touch $out
            '';

            jspaceRag = pkgs.runCommand "check-jspace-rag" {
              nativeBuildInputs = [ pkgs.ripgrep pkgs.bash pkgs.coreutils ];
            } ''
              export PATH="${pkgs.ripgrep}/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin:$PATH"
              export GHIDRA_VIBE_JSPACE_DB="$TMPDIR/jspace-check.sqlite"
              export GHIDRA_VIBE_JSPACE="${ghidraVibeTools}/bin/ghidra-vibe-jspace"
              export GHIDRA_VIBE_JSPACE_BIN="${ghidraVibeTools}/bin/ghidra-vibe-jspace"
              bash ${./gui-tests/smoke-jspace-rag.sh}
              test -f ${./docs/RAG.md}
              test -f ${./docs/SWIFT.md}
              test -x "${ghidraVibeTools}/bin/ghidra-vibe-dsc-index"
              test -x "${ghidraVibeTools}/bin/ghidra-vibe-rag-mcp"
              touch $out
            '';

            ghidraVibeGtkScaffold = pkgs.runCommand "check-gtk-scaffold" { } ''
              test -f ${./linux/GhidraVibe/README.md}
              test -f ${./linux/GhidraVibe/src/main.c}
              test -f ${./linux/GhidraVibe/meson.build}
              test -f ${./linux/GhidraVibe/src/dock.c}
              grep -q "ghidra.vibe.codebrowser" ${./linux/GhidraVibe/src/dock.c}
              test -f ${./native-ui/layout/CodeBrowser.tool.json}
              test -f ${./native-ui/a11y/catalog.json}
              test -f ${./native-ui/icons/AppIcon.icns}
              ! grep -q "Open AppKit from DSC" ${./macos/GhidraVibe/Sources/GhidraVibe/GhidraVibeApp.swift}
              ! grep -q "GHIDRA_VIBE_SWING" ${./nix/ghidra/default.nix}
              touch $out
            '';

            # Packaged runtime must not ship Swing FrontEnd launchers.
            ghidraVibeNoSwing = pkgs.runCommand "check-ghidra-vibe-no-swing" { } ''
              test ! -e ${ghidraVibe}/lib/ghidra/ghidraRun
              test ! -L ${ghidraVibe}/bin/ghidra
              test -f ${ghidraVibe}/bin/ghidra
              test ! -e ${ghidraVibe}/bin/ghidra-swing
              test ! -e ${ghidraVibe}/lib/ghidra/support/ghidraDebug
              # bin/ghidra must refuse (exit 2), not launch Swing
              if ${ghidraVibe}/bin/ghidra >/dev/null 2>&1; then
                echo "bin/ghidra unexpectedly succeeded" >&2
                exit 1
              fi
              test -x ${ghidraVibe}/share/ghidra-vibe/ghidra-vibe-analyzeHeadless
              touch $out
            '';
          }
          // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
            ghidraVibeBuild = pkgs.runCommand "check-ghidravibe-swift" { } ''
              # File presence gate for CI; full Swift build uses local Xcode (nix sandbox lacks SDK).
              test -f ${./macos/GhidraVibe/Package.swift}
              test -f ${./macos/GhidraVibe/Sources/GhidraVibe/GuiControlServer.swift}
              test -f ${./macos/GhidraVibe/Sources/GhidraVibe/AgentChatView.swift}
              test -f ${./macos/GhidraVibe/Sources/GhidraVibe/AppModel.swift}
              test -f ${./macos/GhidraVibe/Sources/GhidraVibe/CodeBrowserDockView.swift}
              test -f ${./macos/GhidraVibe/Sources/GhidraVibe/DockLayout.swift}
              test -f ${./macos/GhidraVibe/Sources/GhidraVibe/ProjectWindowView.swift}
              grep -q "ensureProgramEngineRunning" ${./macos/GhidraVibe/Sources/GhidraVibe/AppModel.swift}
              ! grep -q "GHIDRA_VIBE_SWING" ${./macos/GhidraVibe/Sources/GhidraVibe/AppModel.swift}
              grep -q "openDyldCache" ${./macos/GhidraVibe/Sources/GhidraVibe/AppModel.swift}
              grep -q "listDyldImages" ${./macos/GhidraVibe/Sources/GhidraVibe/AppModel.swift}
              grep -q "toolMode" ${./macos/GhidraVibe/Sources/GhidraVibe/AppModel.swift}
              test -f ${./ghidra_scripts/ImportDyldCacheImage.java}
              test -f ${./scripts/lib/dsc_index.py}
              test -f ${./macos/GhidraVibe/Resources/AppIcon.icns}
              touch $out
            '';
          };
        }
      )
    // {
      nixosModules.default = import ./nix/modules/nixos.nix;
      darwinModules.default = import ./nix/modules/darwin.nix;
      homeModules.default = import ./nix/modules/home-manager.nix;
    };
}
