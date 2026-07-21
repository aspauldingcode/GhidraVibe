# Cursor / IDE MCP

Cursor MCP is **optional** — GhidraVibe runs without it. Wire the same bridges into Claude Desktop, Continue, or any MCP client the same way.

**Nix is not required in the client.** Prefer [uv](https://github.com/astral-sh/uv) (`uv run` / `uvx`) against the bridge scripts, matching the [mcp-nixos](https://github.com/utensils/mcp-nixos) install style.

## 1. Start GhidraVibe

- **Prebuilt:** [Releases](https://github.com/aspauldingcode/GhidraVibe/releases) DMG → open the app.
- **Nix:** `nix run github:aspauldingcode/GhidraVibe` (or `nix run` from a checkout).

Leave it running. Defaults:

| Service | Env | URL |
|---|---|---|
| Program engine | `GHIDRA_MCP_URL` | `http://127.0.0.1:8089` |
| GuiControl | `GHIDRA_VIBE_GUI_URL` | `http://127.0.0.1:8091` |
| Vibe tools (dyld, Malimite, …) | `GHIDRA_VIBE_MCP_EXT_URL` | `http://127.0.0.1:8092` |

Headless (no UI): `ghidra-vibe-mcp-headless --project /path/to/Proj.gpr` then open a program. Stock Swing UI is **not** shipped.

## 2. Locate bridge scripts

```bash
nix build github:aspauldingcode/GhidraVibe
BRIDGES="$(readlink -f result)/share/ghidra-mcp"
```

Local checkout: `nix build .#ghidra-vibe` → `./result/share/ghidra-mcp/`.

| Script | Role |
|---|---|
| `bridge_mcp_ghidra.py` | Engine tools (decompile, rename, …) — PEP 723 / needs `mcp` |
| `bridge_mcp_gui.py` | Native UI (GuiControl) — stdlib |
| `bridge_mcp_vibe.py` | dyld / Malimite / rules / nav — stdlib |
| `bridge_mcp_rag.py` | Compat shim → `ghidra-vibe-rag-mcp` |

## 3. Configure the client

### Option 1: uv (Recommended)

```json
{
  "mcpServers": {
    "ghidra": {
      "command": "uv",
      "args": ["run", "/ABS/PATH/TO/result/share/ghidra-mcp/bridge_mcp_ghidra.py"],
      "env": { "GHIDRA_MCP_URL": "http://127.0.0.1:8089" }
    },
    "ghidra-vibe-gui": {
      "command": "uv",
      "args": ["run", "/ABS/PATH/TO/result/share/ghidra-mcp/bridge_mcp_gui.py"],
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
      "command": "uv",
      "args": ["run", "/ABS/PATH/TO/result/share/ghidra-mcp/bridge_mcp_vibe.py"],
      "env": {
        "GHIDRA_MCP_URL": "http://127.0.0.1:8089",
        "GHIDRA_VIBE_MCP_EXT_URL": "http://127.0.0.1:8092"
      }
    }
  }
}
```

`uvx` equivalent for the engine bridge:

```bash
uvx --with 'mcp>=1.2.0,<2' python "$BRIDGES/bridge_mcp_ghidra.py"
```

### Option 2: Nix / Home Manager

Enable `programs.ghidra-vibe` — writes `~/.config/ghidra-vibe/cursor-mcp.json` with store paths filled in ([nix/modules/home-manager.nix](../nix/modules/home-manager.nix)).

### Option 3: `python3`

Works for gui/vibe bridges out of the box. For the engine bridge, install `mcp` (`pip install 'mcp>=1.2.0,<2'`) or use `uv run` as above.

## Tips

- Start vibe tools HTTP when needed: `ghidra-vibe-mcp-ext`.
- Prefer `rag_discover` before deep RE questions; `dyld_import_image` + `decompile_function` for Apple frameworks.
- Tool map: [native-ui/mcp/tool-map.json](../native-ui/mcp/tool-map.json).
- Usability check: `./gui-tests/cursor-mcp-usability.sh`.
