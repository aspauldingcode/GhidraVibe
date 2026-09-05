# Cursor MCP note (home-manager)

`~/.cursor/mcp.json` is a **home-manager symlink**. Do not `chmod` or
overwrite it in place.

Built bridges (this machine):

```text
/Users/8amps/GhidraVibe/result-ghidra-vibe-fresh/share/ghidra-mcp/
```

Replace the broken `GhidraMCP_Vibe_RSE` nix run entries with uv + absolute
bridges (see [CURSOR.md](CURSOR.md)), then `home-manager switch`.

## Headless JDK wall (2026-08-20, updated 2026-09-03)

Ghidra 12.1 + **HotSpot** 17/21/25 (Zulu and Temurin) SIGBUS (`BUS_ADRALN`)
in `CodeHeap::allocate` on this host, including `env -i` and `/tmp` copies.
MS OpenJDK 11 runs but is too old for Ghidra 12.

**Working JVM:** IBM Semeru / Eclipse OpenJ9 21. `flake.nix` selects
`pkgs.semeru-bin-21` on Darwin and **does not inherit** a shell `JAVA_HOME`
(Zulu/Temurin HotSpot SIGBUS even on `java -version`).

Keep analysis up with `ghidra-vibe-analysis-ensure` (MCP auto-starts it;
home-manager `mcp.keepAnalysisAlive` is a LaunchAgent with KeepAlive).
Do **not** use a profile wrapper that `nix shell` rebuilds the flake.

`vibe_health` is green when `analysis.ok` is true on `127.0.0.1:8089`.

Headless import is remapped: `import_file` → `POST /load_program` (fat
Mach-O is `lipo -thin` to arm64e/arm64 first), `open_program` →
`POST /load_program_from_project` when stock GET is GUI-only
(`PluginTool not available`). `ghidra-vibe-analyzeHeadless` also thins
`-import` arguments and probes Semeru via `scripts/lib/detect-java.sh`.

After `nix build .#ghidra-vibe-mcp`, point the `ghidra` bridge at
`result/share/ghidra-mcp/bridge_mcp_ghidra.py` (wrapper) plus sibling
`bridge_mcp_ghidra_stock.py`. Or keep using the repo vibe handlers via
`PYTHONPATH=$PWD/scripts/lib` without a Ghidra rebuild.

Suggested MCP fragment for home-manager:

```json
{
  "ghidra": {
    "command": "uv",
    "args": [
      "run",
      "/Users/8amps/GhidraVibe/result-ghidra-vibe-fresh/share/ghidra-mcp/bridge_mcp_ghidra.py"
    ],
    "env": {
      "GHIDRA_MCP_URL": "http://127.0.0.1:8089"
    }
  },
  "ghidra-vibe": {
    "command": "uv",
    "args": [
      "run",
      "/Users/8amps/GhidraVibe/result-ghidra-vibe-fresh/share/ghidra-mcp/bridge_mcp_vibe.py"
    ],
    "env": {
      "GHIDRA_MCP_URL": "http://127.0.0.1:8089",
      "GHIDRA_VIBE_MCP_EXT_URL": "http://127.0.0.1:8092",
      "PYTHONPATH": "/Users/8amps/GhidraVibe/scripts/lib",
      "GHIDRA_VIBE_HEADLESS": "/Users/8amps/GhidraVibe/scripts/ghidra-vibe-analyzeHeadless",
      "GHIDRA_VIBE_LIB": "/Users/8amps/GhidraVibe/scripts/lib"
    }
  },
  "ghidra-vibe-rag": {
    "command": "python3",
    "args": [
      "/Users/8amps/GhidraVibe/result-ghidra-vibe-fresh/share/ghidra-mcp/bridge_mcp_rag.py"
    ],
    "env": {
      "GHIDRA_MCP_URL": "http://127.0.0.1:8089",
      "GHIDRA_VIBE_JSPACE_LIB": "/Users/8amps/GhidraVibe/result-ghidra-vibe-fresh/share/ghidra-vibe/lib"
    }
  }
}
```
