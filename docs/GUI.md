# Native UI — GhidraVibe *is* Ghidra

GhidraVibe **is** full Ghidra with a native GUI (see [PRODUCT.md](PRODUCT.md)).
Project Window, CodeBrowser, docking, menus, providers — use it as normal Ghidra.
Engine is **built from source** and embedded **in-process** (HotSpot in the
GhidraVibe process). Nix removes Swing *launchers* only. True headless CLI
(`ghidra-vibe-mcp-headless`) is for agents/batch. **Cursor MCP is optional.**

| Platform | Product GUI |
| --- | --- |
| macOS 26+ | SwiftUI / AppKit + **Liquid Glass** (see [macos-liquid-glass.md](macos-liquid-glass.md)) |
| Linux | GTK4 + libadwaita (same layout contracts) |

Framework Docking/Gui JARs may remain on the **engine classpath** (ClassSearcher);
they are not a runnable Swing UI. See [ARCHITECTURE.md](ARCHITECTURE.md).

## Startup flow (native; not Swing)

1. **User Agreement** — SwiftUI `.alert` (not Java `UserAgreementDialog`)
2. **Splash** — dragon / version / “Creating front end tool…”
3. **Welcome / Ghidra Help** — two-pane help (first run, or Help → Ghidra Help…)
4. **Tip of the Day** — Help → Tip of the Day… (optional at startup)
5. **Workspace / project picker** — recent `.gpr` projects, New / Browse
6. **Project Window** — stock Front End chrome (`native-ui/parity/FrontEnd.chrome.json`):
   VC toolbar → Tool Chest (CodeBrowser / Debugger / Emulator / Version Tracking, A–Z) → Active Project
   (Tree/Table + Filter) → Running Tools + Workspace → LogPanel
7. **CodeBrowser** — stock dock + menus (`CodeBrowser.chrome.json` /
   `CodeBrowser.tool.json`): left trees, Listing, Decompile (+ Window tabs), Console

If you see a Java splash or Swing Project Window, you are not running the
packaged GhidraVibe runtime (`pkill -f ghidra.GhidraRun`). Product `bin/ghidra`
always exits — use `nix run` for the native GUI.

## Modular docking (SwiftUI ≡ stock DockingWindowManager)

CodeBrowser panes are **modular and re-attachable** (macOS SwiftUI):

| Action | How |
| --- | --- |
| Close | Provider title-bar ✕ (Window menu restores) |
| Redock | Drag title bar onto Left / Center / Right / Bottom / Console / Header, or context menu **Dock to…** |
| Float | Context menu **Float** → separate window; **Dock Back** reattaches to home region |
| Reset | Toolbar **More… → Reset Dock Layout** (stock defaults) |

Regions mirror stock `CodeBrowser.tool`: left dock is full height; Console sits under Listing/right only. Layout persists in `UserDefaults` (`ghidra.vibe.dock.layout.v1`).

Provider chrome is inventory-driven (`CodeBrowser.chrome.json` / `CodeBrowser.inventory.json`): same labels, hints, and local toolbars as stock. **1:1 stock parity** ([STOCK_PARITY.md](STOCK_PARITY.md)): temporary honest-disabled is tracking only (`TRACKED_GAPS.json`), never “requires MCP” or a permanent stub. Tool Chest tools (Debugger / Emulator / Version Tracking) have their own chrome contracts under `native-ui/parity/`.

## Layout ground truth

[`native-ui/layout/CodeBrowser.tool.json`](../native-ui/layout/CodeBrowser.tool.json) is
normalized from Ghidra’s shipped `defaultTools/CodeBrowser.tool`.

Default active panes: Program Trees, Symbol Tree, Data Type Manager, Listing, Decompile, Console.

**Function Graph** is a native CFG viewer (not a JSON dump): the in-process engine builds basic blocks + flow edges (`BasicBlockModel`); macOS draws them with an AppKit canvas (pan/zoom/click-to-navigate); Linux uses a GTK/Cairo drawing area. Refresh via Window → Function Graph or GuiControl `POST /refresh_function_graph`.

**Task Monitor (status bar):** when Auto Analyze, DSC import, decompile, or engine start is running, the bottom bar expands into a stock-like monitor — orange badge, spinner, full-width progress bar, elapsed time, and Cancel (for Auto Analyze). Idle state stays a thin caption strip.

## Vibe / Apple panels (Window menu)

MCP, Agent (trailing sidebar), RAG/JSpace, Rules, Code Editor,
**Shared Cache / Framework…** (File + toolbar + Tool Chest), **App Bundle** (File + toolbar + Tool Chest),
**Classes** (left dock ObjC/Swift).

Apple RE details: [APPLE.md](APPLE.md). Malimite-inspired IPA/resources/Swift namespaces — native UI, not Swing.

## UI ≡ program engine

Every Window provider and toolbar action is a **first-class Ghidra UI control**.
Controls talk to the local program engine (`:8089`) and vibe helpers (`:8092`)
so the native GUI owns the full surface without embedding Swing. That localhost
API is plumbing — not a Cursor/MCP product dependency.

Ground truth: [`native-ui/mcp/tool-map.json`](../native-ui/mcp/tool-map.json).

| Pane | MCP |
| --- | --- |
| Bookmarks / Memory Map / Bytes / Symbols / Xrefs | analysis `list_*` / `get_xrefs_*` / `read_memory` |
| Entropy / Equates / Relocs / Registers / Tags | vibe `vibe_list_*` |
| App Bundle / Classes | vibe `malimite_*` / `swift_*` (File → Open App Bundle…) |
| Shared Cache / Framework | vibe `dyld_*` (File → Open Framework from Shared Cache…) |
| RAG / Rules / Agent | vibe `rag_*` / `rules_*` / `rename_function` / `autonomous_re`; GuiControl `/agent/*` |
| Auto Analyze | analysis `run_analysis` |

GTK uses the same tool names (`vibe_provider_mcp` Refresh). Smokes: `gui-tests/smoke-providers-mcp.sh`, `smoke-malimite-mcp.sh`, `smoke-dyld-mcp.sh`, `smoke-rag-agent.sh`.

## Accessibility / agent-device

See [GUI_TESTING.md](GUI_TESTING.md). Catalog: [`native-ui/a11y/catalog.json`](../native-ui/a11y/catalog.json).

## Memory

`scripts/lib/detect-maxmem.sh` sets `-Xmx` (~45% RAM). Override with `GHIDRA_VIBE_MAXMEM`.
