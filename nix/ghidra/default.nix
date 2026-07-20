# GhidraVibe runtime = full Ghidra **from-source** (pkgs.ghidra / Gradle), not ghidra-bin.
#
# Product identity: this IS Ghidra — native GUI + optional MCP/agents + dyld/Malimite.
# We keep the entire program engine (Features, Processors, Decompiler, analyzers).
# We only remove *runnable Swing UI entrypoints* (GhidraRun / stock .app). Docking JARs
# remain on the classpath (ClassSearcher / headless); they are not the product GUI.
{
  lib,
  stdenvNoCC,
  ghidra,
  ghidraMcpExtension,
  ghidraVibeTools,
}:

assert lib.versionAtLeast ghidra.version "12.1.2";
# nixpkgs: pkgs.ghidra = Gradle from-source; pkgs.ghidra-bin = prebuilt PUBLIC zip.
assert lib.assertMsg (ghidra.pname == "ghidra")
  "ghidra-vibe requires pkgs.ghidra (from-source), not ${ghidra.pname}";

stdenvNoCC.mkDerivation {
  pname = "ghidra-vibe";
  version = "${ghidra.version}+native-${ghidraMcpExtension.version}";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;
  dontStrip = true;
  noAuditTmpdir = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -a "${ghidra}/." "$out/"
    chmod -R u+w "$out"

    EXT_DIR="$out/lib/ghidra/Ghidra/Extensions"
    mkdir -p "$EXT_DIR"
    cp -a "${ghidraMcpExtension}/share/ghidra-extensions/GhidraMCP" "$EXT_DIR/"

    mkdir -p "$out/share/ghidra-mcp" "$out/share/ghidra-vibe" "$out/share/ghidra-vibe/ghidra_scripts" \
      "$out/share/ghidra-vibe/lib" "$out/bin"
    cp -a "${ghidraMcpExtension}/share/ghidra-mcp/." "$out/share/ghidra-mcp/"
    chmod -R u+w "$out/share/ghidra-mcp" "$out/bin" "$out/share/ghidra-vibe"

    # GUI control bridge (HTTP) — kept for shell automation; RAG is Rust.
    cp ${../share/bridge_mcp_gui.py} "$out/share/ghidra-mcp/bridge_mcp_gui.py"
    cp ${../share/bridge_mcp_vibe.py} "$out/share/ghidra-mcp/bridge_mcp_vibe.py"
    cp ${../../ghidra_scripts}/*.java "$out/share/ghidra-vibe/ghidra_scripts/"
    # Copy package *contents* into fixed names (cp -a of a store path would keep the hash basename).
    mkdir -p "$out/share/ghidra-vibe/lib/malimite" "$out/share/ghidra-vibe/lib/vibe_mcp"
    cp -a ${../../scripts/lib/malimite}/. "$out/share/ghidra-vibe/lib/malimite/"
    cp -a ${../../scripts/lib/vibe_mcp}/. "$out/share/ghidra-vibe/lib/vibe_mcp/"
    cp ${../../scripts/lib/dsc_index.py} "$out/share/ghidra-vibe/lib/dsc_index.py"
    cp ${../../scripts/ghidra-vibe-dyld} "$out/share/ghidra-vibe/ghidra-vibe-dyld"
    cp ${../../scripts/ghidra-vibe-apple} "$out/share/ghidra-vibe/ghidra-vibe-apple"
    cp ${../../scripts/ghidra-vibe-mcp-ext} "$out/share/ghidra-vibe/ghidra-vibe-mcp-ext"
    cp ${../../scripts/ghidra-vibe-analyzeHeadless} "$out/share/ghidra-vibe/ghidra-vibe-analyzeHeadless"
    cp ${../../scripts/lib/detect-maxmem.sh} "$out/share/ghidra-vibe/lib/detect-maxmem.sh"
    cp ${../../scripts/ghidra-vibe-jspace} "$out/share/ghidra-vibe/ghidra-vibe-jspace"

    # Rust tools (JSpace + DSC index + RAG MCP)
    cp ${ghidraVibeTools}/bin/ghidra-vibe-jspace "$out/bin/ghidra-vibe-jspace"
    cp ${ghidraVibeTools}/bin/ghidra-vibe-dsc-index "$out/bin/ghidra-vibe-dsc-index"
    cp ${ghidraVibeTools}/bin/ghidra-vibe-rag-mcp "$out/bin/ghidra-vibe-rag-mcp"
    # Compat shim: old configs that still point at bridge_mcp_rag.py
    cat > "$out/share/ghidra-mcp/bridge_mcp_rag.py" <<EOF
#!/usr/bin/env bash
exec "$out/bin/ghidra-vibe-rag-mcp" "\$@"
EOF

    chmod u+w \
      "$out/share/ghidra-vibe/ghidra-vibe-dyld" \
      "$out/share/ghidra-vibe/ghidra-vibe-apple" \
      "$out/share/ghidra-vibe/ghidra-vibe-mcp-ext" \
      "$out/share/ghidra-vibe/ghidra-vibe-analyzeHeadless" \
      "$out/share/ghidra-vibe/ghidra-vibe-jspace" \
      "$out/share/ghidra-mcp/bridge_mcp_gui.py" \
      "$out/share/ghidra-mcp/bridge_mcp_vibe.py" \
      "$out/bin/ghidra-vibe-jspace" \
      "$out/bin/ghidra-vibe-dsc-index" \
      "$out/bin/ghidra-vibe-rag-mcp"
    chmod +x "$out/share/ghidra-vibe/ghidra-vibe-dyld" \
      "$out/share/ghidra-vibe/ghidra-vibe-apple" \
      "$out/share/ghidra-vibe/ghidra-vibe-mcp-ext" \
      "$out/share/ghidra-vibe/ghidra-vibe-analyzeHeadless" \
      "$out/share/ghidra-vibe/ghidra-vibe-jspace" \
      "$out/share/ghidra-mcp/bridge_mcp_gui.py" \
      "$out/share/ghidra-mcp/bridge_mcp_vibe.py" \
      "$out/bin/ghidra-vibe-jspace" \
      "$out/bin/ghidra-vibe-dsc-index" \
      "$out/bin/ghidra-vibe-rag-mcp"
    chmod +x "$out/share/ghidra-mcp/bridge_mcp_rag.py" 2>/dev/null || true

    cat > "$out/bin/ghidra-vibe-mcp-ext" <<EOF
#!/usr/bin/env bash
export PYTHONPATH="\''${PYTHONPATH:+\$PYTHONPATH:}$out/share/ghidra-vibe/lib"
export GHIDRA_VIBE_DYLD="\''${GHIDRA_VIBE_DYLD:-$out/bin/ghidra-vibe-dyld}"
export GHIDRA_VIBE_JSPACE="\''${GHIDRA_VIBE_JSPACE:-$out/bin/ghidra-vibe-jspace}"
export GHIDRA_VIBE_SCRIPT_PATH="\''${GHIDRA_VIBE_SCRIPT_PATH:-$out/share/ghidra-vibe/ghidra_scripts}"
exec "$out/share/ghidra-vibe/ghidra-vibe-mcp-ext" "\$@"
EOF
    cat > "$out/bin/ghidra-vibe-apple" <<EOF
#!/usr/bin/env bash
export PYTHONPATH="\''${PYTHONPATH:+\$PYTHONPATH:}$out/share/ghidra-vibe/lib"
export GHIDRA_VIBE_SCRIPT_PATH="\''${GHIDRA_VIBE_SCRIPT_PATH:-$out/share/ghidra-vibe/ghidra_scripts}"
export GHIDRA_VIBE_HEADLESS="\''${GHIDRA_VIBE_HEADLESS:-$out/share/ghidra-vibe/ghidra-vibe-analyzeHeadless}"
exec "$out/share/ghidra-vibe/ghidra-vibe-apple" "\$@"
EOF
    chmod +x "$out/bin/ghidra-vibe-mcp-ext" "$out/bin/ghidra-vibe-apple"

    # --- Full engine kept; strip only Swing UI entrypoints + fat docs ---
    find "$out/lib/ghidra" \( -name '*.html' -o -name '*.htm' -o -name '*.pdf' \) \
      ! -path '*/Extensions/GhidraMCP/*' -type f -delete 2>/dev/null || true
    rm -rf \
      "$out/lib/ghidra/docs/GhidraAPI_javadoc" \
      "$out/lib/ghidra/docs/GhidraAPI_javadoc.zip" \
      "$out/lib/ghidra/docs/ghidra_stubs" \
      "$out/lib/ghidra/docs/GhidraClass" \
      "$out/lib/ghidra/docs/ChangeHistory.html" \
      "$out/lib/ghidra/docker" \
      2>/dev/null || true
    find "$out/lib/ghidra" -name '*-src.zip' -type f -delete 2>/dev/null || true
    rm -f "$out/lib/ghidra/support/buildGhidraJar" "$out/lib/ghidra/support/buildGhidraJar.bat" \
      "$out/bin/ghidra-buildGhidraJar" 2>/dev/null || true

    # Keep all Features/ + Debug/ + Processors — this is full Ghidra.
    # Delete every Swing FrontEnd / CodeBrowser *launcher* only.
    # Important: remove bin/ghidra *symlink* before writing a stub — otherwise
    # `cat > bin/ghidra` writes through the link and recreates ghidraRun.
    rm -f \
      "$out/bin/ghidra" \
      "$out/bin/ghidra-swing" \
      "$out/bin/ghidra-ghidraDebug" \
      "$out/bin/ghidra-pyghidraRun" \
      "$out/bin/ghidra-GhidraGo" \
      "$out/bin/ghidra-jshellRun" \
      "$out/bin/GhidraGo" \
      "$out/lib/ghidra/ghidraRun" \
      "$out/lib/ghidra/ghidraRun.bat" \
      "$out/lib/ghidra/support/ghidraDebug" \
      "$out/lib/ghidra/support/ghidraDebug.bat" \
      "$out/lib/ghidra/support/pyghidraRun" \
      "$out/lib/ghidra/support/pyghidraRun.bat" \
      "$out/lib/ghidra/support/GhidraGo" \
      "$out/lib/ghidra/support/jshellRun" \
      "$out/lib/ghidra/support/jshellRun.bat" \
      2>/dev/null || true
    # Stock macOS .app / defaultTools are Swing-only — product GUI is GhidraVibe.app.
    rm -rf \
      "$out/Applications/Ghidra.app" \
      "$out/lib/ghidra/Ghidra/Configurations/Public_Release/defaultTools" \
      2>/dev/null || true
    # Any remaining symlink into ghidraRun (nixpkgs layout variants).
    find "$out" -type l \( -lname '*ghidraRun*' -o -lname '*/ghidraRun' \) -delete 2>/dev/null || true

    # Refuse stub — must be a regular file, never a symlink to ghidraRun.
    mkdir -p "$out/bin"
    cat > "$out/bin/ghidra" <<EOF
#!/usr/bin/env bash
echo "GhidraVibe: stock Swing UI is not shipped." >&2
echo "  GUI:      nix run  (native GhidraVibe)" >&2
echo "  Headless: ghidra-analyzeHeadless / ghidra-vibe-dyld" >&2
exit 2
EOF
    chmod +x "$out/bin/ghidra"
    # Guard: install must not leave a Swing launcher.
    if [[ -e "$out/lib/ghidra/ghidraRun" ]] || [[ -L "$out/bin/ghidra" ]]; then
      echo "FATAL: Swing launcher still present after strip" >&2
      ls -la "$out/bin/ghidra" "$out/lib/ghidra/ghidraRun" 2>&1 || true
      exit 1
    fi

    # Headless-first launch wrappers (Nix indented-string escape for bash ''${...}).
    cat > "$out/bin/ghidra-vibe-dyld" <<EOF
#!/usr/bin/env bash
export GHIDRA_INSTALL_DIR="\''${GHIDRA_INSTALL_DIR:-$out/lib/ghidra}"
export GHIDRA_VIBE_DSC_INDEX="\''${GHIDRA_VIBE_DSC_INDEX:-$out/bin/ghidra-vibe-dsc-index}"
export GHIDRA_VIBE_SCRIPT_PATH="\''${GHIDRA_VIBE_SCRIPT_PATH:-$out/share/ghidra-vibe/ghidra_scripts}"
export GHIDRA_VIBE_HEADLESS="\''${GHIDRA_VIBE_HEADLESS:-$out/share/ghidra-vibe/ghidra-vibe-analyzeHeadless}"
export GHIDRA_VIBE_APPLE_SYMBOLS="\''${GHIDRA_VIBE_APPLE_SYMBOLS:-1}"
exec "$out/share/ghidra-vibe/ghidra-vibe-dyld" "\$@"
EOF
    cat > "$out/bin/ghidra-vibe-jspace-wrap" <<EOF
#!/usr/bin/env bash
export GHIDRA_VIBE_JSPACE_BIN="\''${GHIDRA_VIBE_JSPACE_BIN:-$out/bin/ghidra-vibe-jspace}"
exec "$out/bin/ghidra-vibe-jspace" "\$@"
EOF
    # Packaged headless launcher (detect-maxmem + RAM-aware -Xmx)
    chmod u+w "$out/share/ghidra-vibe/ghidra-vibe-analyzeHeadless"
    cat > "$out/share/ghidra-vibe/ghidra-vibe-analyzeHeadless" <<'AHEOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/detect-maxmem.sh"
MEM="$(detect_ghidra_maxmem)"
VMARG_LIST="''${GHIDRA_VIBE_VMARGS:--XX:ParallelGCThreads=2 -XX:CICompilerCount=2 -Djava.awt.headless=true -Dghidra.vibe.nativeUi=1 }"
if [[ -n "''${GHIDRA_INSTALL_DIR:-}" && -x "''${GHIDRA_INSTALL_DIR}/support/launch.sh" ]]; then
  SUPPORT="''${GHIDRA_INSTALL_DIR}/support"
else
  echo "Set GHIDRA_INSTALL_DIR" >&2
  exit 1
fi
echo "ghidra-vibe-analyzeHeadless MAXMEM=$MEM support=$SUPPORT" >&2
exec "$SUPPORT/launch.sh" fg jdk Ghidra-Headless "$MEM" "$VMARG_LIST" \
  ghidra.app.util.headless.AnalyzeHeadless "$@"
AHEOF
    chmod +x "$out/bin/ghidra-vibe-dyld" "$out/share/ghidra-vibe/ghidra-vibe-analyzeHeadless"

    cat > "$out/share/ghidra-vibe/runtime.env" <<EOF
GHIDRA_INSTALL_DIR=$out/lib/ghidra
GHIDRA_VERSION=${ghidra.version}
GHIDRA_MCP_BRIDGE=$out/share/ghidra-mcp/bridge_mcp_ghidra.py
GHIDRA_VIBE_GUI_BRIDGE=$out/share/ghidra-mcp/bridge_mcp_gui.py
GHIDRA_VIBE_BRIDGE=$out/share/ghidra-mcp/bridge_mcp_vibe.py
GHIDRA_VIBE_RAG_MCP=$out/bin/ghidra-vibe-rag-mcp
GHIDRA_MCP_EXTENSION=$EXT_DIR/GhidraMCP
GHIDRA_VIBE_DYLD=$out/bin/ghidra-vibe-dyld
GHIDRA_VIBE_APPLE=$out/bin/ghidra-vibe-apple
GHIDRA_VIBE_MCP_EXT=$out/bin/ghidra-vibe-mcp-ext
GHIDRA_VIBE_MCP_EXT_URL=http://127.0.0.1:8092
GHIDRA_VIBE_JSPACE=$out/bin/ghidra-vibe-jspace
GHIDRA_VIBE_DSC_INDEX=$out/bin/ghidra-vibe-dsc-index
GHIDRA_VIBE_SCRIPT_PATH=$out/share/ghidra-vibe/ghidra_scripts
GHIDRA_VIBE_APPLE_SYMBOLS=1
GHIDRA_VIBE_NATIVE_UI=1
EOF
    runHook postInstall
  '';

  meta = with lib; {
    description = "Full Ghidra ${ghidra.version} from-source — native GUI (GhidraVibe), Swing launchers removed";
    homepage = "https://github.com/NationalSecurityAgency/Ghidra";
    license = licenses.asl20;
    platforms = ghidra.meta.platforms or platforms.unix;
    mainProgram = "ghidra-vibe-dyld";
  };
}
