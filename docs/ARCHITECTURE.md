# Architecture

**GhidraVibe is Ghidra** — the full program engine built **from source**, with a
**native GUI** (not a remote controller of `ghidra-bin` / Swing). Users use it
as normal Ghidra. MCP, agents, dyld-DSC, and Malimite-style Apple RE are
first-class additions, not the product identity.

See [PRODUCT.md](PRODUCT.md).

| Layer | Role |
|-------|------|
| **Ghidra engine** | Entire from-source tree (analyzers, loaders, decompiler, processors, Features, …) via nixpkgs Gradle `pkgs.ghidra` — **never** `ghidra-bin` |
| **Product GUI** | SwiftUI / GTK CodeBrowser + Project Window — 1:1 stock surface, modular docking |
| **Optional control** | Localhost engine API + Cursor/IDE MCP when the user wants agents |
| **Vibe additions** | dyld shared cache (IDA-like), Apple/Malimite, Agent/RAG/Rules |

```
nix run
  → build/wrap full Ghidra from source (ghidra-vibe)
  → launch native GhidraVibe GUI
  → embed JVM in-process (GhidraMCPHeadlessServer in GUI process)
  → bin/ghidra refuses Swing (Swing UI not shipped)

True headless (agents / batch): ghidra-vibe-mcp-headless / analyzeHeadless
  → separate JVM only (GHIDRA_VIBE_ENGINE=sidecar also uses this)
```

## From source

- Input: NSA Ghidra via nixpkgs `build.nix` (`fetchFromGitHub` + Gradle).
- Assertion: `ghidra.pname == "ghidra"` (rejects `ghidra-bin`).
- Packaging (`nix/ghidra/default.nix`) keeps the **full engine** (all Features /
  Processors / Debug modules for ClassSearcher and headless).
- Only **Swing UI entrypoints** are removed (`ghidraRun`, stock `Ghidra.app`,
  debug/pyghidra GUI launchers). Docking JARs stay for the engine classpath.

## Native GUI + optional MCP

| Concern | Required for daily RE? |
|---------|------------------------|
| Native GhidraVibe window | **Yes** — this is the GUI |
| In-process program engine | **Yes** — HotSpot embedded in the GUI process (`GHIDRA_VIBE_ENGINE=inprocess`) |
| True headless sidecar | **No** for GUI — CLI/agents via `ghidra-vibe-mcp-headless` |
| Cursor / Claude MCP bridges | **No** — `GHIDRA_VIBE_CURSOR_BRIDGE=1` if wanted |
| Vibe helpers (`:8092`) | For dyld / Malimite / RAG / nav extras |

| Port | Service |
|------|---------|
| `:8089` | Program engine API (in-process for GUI; sidecar when headless) |
| `:8091` | GuiControl — automate the native GUI |
| `:8092` | Vibe helpers (dyld, Malimite, RAG, rules) |
| `:8099` | Debugger MCP (optional) |

**Parity bar:** **1:1 stock Ghidra** features / functionality / UX in the native
UI — menus, toolbars, providers, Tool Chest tools (CodeBrowser, Debugger,
Emulator, Version Tracking), labels, hints, docking. See [STOCK_PARITY.md](STOCK_PARITY.md).
Temporary `disabled_honest` is tracking only (must be in `TRACKED_GAPS.json`);
stock controls must not be omitted or permanently stubbed.

Shared contracts: `native-ui/` (layout, menus, a11y, tool-map, STOCK_UNIVERSE).
