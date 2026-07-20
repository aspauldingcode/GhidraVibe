# GUI testing (agent-device + Accessibility)

Every interactive control has a stable id, label, and hint (tooltip) from
[`native-ui/a11y/catalog.json`](../native-ui/a11y/catalog.json). Prefer `id="…"` selectors.

## Identifier convention

| Pattern | Example |
| --- | --- |
| Root / chrome | `ghidra.vibe.root`, `ghidra.vibe.status.bar` |
| Tool windows | `ghidra.vibe.project`, `ghidra.vibe.codebrowser` |
| Toolbar | `ghidra.vibe.toolbar.mcp_health`, `…goto`, `…dsc` |
| Providers | `ghidra.vibe.provider.listing`, `…decompiler`, `…mcp` |
| Menus | `ghidra.vibe.menu.file.import` |

macOS binds via `a11yCatalog(_:)` (Swift). GTK via `vibe_a11y_bind()`.

## agent-device loop (CLI or MCP)

```bash
./macos/GhidraVibe/scripts/package-app.sh
agent-device open ./macos/GhidraVibe/.build/GhidraVibe.app --platform macos --relaunch --session vibe
agent-device snapshot -i --session vibe --platform macos
agent-device is exists 'id="ghidra.vibe.toolbar.mcp_health"' --session vibe --platform macos
agent-device click 'id="ghidra.vibe.project.start_mcp"' --session vibe --platform macos
```

Replay: `gui-tests/smoke-a11y.ad` (macOS), `gui-tests/linux/smoke-a11y.ad` (Linux).

Stock 1:1 parity gates (universe → chrome → inventory → a11y → Liquid Glass):

```bash
scripts/stock-parity-loop.sh          # preferred (full stock bar)
scripts/codebrowser-parity-loop.sh    # alias → stock-parity-loop.sh
# regenerate universe after Ghidra upgrades:
#   export GHIDRA_INSTALL_DIR=$(nix build .#ghidra-vibe --print-out-paths)/lib/ghidra
#   python3 scripts/extract-stock-universe.py
gui-tests/smoke-app-bundle.sh   # needs vibe MCP :8092
# live AX:
#   agent-device replay gui-tests/codebrowser-parity.ad --session vibe --platform macos
#   agent-device replay gui-tests/debugger-parity.ad --session vibe --platform macos
#   agent-device replay gui-tests/emulator-parity.ad --session vibe --platform macos
#   agent-device replay gui-tests/vt-parity.ad --session vibe --platform macos
```

See [STOCK_PARITY.md](STOCK_PARITY.md). Gaps: `native-ui/parity/TRACKED_GAPS.json` (ratchet `max_stock_disabled`).

GuiControl HTTP (`GHIDRA_VIBE_GUI_URL`, default `:8091`) exposes `/state`, `/action`, `/a11y/catalog`
for agents that prefer HTTP over AX scrape.

Whoami / AppKit decompile (GuiControl assertion; fixture prep is CLI only):

```bash
./gui-tests/smoke-whoami-decompile.sh
# Native Function Graph CFG (BasicBlockModel → AppKit canvas; asserts blocks+edges):
./gui-tests/smoke-function-graph.sh
# DSC AppKit (first import can take several minutes; reuses /tmp fixture after):
./gui-tests/smoke-appkit-decompile.sh
# Force re-import / rebuild app:
#   APPKIT_FORCE_IMPORT=1 APPKIT_REPACKAGE=1 ./gui-tests/smoke-appkit-decompile.sh
```

Full AppKit classes GUI path (DSC open → analyze → ObjC class list → decompile):

```bash
./gui-tests/smoke-appkit-classes.sh
# Artifacts: gui-tests/artifacts/appkit-classes-*.txt/json
# Faster reuse of an already-imported project:
#   APPKIT_CLASSES_REUSE_PROJECT=1 ./gui-tests/smoke-appkit-classes.sh
```

Asserts `/state` `objcClassPreview` (NSApplication/…) and a class-method `decompilePreview`.
`GHIDRA_INSTALL_DIR` auto-detects from nix/`result` when unset.

## Stock capability suite (every-feature runtime)

Inventory-driven M2/M3 probes for every stock wired id + universe module. Static
`TRACKED_GAPS=0` alone is not enough — this suite exercises MCP/engine/GuiControl
(or records an explicit `runtime_gap`).

```bash
export GHIDRA_INSTALL_DIR=$(nix build .#ghidra-vibe --print-out-paths)/lib/ghidra
./scripts/check-capability-matrix.sh
# Starts analysis MCP via packaged GhidraVibe in-process engine if :8089 is down.
./gui-tests/run-stock-capability-suite.sh
# Also wait for GuiControl (:8091) M2 probes:
#   CAPABILITY_LAUNCH_GUI=1 ./gui-tests/run-stock-capability-suite.sh
# Skip auto-start (fail if MCP already down):
#   CAPABILITY_START_ANALYSIS=0 ./gui-tests/run-stock-capability-suite.sh
```

Report: `gui-tests/artifacts/CAPABILITY_REPORT.json` (includes `pass_class` hard/honest/soft/catalog).
Suite fails on `unmapped` / `failed`, or when `runtime_gap` exceeds
`native-ui/parity/RUNTIME_GAPS.json` `max_runtime_gaps`.

## Prerequisites

- macOS: Accessibility permission for Terminal / Cursor / `agent-device`
- `agent-device` ≥ 0.18
- Linux: AT-SPI enabled for the GTK shell
- Capability suite: `GHIDRA_INSTALL_DIR` + analysis MCP (see above)
