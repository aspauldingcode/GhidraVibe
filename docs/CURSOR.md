# Cursor MCP

Cursor MCP is **optional** — GhidraVibe runs without it. For IDE agents:

1. Start the local program engine HTTP (default `http://127.0.0.1:8089`):
   - **`nix run`** — native UI auto-starts the engine.
   - **Headless:** `ghidra-vibe-mcp-headless --project /path/to/Proj.gpr` then `GET /open_program?program=/Program`.
   - Stock Swing UI is **not shipped**.
2. Engine URL: `GHIDRA_MCP_URL` (default `http://127.0.0.1:8089`).
3. GUI control: `GHIDRA_VIBE_GUI_URL` (default `http://127.0.0.1:8091`) — starts with the native shell.
4. Optional Python stdio bridge: `GHIDRA_VIBE_CURSOR_BRIDGE=1`.

```json
{
  "mcpServers": {
    "ghidra": {
      "command": "python3",
      "args": ["/ABS/PATH/TO/result/share/ghidra-mcp/bridge_mcp_ghidra.py"],
      "env": { "GHIDRA_MCP_URL": "http://127.0.0.1:8089" }
    },
    "ghidra-vibe-gui": {
      "command": "python3",
      "args": ["/ABS/PATH/TO/result/share/ghidra-mcp/bridge_mcp_gui.py"],
      "env": { "GHIDRA_VIBE_GUI_URL": "http://127.0.0.1:8091" }
    },
    "ghidra-vibe-rag": {
      "command": "python3",
      "args": ["/ABS/PATH/TO/result/share/ghidra-mcp/bridge_mcp_rag.py"],
      "env": {
        "GHIDRA_MCP_URL": "http://127.0.0.1:8089",
        "GHIDRA_VIBE_JSPACE_LIB": "/ABS/PATH/TO/result/share/ghidra-vibe/lib"
      }
    },
    "ghidra-vibe": {
      "command": "python3",
      "args": ["/ABS/PATH/TO/result/share/ghidra-mcp/bridge_mcp_vibe.py"],
      "env": {
        "GHIDRA_MCP_URL": "http://127.0.0.1:8089",
        "GHIDRA_VIBE_MCP_EXT_URL": "http://127.0.0.1:8092"
      }
    }
  }
}
```

Start vibe tools: `ghidra-vibe-mcp-ext` (Malimite, dyld, rules, RAG helpers, nav).
Use `rag_discover` before deep RE questions; `dyld_import_image` + `decompile_function` for Apple frameworks.
Home-manager writes a snippet to `~/.config/ghidra-vibe/cursor-mcp.json` when enabled.
Tool map: [native-ui/mcp/tool-map.json](../native-ui/mcp/tool-map.json).

Usability check: `./gui-tests/cursor-mcp-usability.sh`
