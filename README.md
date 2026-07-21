# GhidraVibe releases index

Artifacts are published on the [GitHub Releases](https://github.com/aspauldingcode/GhidraVibe/releases) page.
This branch only tracks the latest channel metadata.

{
  "name": "GhidraVibe",
  "version": "0.1.0-800ce5f",
  "sha": "800ce5f",
  "dmg": "GhidraVibe-0.1.0-800ce5f.dmg",
  "dmg_latest": "GhidraVibe-latest.dmg",
  "app": "GhidraVibe.app",
  "generated_at": "2026-07-21T17:29:00Z",
  "channel": "beta",
  "tag": "beta",
  "release_url": "https://github.com/aspauldingcode/GhidraVibe/releases/tag/beta",
  "dmg_url": "https://github.com/aspauldingcode/GhidraVibe/releases/download/beta/GhidraVibe-0.1.0-800ce5f.dmg",
  "dmg_latest_url": "https://github.com/aspauldingcode/GhidraVibe/releases/download/beta/GhidraVibe-latest.dmg"
}

---

## GhidraVibe Beta

Rolling prerelease from `master` (`800ce5f`).

- **Commit:** `800ce5ffcc7497bbc74da303db6486fe9788b81c`
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
