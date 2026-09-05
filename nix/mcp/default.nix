{
  lib,
  stdenvNoCC,
  symlinkJoin,
  writeShellApplication,
  python3,
  uv,
  ghidraMcpExtension,
  ghidraVibeTools,
}:

# Local stdio MCP host binaries (mcp-nixos / wwn-mcp model).
# Cursor spawns these over stdio. No public URL. No manual :8092 daemon.
let
  share = stdenvNoCC.mkDerivation {
    pname = "ghidra-vibe-mcp-share";
    version = "1";

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/ghidra-mcp" "$out/share/ghidra-vibe/lib"
      if [[ -f ${ghidraMcpExtension}/share/ghidra-mcp/bridge_mcp_ghidra_stock.py ]]; then
        cp ${ghidraMcpExtension}/share/ghidra-mcp/bridge_mcp_ghidra_stock.py \
          "$out/share/ghidra-mcp/bridge_mcp_ghidra_stock.py"
      else
        cp ${ghidraMcpExtension}/share/ghidra-mcp/bridge_mcp_ghidra.py \
          "$out/share/ghidra-mcp/bridge_mcp_ghidra_stock.py"
      fi
      cp ${../../nix/share/bridge_mcp_ghidra.py} "$out/share/ghidra-mcp/bridge_mcp_ghidra.py"
      cp ${../../nix/share/bridge_mcp_vibe.py} "$out/share/ghidra-mcp/bridge_mcp_vibe.py"
      cp ${../../nix/share/bridge_mcp_gui.py} "$out/share/ghidra-mcp/bridge_mcp_gui.py"
      cp -a ${../../scripts/lib/vibe_mcp}/. "$out/share/ghidra-vibe/lib/vibe_mcp/"
      # Malimite + helpers used by vibe_mcp tool handlers
      mkdir -p "$out/share/ghidra-vibe/lib/malimite"
      cp -a ${../../scripts/lib/malimite}/. "$out/share/ghidra-vibe/lib/malimite/"
      cp ${../../scripts/lib/dsc_index.py} "$out/share/ghidra-vibe/lib/dsc_index.py"
      cp ${../../scripts/lib/macho_slice.py} "$out/share/ghidra-vibe/lib/macho_slice.py"
      cp ${../../scripts/lib/detect-maxmem.sh} "$out/share/ghidra-vibe/lib/detect-maxmem.sh"
      cp ${../../scripts/lib/detect-java.sh} "$out/share/ghidra-vibe/lib/detect-java.sh"
      cp ${../../scripts/lib/macho-native-slice.sh} "$out/share/ghidra-vibe/lib/macho-native-slice.sh"
      cp ${../../scripts/ghidra-vibe-analyzeHeadless} "$out/share/ghidra-vibe/ghidra-vibe-analyzeHeadless"
      cp ${../../scripts/ghidra-vibe-analysis-ensure} "$out/share/ghidra-vibe/ghidra-vibe-analysis-ensure"
      chmod +x "$out/share/ghidra-mcp/bridge_mcp_ghidra.py" \
        "$out/share/ghidra-mcp/bridge_mcp_vibe.py" \
        "$out/share/ghidra-mcp/bridge_mcp_gui.py" \
        "$out/share/ghidra-vibe/ghidra-vibe-analyzeHeadless" \
        "$out/share/ghidra-vibe/ghidra-vibe-analysis-ensure" \
        "$out/share/ghidra-vibe/lib/detect-java.sh" \
        "$out/share/ghidra-vibe/lib/macho-native-slice.sh"
      runHook postInstall
    '';
  };

  # Ghidra program engine bridge (FastMCP). Discovers local instances via UDS;
  # optional GHIDRA_MCP_URL only if you already started headless/GUI engine.
  ghidraMcp = writeShellApplication {
    name = "ghidra-mcp";
    runtimeInputs = [
      uv
      python3
    ];
    text = ''
      export GHIDRA_VIBE_ANALYSIS_ENSURE="''${GHIDRA_VIBE_ANALYSIS_ENSURE:-${share}/share/ghidra-vibe/ghidra-vibe-analysis-ensure}"
      if [[ "''${GHIDRA_VIBE_ANALYSIS_AUTOSTART:-1}" != "0" && -x "$GHIDRA_VIBE_ANALYSIS_ENSURE" ]]; then
        "$GHIDRA_VIBE_ANALYSIS_ENSURE" >/dev/null 2>&1 &
      fi
      exec uv run "${share}/share/ghidra-mcp/bridge_mcp_ghidra.py" "$@"
    '';
  };

  # Vibe tools (dyld / Malimite / rules / RAG helpers). Spawns mcp-ext on an
  # ephemeral localhost port, bridges stdio, tears down the child on exit.
  ghidraVibeMcp = writeShellApplication {
    name = "ghidra-vibe-mcp";
    runtimeInputs = [ python3 ];
    text = ''
      set -euo pipefail
      export PYTHONPATH="${share}/share/ghidra-vibe/lib''${PYTHONPATH:+:$PYTHONPATH}"
      export GHIDRA_VIBE_JSPACE="''${GHIDRA_VIBE_JSPACE:-${ghidraVibeTools}/bin/ghidra-vibe-jspace}"
      export GHIDRA_VIBE_DSC_INDEX="''${GHIDRA_VIBE_DSC_INDEX:-${ghidraVibeTools}/bin/ghidra-vibe-dsc-index}"
      export GHIDRA_VIBE_LIB="''${GHIDRA_VIBE_LIB:-${share}/share/ghidra-vibe/lib}"
      export GHIDRA_VIBE_HEADLESS="''${GHIDRA_VIBE_HEADLESS:-${share}/share/ghidra-vibe/ghidra-vibe-analyzeHeadless}"
      export GHIDRA_VIBE_ANALYSIS_ENSURE="''${GHIDRA_VIBE_ANALYSIS_ENSURE:-${share}/share/ghidra-vibe/ghidra-vibe-analysis-ensure}"
      if [[ "''${GHIDRA_VIBE_ANALYSIS_AUTOSTART:-1}" != "0" && -x "$GHIDRA_VIBE_ANALYSIS_ENSURE" ]]; then
        "$GHIDRA_VIBE_ANALYSIS_ENSURE" >/dev/null 2>&1 &
      fi

      if [[ -n "''${GHIDRA_VIBE_MCP_EXT_URL:-}" ]]; then
        exec python3 "${share}/share/ghidra-mcp/bridge_mcp_vibe.py" "$@"
      fi

      port="$(
        python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
      )"
      python3 -m vibe_mcp --host 127.0.0.1 --port "$port" &
      ext_pid=$!
      cleanup() {
        kill "$ext_pid" 2>/dev/null || true
        wait "$ext_pid" 2>/dev/null || true
      }
      trap cleanup EXIT INT TERM

      python3 -c "
      import time, urllib.request, sys
      url = 'http://127.0.0.1:' + sys.argv[1] + '/mcp/schema'
      for _ in range(100):
          try:
              urllib.request.urlopen(url, timeout=0.25)
              raise SystemExit(0)
          except Exception:
              time.sleep(0.05)
      raise SystemExit('ghidra-vibe-mcp: mcp-ext failed to start on port ' + sys.argv[1])
      " "$port"

      export GHIDRA_VIBE_MCP_EXT_URL="http://127.0.0.1:$port"
      python3 "${share}/share/ghidra-mcp/bridge_mcp_vibe.py" "$@"
    '';
  };

  ghidraVibeRagMcp = writeShellApplication {
    name = "ghidra-vibe-rag-mcp";
    text = ''
      exec ${ghidraVibeTools}/bin/ghidra-vibe-rag-mcp "$@"
    '';
  };

  # Optional: run the HTTP ext alone (manual / debugging). Not required for Cursor.
  ghidraVibeMcpExt = writeShellApplication {
    name = "ghidra-vibe-mcp-ext";
    runtimeInputs = [ python3 ];
    text = ''
      export PYTHONPATH="${share}/share/ghidra-vibe/lib''${PYTHONPATH:+:$PYTHONPATH}"
      export GHIDRA_VIBE_JSPACE="''${GHIDRA_VIBE_JSPACE:-${ghidraVibeTools}/bin/ghidra-vibe-jspace}"
      export GHIDRA_VIBE_DSC_INDEX="''${GHIDRA_VIBE_DSC_INDEX:-${ghidraVibeTools}/bin/ghidra-vibe-dsc-index}"
      export GHIDRA_VIBE_LIB="''${GHIDRA_VIBE_LIB:-${share}/share/ghidra-vibe/lib}"
      export GHIDRA_VIBE_HEADLESS="''${GHIDRA_VIBE_HEADLESS:-${share}/share/ghidra-vibe/ghidra-vibe-analyzeHeadless}"
      exec python3 -m vibe_mcp "$@"
    '';
  };
in
symlinkJoin {
  name = "ghidra-vibe-mcp";
  paths = [
    share
    ghidraMcp
    ghidraVibeMcp
    ghidraVibeRagMcp
    ghidraVibeMcpExt
  ];
  meta = with lib; {
    description = "GhidraVibe local stdio MCP servers (ghidra / vibe / rag)";
    homepage = "https://github.com/aspauldingcode/GhidraVibe";
    license = licenses.asl20;
    platforms = platforms.unix;
    mainProgram = "ghidra-vibe-mcp";
  };
}
