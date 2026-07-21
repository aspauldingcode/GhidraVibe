# GhidraVibe releases index

Artifacts are published on the [GitHub Releases](https://github.com/aspauldingcode/GhidraVibe/releases) page.
This branch only tracks the latest channel metadata.

{
  "name": "GhidraVibe",
  "version": "0.1.0-67b987f",
  "sha": "67b987f",
  "dmg": "GhidraVibe-0.1.0-67b987f.dmg",
  "dmg_latest": "GhidraVibe-latest.dmg",
  "app": "GhidraVibe.app",
  "generated_at": "2026-07-21T09:03:44Z",
  "channel": "beta",
  "tag": "beta",
  "release_url": "https://github.com/aspauldingcode/GhidraVibe/releases/tag/beta",
  "dmg_url": "https://github.com/aspauldingcode/GhidraVibe/releases/download/beta/GhidraVibe-0.1.0-67b987f.dmg",
  "dmg_latest_url": "https://github.com/aspauldingcode/GhidraVibe/releases/download/beta/GhidraVibe-latest.dmg"
}

---

## GhidraVibe Beta

Rolling prerelease from `master` (`67b987f`).

- **Commit:** `67b987fe7d78b17a617d03d204bac7050562e330`
- **Range:** `HEAD`

### Changes

- Initial packaging commit

### Install

1. Download the `.dmg` asset from this release.
2. Open it and drag **GhidraVibe** into Applications.
3. Or develop from source: `nix run` (see README).

### MCP (optional)

With the app running, point Cursor at the bridges under the nix result
`share/ghidra-mcp/` (see docs/CURSOR.md in the repo).
Engine default: `http://127.0.0.1:8089` · GuiControl: `http://127.0.0.1:8091`.
