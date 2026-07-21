# GhidraVibe releases index

Artifacts are published on the [GitHub Releases](https://github.com/aspauldingcode/GhidraVibe/releases) page.
This branch only tracks the latest channel metadata.

{
  "name": "GhidraVibe",
  "version": "0.1.0-e7e481d",
  "sha": "e7e481d",
  "dmg": "GhidraVibe-0.1.0-e7e481d.dmg",
  "dmg_latest": "GhidraVibe-latest.dmg",
  "app": "GhidraVibe.app",
  "generated_at": "2026-07-21T09:13:40Z",
  "channel": "beta",
  "tag": "beta",
  "release_url": "https://github.com/aspauldingcode/GhidraVibe/releases/tag/beta",
  "dmg_url": "https://github.com/aspauldingcode/GhidraVibe/releases/download/beta/GhidraVibe-0.1.0-e7e481d.dmg",
  "dmg_latest_url": "https://github.com/aspauldingcode/GhidraVibe/releases/download/beta/GhidraVibe-latest.dmg"
}

---

## GhidraVibe Beta

Rolling prerelease from `master` (`e7e481d`).

- **Commit:** `e7e481d1c4537849daaee45fb04495fe03fdc02f`
- **Range:** `beta..HEAD`

### Changes

- fix(linux): Port GTK3-only API calls to GTK4 (e7e481d)

### Install

1. Download the `.dmg` asset from this release.
2. Open it and drag **GhidraVibe** into Applications.
3. Or develop from source: `nix run` (see README).

### MCP (optional)

With the app running, point Cursor at the bridges under the nix result
`share/ghidra-mcp/` (see docs/CURSOR.md in the repo).
Engine default: `http://127.0.0.1:8089` · GuiControl: `http://127.0.0.1:8091`.
