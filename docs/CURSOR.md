# Cursor / IDE MCP

Cursor MCP is **optional**. GhidraVibe runs without it. Wire the same bins into
Claude Desktop, Continue, or any MCP client the same way.

**Host model matches [mcp-nixos](https://github.com/utensils/mcp-nixos) /
[wwn-mcp](https://github.com/Wawona/wwn-mcp):** spawn a local nix PATH binary
over **stdio**. No public URL. `ghidra-vibe-mcp` auto-starts mcp-ext on an
ephemeral localhost port (no manual `:8092`).

## Recommended: `#ghidra-vibe-mcp`

```bash
nix profile install .#ghidra-vibe-mcp
# or: programs.ghidra-vibe.enable = true; (home-manager)
```

```json
{
  "mcpServers": {
    "ghidra": { "command": "ghidra-mcp", "args": [] },
    "ghidra-vibe": { "command": "ghidra-vibe-mcp", "args": [] },
    "ghidra-vibe-rag": { "command": "ghidra-vibe-rag-mcp", "args": [] }
  }
}
```

| Binary | Role |
|---|---|
| `ghidra-mcp` | Engine tools (UDS discovery; optional `GHIDRA_MCP_URL` if headless already up) |
| `ghidra-vibe-mcp` | dyld / Malimite / rules / nav (spawns mcp-ext, tears down on exit) |
| `ghidra-vibe-rag-mcp` | JSpace RAG discover/search/index |

Home Manager writes the same shape to `~/.config/ghidra-vibe/cursor-mcp.json`.

## Analysis HTTP stays up

`ghidra-vibe-analysis-ensure` starts the program-engine API (`:8089`) if it
is down, and home-manager `mcp.keepAnalysisAlive` (default) installs a
LaunchAgent with KeepAlive. MCP `vibe_health` / decompile call the same
ensure. You should not have to start headless by hand.

| Service | Env | Default |
|---|---|---|
| Program engine | `GHIDRA_MCP_URL` | `http://127.0.0.1:8089` |
| GuiControl | `GHIDRA_VIBE_GUI_URL` | `http://127.0.0.1:8091` |

- **Prebuilt:** [Releases](https://github.com/aspauldingcode/GhidraVibe/releases) DMG
- **Nix GUI:** `nix run github:aspauldingcode/GhidraVibe`
- **Headless:** `ghidra-vibe-mcp-headless --project /path/to/Proj.gpr`

## Legacy: raw bridges + fixed ports

Still works if you prefer manual daemons:

```bash
nix build .#ghidra-vibe
BRIDGES="$(readlink -f result)/share/ghidra-mcp"
ghidra-vibe-mcp-ext   # :8092
```

```json
{
  "mcpServers": {
    "ghidra": {
      "command": "uv",
      "args": ["run", "/ABS/PATH/TO/result/share/ghidra-mcp/bridge_mcp_ghidra.py"],
      "env": { "GHIDRA_MCP_URL": "http://127.0.0.1:8089" }
    },
    "ghidra-vibe": {
      "command": "python3",
      "args": ["/ABS/PATH/TO/result/share/ghidra-mcp/bridge_mcp_vibe.py"],
      "env": { "GHIDRA_VIBE_MCP_EXT_URL": "http://127.0.0.1:8092" }
    }
  }
}
```

## Tips

- Prefer `rag_discover` before deep RE questions; `dyld_import_image` +
  `decompile_function` for Apple frameworks.
- Tool map: [native-ui/mcp/tool-map.json](../native-ui/mcp/tool-map.json).
- Usability check: `./gui-tests/cursor-mcp-usability.sh`.
