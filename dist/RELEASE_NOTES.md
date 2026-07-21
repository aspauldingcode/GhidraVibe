## GhidraVibe Beta

Rolling prerelease from `master` (`e091d93`).

- **Commit:** `e091d93783ea02517dc598a6a855cf6db3901290`
- **Range:** `beta..HEAD`

### Changes

- fix(nix): Detach Metal toolchain DMG mount before derivation exits (e091d93)

### Install

1. Download the `.dmg` asset from this release.
2. Open it and drag **GhidraVibe** into Applications.
3. Or develop from source: `nix run` (see README).

### MCP (optional)

With the app running, point Cursor at the bridges under the nix result
`share/ghidra-mcp/` (see docs/CURSOR.md in the repo).
Engine default: `http://127.0.0.1:8089` · GuiControl: `http://127.0.0.1:8091`.
