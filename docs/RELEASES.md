# GhidraVibe Release Process

## Current Status

**macOS Releases**: ✅ **Working**
- Runs on GitHub-hosted `macos-26` runners (ship Swift 6.2+)
- Builds the app via `nix build .#ghidra-vibe-app`, packages it into a `.dmg`

**Linux Releases**: ✅ **Working**
- Runs on GitHub-hosted `ubuntu-24.04` (x86_64) and `ubuntu-24.04-arm` (aarch64) —
  true native builds, no QEMU emulation
- Packaged with `nix bundle --bundler github:ralismark/nix-appimage`, which
  produces a genuinely portable, statically-linked AppImage (no dependency on
  the host's glibc or `/nix/store`)

Both workflows run automatically on every push to `master`/`main` (publishing
the rolling `beta` prerelease) and on `v*` tags (publishing a dedicated
release).

## Release Artifacts

When releases are created, they include:

### macOS
- `GhidraVibe-{version}.dmg` - The main application bundle
- `GhidraVibe-latest.dmg` - Stable link to the latest version
- `latest.json` - Metadata for update checks

### Linux
- `GhidraVibe-{version}-x86_64.AppImage` - Intel/AMD 64-bit AppImage
- `GhidraVibe-{version}-aarch64.AppImage` - ARM 64-bit AppImage
- `GhidraVibe-latest-x86_64.AppImage` - Stable link for x86_64
- `GhidraVibe-latest-aarch64.AppImage` - Stable link for aarch64
- `latest-x86_64.json` - Metadata for x86_64
- `latest-aarch64.json` - Metadata for aarch64

### Common
- `RELEASE_NOTES.md` - Auto-generated release notes

## Beta Releases

Beta releases are created on every push to `master`:

- Tag: `beta` (lightweight, force-pushed)
- GitHub Release: marked as "prerelease"

## Stable Releases

Stable releases are created when you push a tag starting with `v`:

```bash
git tag v1.0.0
git push origin v1.0.0
```

This creates:
- Tag: `v1.0.0` (permanent)
- GitHub Release: marked as "latest"

## Building Locally

### macOS

```bash
nix build .#ghidra-vibe-app -o result-app
nix build .#ghidra-vibe
export GHIDRA_INSTALL_DIR="$PWD/result/lib/ghidra"
SKIP_SWIFT_BUILD=1 GHIDRA_VIBE_PREBUILT_APP="$PWD/result-app/Applications/GhidraVibe.app" \
  ./macos/GhidraVibe/scripts/package-dmg.sh
ls -lh dist/*.dmg
```

Or, to build fresh from source instead of the Nix output (requires Swift 6.2+):

```bash
./macos/GhidraVibe/scripts/package-dmg.sh
```

### Linux

```bash
nix bundle --bundler github:ralismark/nix-appimage .#ghidra-vibe-gtk
```

## Workflow Details

### macOS Release (`macos-release.yml`)
- Runs on: `macos-26` (GitHub-hosted, Apple Silicon)
- Builds with: Nix (`ghidra-vibe` engine + `ghidra-vibe-app` SwiftUI app)
- Produces: `.dmg` installer
- The Nix-built `.app` is staged at `.build/nix-prebuilt/GhidraVibe.app`
  (kept separate from `package-app.sh`'s output path so it isn't deleted
  during cleanup) and copied into place via `SKIP_SWIFT_BUILD=1`
- See `.github/workflows/macos-release.yml` for the full workflow

### Linux Release (`linux-release.yml`)
- Runs on: `ubuntu-24.04` (x86_64) and `ubuntu-24.04-arm` (aarch64) — both
  native GitHub-hosted runners, no cross-compilation/emulation
- Builds with: Nix + GTK 4, bundled via `nix bundle --bundler
  github:ralismark/nix-appimage`
- Produces: `.AppImage` bundles
- See `.github/workflows/linux-release.yml` for the full workflow

## CI Status

Release workflows:

- ✅ `macos-release` - Publishing `.dmg` via macos-26 runners
- ✅ `linux-release` - Publishing x86_64 and aarch64 AppImages

Other CI workflows:

- ✅ `ci` - Nix flake checks
- ✅ `Multi-platform CI` - Cross-platform builds (uses the actual `ghidra-vibe*`
  flake output names — the older `ghidraVibe*` camelCase names never matched
  any exposed attribute)
- ⏳ `dsc-acceptance` / `gui-smoke` - Require a self-hosted
  `[self-hosted, macOS, tahoe, apple-silicon]` runner; queued indefinitely
  when no such runner is online. Not part of the GitHub-hosted release path.
- ✅ `device-agent-tests` - Device agent CLI tests

## Questions?

For questions about the release process, see:
- GitHub Actions workflows: `.github/workflows/macos-release.yml`,
  `.github/workflows/linux-release.yml`
- DMG packaging scripts: `macos/GhidraVibe/scripts/package-dmg.sh`,
  `macos/GhidraVibe/scripts/package-app.sh`
- Release notes generation: `scripts/generate-release-notes.sh`
