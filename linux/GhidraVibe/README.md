# GhidraVibe (GTK)

Native Linux shell mirroring stock Ghidra **Project Window**, **CodeBrowser**, and Tool Chest
tools (**Debugger** / **Emulator** / **Version Tracking**) (GTK4 + libadwaita). Talks to the
program engine over HTTP; stock tool pages share `native-ui/parity` contracts with macOS.

## Build

```bash
meson setup build
meson compile -C build
# Optional HTML Help rendering (TOC works without it):
#   apt/dnf/nix: webkitgtk-6.0
GHIDRA_VIBE_UI_DATA=../../native-ui ./build/ghidra-vibe
```

Help → **Ghidra Help…** opens the stock JavaHelp corpus from `native-ui/help`
(or `GHIDRA_VIBE_HELP`). Generate with `scripts/extract-stock-help.py`.

Nix: `nix build .#ghidra-vibe-gtk` (Linux).

## Accessibility

Stable ids match `native-ui/a11y/catalog.json` (`ghidra.vibe.*`). Toolbar buttons set
tooltips from catalog `hint`. Automate with agent-device / AT-SPI using `id=` / accessible name.
