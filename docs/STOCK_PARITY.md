# Stock Ghidra 1:1 parity

**GhidraVibe must have 1:1 features, functionality, and UX with stock Ghidra.**
No stock feature may be permanently omitted or left as a dead stub.

The engine is already full from-source Ghidra. The native GUI (SwiftUI / GTK)
replaces Swing — it must not ship a reduced feature set.

Vibe-only surfaces (Agent, RAG/JSpace, DSC, Apple/Malimite, Cursor bridges) are
**additive**. They do not replace or excuse missing stock.

## Mapping rules

| Stock | GhidraVibe |
|-------|------------|
| Swing Project Window | Native Project Window (`FrontEnd.chrome.json`) |
| Swing CodeBrowser | Native CodeBrowser dock + menus |
| Debugger / Emulator / Version Tracking tools | Native Tool Chest tools (same providers) |
| Program engine (analyzers, loaders, decompiler, processors) | In-process HotSpot (`GHIDRA_VIBE_ENGINE=inprocess`) |
| Swing chrome labels / a11y | `native-ui/a11y/catalog.json` + platform IDs |

## Parity tiers

| Tier | Meaning | Stock end-state |
|------|---------|-----------------|
| **M1 Visible** | Control in chrome/menus/catalog with stock label | Required for every stock control |
| **M2 UI-wired** | Opens tool/provider/dialog; real navigation | Required for pure-UI stock actions |
| **M3 Engine-wired** | Mutates/queries the open program via engine API | Required for program-mutating stock actions |

**Forbidden for stock:** omitted control, fake success, “requires MCP”, permanent `disabled_honest`.

Temporary `disabled_honest` / `depth: shell|partial` is tracking while wiring M2/M3.
Every such item must appear in [`TRACKED_GAPS.json`](../native-ui/parity/TRACKED_GAPS.json)
(CI-enforced via `scripts/sync-tracked-gaps.py`). Stock-depth proven controls are
listed in [`STOCK_DEPTH_ALLOWLIST.json`](../native-ui/parity/STOCK_DEPTH_ALLOWLIST.json)
— only those may be `wired` / `depth: stock`. Tool-map aliases that fake M3
(`list_functions` for BSim, etc.) are forbidden.

## Ground truth

1. [`native-ui/parity/STOCK_UNIVERSE.json`](../native-ui/parity/STOCK_UNIVERSE.json) —
   extracted from `GHIDRA_INSTALL_DIR` default tools + modules  
   (`scripts/extract-stock-universe.py`)
2. Per-tool chrome: `CodeBrowser.chrome.json`, `FrontEnd.chrome.json`,
   `Debugger.chrome.json`, `Emulator.chrome.json`, `VersionTracking.chrome.json`
3. Per-tool inventories: `*.inventory.json` (tiers `m1` / `m2_ui` / `m3_engine`)
4. Engine action map: [`native-ui/mcp/tool-map.json`](../native-ui/mcp/tool-map.json)

Regenerate universe after Ghidra upgrades:

```bash
export GHIDRA_INSTALL_DIR=$(nix build .#ghidra-vibe --print-out-paths)/lib/ghidra
python3 scripts/extract-stock-universe.py
```

## CI gates

`scripts/stock-parity-loop.sh`:

1. Universe extract (or verify present)
2. Every stock tool/provider from universe ⊆ chrome contracts
3. Inventories regenerated; toolbar/provider ids ⊆ a11y catalog + Swift/GTK
4. Every stock `disabled_honest` ∈ `TRACKED_GAPS.json`
5. CodeBrowser liquid-glass / a11y gates
6. Capability matrix covers every stock wired id + universe module (`check-capability-matrix.sh`)
7. Stock Help corpus extract (`check-stock-help.sh`: ≥200 articles, ≥70 tips, TOC/map);
   F1/context Help maps providers → `map.json`; Linux shares the same bundle

## Implementation waves

| Wave | Focus | Status |
|------|--------|--------|
| **A** | CodeBrowser daily RE — save, goto, nav, listing I/D/U/L/F/V/B, search, edit | Done (stock depth allowlisted) |
| **B** | Full stock CB provider bodies at stock depth | Done (canonical provider slugs; headless + Running Tools + disasm/preview) |
| **C** | Front End — VC ops, project tree/table, tool launch | Done — `vc_status` / `vc_op`; **greyed without shared repo is stock parity** (not a gap) |
| **D** | Debugger / Emulator / Version Tracking native tool UIs | Done — shared panes via `mapProvider`; unique via `debugger_list`; VT session; GTK pages |
| **E** | BSim DB UI, full PyGhidra IDE, agent TraceRmi launchers | Outside the TRACKED_GAPS 88-list (separate backlog) |

`TRACKED_GAPS.json` is at **`gaps=0` / `max_stock_disabled=0`**. Non-stock vibe extras (Apple/DSC/RAG/agent panes) remain `stock: false` and are not tracked as stock gaps.

Each closed wave allowlists ids in [`STOCK_DEPTH_ALLOWLIST.json`](../native-ui/parity/STOCK_DEPTH_ALLOWLIST.json); regenerate with `./scripts/stock-parity-loop.sh`.

## Capability suite (runtime proof)

Static allowlist / inventory wiring proves **M1 + id presence**. It does **not** prove every stock control at **M2 UI + M3 engine** runtime. That is the capability suite:

| Artifact | Role |
|----------|------|
| [`CAPABILITY_MATRIX.json`](../native-ui/parity/CAPABILITY_MATRIX.json) | One probe per stock wired inventory id + `STOCK_UNIVERSE` modules (`scripts/generate-capability-matrix.py`) |
| [`RUNTIME_GAPS.json`](../native-ui/parity/RUNTIME_GAPS.json) | Honest Wave E / null tool-map gaps (ratchet `max_runtime_gaps`) |
| `gui-tests/run-stock-capability-suite.sh` | Fixture binary → analysis MCP → every matrix probe → `gui-tests/artifacts/CAPABILITY_REPORT.json` |
| `scripts/check-capability-matrix.sh` | Gate: no orphan inventory/universe ids; every case has a probe |

**Done when:** `unmapped=0`, `failed=0`, and `runtime_gap ≤ max_runtime_gaps`. Remaining Wave E items (BSim DB UI, full PyGhidra IDE, live TraceRmi agents) appear only as ratcheted `RUNTIME_GAPS` — never silent skips.

```bash
export GHIDRA_INSTALL_DIR=$(nix build .#ghidra-vibe --print-out-paths)/lib/ghidra
# Optional but recommended for in-process engine auto-start:
#   export GHIDRA_VIBE_ENGINE_HOME=$(nix build .#ghidra-vibe-engine --print-out-paths)
#   export JAVA_HOME=$(/usr/libexec/java_home -v 21)
./scripts/check-capability-matrix.sh
./gui-tests/run-stock-capability-suite.sh
# Optional M2 GuiControl probes:
#   CAPABILITY_LAUNCH_GUI=1 ./gui-tests/run-stock-capability-suite.sh
```

## Related docs

- [PRODUCT.md](PRODUCT.md) — GhidraVibe is Ghidra
- [ARCHITECTURE.md](ARCHITECTURE.md) — engine + native GUI
- [GUI.md](GUI.md) — chrome and docking
- [GUI_TESTING.md](GUI_TESTING.md) — AX / GuiControl / capability suite how-to
