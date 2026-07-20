# GhidraVibe (GTK)

Native Linux shell mirroring stock Ghidra **Project Window**, **CodeBrowser**, and Tool Chest
tools (**Debugger** / **Emulator** / **Version Tracking**) (GTK4 + libadwaita). Talks to the
program engine over HTTP; stock tool pages share `native-ui/parity` contracts with macOS.

## Build

```bash
meson setup build
meson compile -C build
GHIDRA_VIBE_UI_DATA=../../native-ui ./build/ghidra-vibe
```

Nix: `nix build .#ghidra-vibe-gtk` (Linux).

## Accessibility

Stable ids match `native-ui/a11y/catalog.json` (`ghidra.vibe.*`). Toolbar buttons set
tooltips from catalog `hint`. Automate with agent-device / AT-SPI using `id=` / accessible name.
