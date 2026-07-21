# GhidraVibe Release Process

## Current Status

**macOS Releases**: ⚠️ **Currently Not Automated**

GitHub-hosted `macos-14` runners have Swift 5.10, but GhidraVibe requires Swift 6.2+ for building the native macOS app. The `macos-release` workflow will check for Swift 6.2 availability and skip the build with a clear warning if not available.

## Creating Releases

### Option 1: Wait for GitHub Runner Update

GitHub will eventually update their macOS runners to include Swift 6.2+. When this happens, the automated workflow will work automatically.

### Option 2: Build Locally with Nix

If you have a Mac with Swift 6.2+ (or Nix installed), you can build the release locally:

```bash
# Build the macOS app
nix build .#ghidra-vibe-app -o result-app

# Build GhidraVibe headless/engine
nix build .#ghidra-vibe

# Package into DMG
export GHIDRA_INSTALL_DIR="$PWD/result/lib/ghidra"
./macos/GhidraVibe/scripts/package-dmg.sh

# The DMG will be in dist/
ls -lh dist/*.dmg
```

### Option 3: Self-Hosted Runner

Set up a self-hosted macOS runner with Swift 6.2+ and the required labels:

1. Go to repository Settings → Actions → Runners
2. Add a self-hosted runner
3. Install Swift 6.2+ on the runner machine
4. Add labels: `macOS`, `tahoe`, `apple-silicon` (or update workflow)
5. The workflow will automatically use the self-hosted runner

## Release Artifacts

When releases are created, they include:

- `GhidraVibe-{version}.dmg` - The main application bundle
- `GhidraVibe-latest.dmg` - Stable link to the latest version
- `latest.json` - Metadata for update checks
- `RELEASE_NOTES.md` - Auto-generated release notes

## Beta Releases

Beta releases are created on every push to `master`:

- Tag: `beta` (lightweight, force-pushed)
- GitHub Release: marked as "prerelease"
- Updates `releases` branch with metadata

## Stable Releases

Stable releases are created when you push a tag starting with `v`:

```bash
git tag v1.0.0
git push origin v1.0.0
```

This creates:
- Tag: `v1.0.0` (permanent)
- GitHub Release: marked as "latest"
- Updates `releases` branch with metadata

## Workflow Details

See `.github/workflows/macos-release.yml` for the full workflow definition.

### Swift Version Check

The workflow includes a Swift version check at the beginning:

```yaml
- name: Check Swift version
  id: swift-check
  run: |
    # Check if Swift 6.2+ is available
    if xcrun swift --version 2>/dev/null | grep -q "Swift version 6\.[2-9]"; then
      echo "swift_62_available=true" >> "$GITHUB_OUTPUT"
    else
      echo "swift_62_available=false" >> "$GITHUB_OUTPUT"
    fi
```

All subsequent build steps are conditional on `swift_62_available == 'true'`.

## CI Status

Other CI workflows continue to function normally:

- ✅ `ci` - Nix flake checks
- ✅ `Multi-platform CI` - Cross-platform builds
- ✅ `dsc-acceptance` - DSC workflow tests
- ✅ `gui-smoke` - GUI smoke tests
- ✅ `device-agent-tests` - Device agent CLI tests
- ⚠️ `macos-release` - Waiting for Swift 6.2+ on runners

## Future Improvements

1. **Conditional macOS builds**: Once Swift 6.2 is available on GitHub runners, releases will be fully automated
2. **Pre-built binary caching**: Cache Nix-built binaries to speed up DMG packaging
3. **Cross-compilation**: Explore building macOS binaries on Linux with appropriate toolchains
4. **Linux releases**: Add similar release automation for Linux GTK builds

## Questions?

For questions about the release process, see:
- GitHub Actions workflow: `.github/workflows/macos-release.yml`
- DMG packaging scripts: `macos/GhidraVibe/scripts/package-dmg.sh`
- Release notes generation: `scripts/generate-release-notes.sh`
