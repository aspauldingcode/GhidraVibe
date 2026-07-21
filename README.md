# GhidraVibe

Ghidra built from source with a **native GUI** (SwiftUI on macOS, GTK on Linux) instead of Swing, plus first-class **MCP**, **Agents**, and **dyld shared cache** extraction / analysis.

<p align="center">
  <img src="media/preview.png" alt="GhidraVibe preview" width="100%" />
</p>

## What you get

| Capability | First-class? | Notes |
|---|---|---|
| **MCP** | Yes | Drive the same program engine + native UI from Cursor / Claude / any MCP client |
| **Agents** | Yes | In-app Agent sidebar (Ollama, llama.cpp, OpenAI, Anthropic, Gemini, OpenAI-compat); no weights shipped |
| **dyld shared cache** | Yes | IDA-like open / index / import of macOS & iOS frameworks from the DSC |
| Full Ghidra engine | Yes | From-source build: projects, decompiler, analyzers, scripts |

MCP is optional control, not a requirement to reverse engineer. Details: [docs/CURSOR.md](docs/CURSOR.md) · [docs/AGENT_CHAT.md](docs/AGENT_CHAT.md) · [docs/DYLD.md](docs/DYLD.md).

## Quick Start: run the app

**Nix is not required.** Grab a prebuilt macOS build, or use Nix if you prefer.

### Option A: Prebuilt (no Nix)

1. Download the latest **Beta** / release DMG from [Releases](https://github.com/aspauldingcode/GhidraVibe/releases).
2. Open **GhidraVibe.app**. The analysis engine and GuiControl start with the UI.

### Option B: Nix

```bash
nix run github:aspauldingcode/GhidraVibe
```

From a checkout: `nix run`. On macOS, Xcode / CLT is needed for the Swift UI package.

Useful variants:

```bash
nix run .#ghidra-vibe          # product / engine tree
nix develop                    # shell with tooling on PATH
```

---

## Wire MCP into Cursor (or any agent)

Leave **GhidraVibe running**. Defaults:

| Service | URL |
|---|---|
| Program engine (GhidraMCP) | `http://127.0.0.1:8089` |
| GuiControl (native UI) | `http://127.0.0.1:8091` |
| Vibe tools (dyld, Malimite, RAG helpers) | `http://127.0.0.1:8092` |

Resolve bridge scripts once (absolute paths), then point your MCP client at them.

```bash
# From a flake checkout; builds the product tree with bridges:
nix build github:aspauldingcode/GhidraVibe
BRIDGES="$(readlink -f result)/share/ghidra-mcp"
ls "$BRIDGES"
# bridge_mcp_ghidra.py  bridge_mcp_gui.py  bridge_mcp_vibe.py  …
```

Or after a local `nix build .#ghidra-vibe`, use `./result/share/ghidra-mcp/`.

### Option 1: uv / uvx (Recommended)

**You don’t need Nix in the MCP client**; only Python tooling ([uv](https://github.com/astral-sh/uv)). The engine bridge is a [PEP 723](https://peps.python.org/pep-0723/) script (`mcp` dependency declared in-file). Gui / vibe bridges are stdlib-only.

Add to Cursor MCP config (`~/.cursor/mcp.json` or **Cursor Settings → MCP**):

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

Equivalent one-shot smoke tests:

```bash
# Engine bridge (pulls mcp via script metadata)
uv run "$BRIDGES/bridge_mcp_ghidra.py"

# Or uvx with an explicit dep (same idea as mcp-nixos’s uvx flow):
uvx --with 'mcp>=1.2.0,<2' python "$BRIDGES/bridge_mcp_ghidra.py"
```

Your agent can now decompile, navigate, drive the native UI, and hit dyld / Apple helpers through MCP.

### Option 2: Nix (run bridges from the flake)

```json
{
  "mcpServers": {
    "ghidra": {
      "command": "nix",
      "args": [
        "shell", "github:aspauldingcode/GhidraVibe#ghidra-vibe", "-c",
        "python3",
        "/replace-with-store-or-result/share/ghidra-mcp/bridge_mcp_ghidra.py"
      ],
      "env": { "GHIDRA_MCP_URL": "http://127.0.0.1:8089" }
    }
  }
}
```

Prefer resolving a stable `result/` symlink (Option 1) over embedding raw `/nix/store/…` paths in your editor config.

### Option 3: Home Manager / nix-darwin (declarative snippet)

```nix
# flake input
ghidra-vibe.url = "github:aspauldingcode/GhidraVibe";

# home.nix / darwin module
programs.ghidra-vibe = {
  enable = true;
  package = inputs.ghidra-vibe.packages.${pkgs.system}.ghidra-vibe;
};
```

That writes `~/.config/ghidra-vibe/cursor-mcp.json` with the bridge paths filled in; merge into Cursor’s MCP config or symlink. See [nix/modules/home-manager.nix](nix/modules/home-manager.nix).

### Option 4: plain `python3`

If `mcp` is already on `PYTHONPATH` (engine bridge only):

```json
{
  "mcpServers": {
    "ghidra": {
      "command": "python3",
      "args": ["/ABS/PATH/TO/result/share/ghidra-mcp/bridge_mcp_ghidra.py"],
      "env": { "GHIDRA_MCP_URL": "http://127.0.0.1:8089" }
    }
  }
}
```

Full tool map: [native-ui/mcp/tool-map.json](native-ui/mcp/tool-map.json) · usability: `./gui-tests/cursor-mcp-usability.sh`.

---

## Agents (in-app)

Open the **Agent** sidebar (trailing column). Configure Ollama / llama.cpp / cloud providers in **Agent Setup**. GhidraVibe never ships LLM weights. Mentions (`@Functions:…`, `@Program`, …), tool permissions, and MoE routing: [docs/AGENT_CHAT.md](docs/AGENT_CHAT.md).

## dyld shared cache

**File → Open Framework from Shared Cache…** (`⌘⇧O`): search AppKit / SwiftUI / … → open into CodeBrowser with Listing, Decompile, Graph, Classes.

Same engine over MCP/CLI: `dyld_find_cache`, `dyld_list_images`, `dyld_import_image`. Full workflow: [docs/DYLD.md](docs/DYLD.md).

## macOS package (local)

```bash
./macos/GhidraVibe/scripts/package-app.sh          # .app
./macos/GhidraVibe/scripts/package-dmg.sh          # .dmg → dist/
```

CI publishes a rolling **Beta** on every push to `master`, and a versioned release for tags `v*`. Metadata is mirrored on the `releases` branch.

## Docs

- MCP / Cursor: [docs/CURSOR.md](docs/CURSOR.md)
- Agents: [docs/AGENT_CHAT.md](docs/AGENT_CHAT.md)
- Apple RE: [docs/DYLD.md](docs/DYLD.md) · [docs/APPLE.md](docs/APPLE.md)
- Product: [docs/PRODUCT.md](docs/PRODUCT.md)

Apache-2.0. [LICENSE](LICENSE). Not endorsed by the NSA.
