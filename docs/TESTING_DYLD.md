# Dyld Shared Cache Testing Guide

This guide covers complete testing of the dyld shared cache workflow, including framework selection and decompilation.

## Quick Test (Automated)

### Basic Workflow Test (No GUI Required)

Tests cache discovery, listing, and resolution:

```bash
./gui-tests/test-dyld-workflow.sh
```

**What it tests:**
- ✅ Cache discovery (platform-specific)
- ✅ Framework listing (100+ frameworks)
- ✅ Framework querying (AppKit, Foundation, UIKit, etc.)
- ✅ Framework path resolution
- ✅ Import infrastructure validation
- ✅ Platform-specific validation

### Full Decompilation Test (Requires Running GhidraVibe)

Tests complete workflow including decompilation via MCP:

```bash
# Terminal 1: Start GhidraVibe
nix run .#ghidraVibe

# Terminal 2: Run test
./gui-tests/test-dyld-decompile-mcp.sh

# Or test specific framework/function:
./gui-tests/test-dyld-decompile-mcp.sh Foundation NSString
```

**What it tests:**
- ✅ MCP connectivity
- ✅ Cache discovery via MCP
- ✅ Framework listing via MCP
- ✅ Framework import with analysis
- ✅ Function search
- ✅ Decompilation of actual functions

---

## Manual Testing (GUI)

### macOS (On-Device Cache)

1. **Start GhidraVibe:**
   ```bash
   nix run .#ghidraVibe
   ```

2. **Open Framework from Shared Cache:**
   - Menu: `File → Open Framework from Shared Cache…`
   - Or: CodeBrowser toolbar → `Framework…` button
   - Or: Keyboard shortcut: `⌘⇧O`

3. **Search and Select Framework:**
   - Search field: Type `AppKit`
   - Results show matching frameworks
   - Select: `AppKit.framework`
   - Click: `Open`

4. **Wait for Import:**
   - Status bar shows progress
   - "Import complete" message appears
   - CodeBrowser opens with listing

5. **Find NSWindow:**
   - Window menu → `Functions` (or `⌘1`)
   - Filter box: Type `NSWindow`
   - See all NSWindow methods listed

6. **Decompile Function:**
   - Click any NSWindow method (e.g., `NSWindow::init`)
   - Right panel shows decompilation automatically
   - Or: Window menu → `Decompile`

7. **Verify Decompilation:**
   - Should see C-like pseudocode
   - Method calls, control flow visible
   - Types resolved (NSWindow, id, SEL, etc.)

### Linux (IPSW-Extracted Cache)

1. **Setup IPSW Cache (First Time Only):**
   ```bash
   # Auto setup
   ghidra-vibe-dyld setup-ipsw
   
   # Or manual setup
   # 1. Download iOS IPSW from https://ipsw.me
   # 2. Extract:
   nix shell nixpkgs#ipsw -c ipsw dyld extract <ipsw-file> \
     --output ~/.local/share/ghidra-vibe/ipsw-cache
   # 3. Set environment:
   export GHIDRA_VIBE_IPSW_CACHE=~/.local/share/ghidra-vibe/ipsw-cache/dyld_shared_cache_arm64e
   ```

2. **Start GhidraVibe:**
   ```bash
   nix run .#ghidraVibe
   ```

3. **Check DSC Setup (If Needed):**
   - Menu: `Tools → DSC/IPSW Setup…`
   - Shows cache status
   - Can run auto-setup from dialog

4. **Follow same steps as macOS** (steps 2-7 above)

---

## Command-Line Testing

### Test Individual Components

```bash
# Find cache
ghidra-vibe-dyld find-cache

# List all frameworks
ghidra-vibe-dyld list

# Query specific framework
ghidra-vibe-dyld list --query AppKit

# Resolve framework path
ghidra-vibe-dyld resolve --image AppKit

# Import framework (creates Ghidra project)
ghidra-vibe-dyld import --image AppKit \
  --project ~/test-dsc \
  --analyze 1
```

### Test Multiple Frameworks

Test various framework types to ensure comprehensive support:

```bash
# System frameworks
ghidra-vibe-dyld import --image Foundation
ghidra-vibe-dyld import --image CoreFoundation

# UI frameworks
ghidra-vibe-dyld import --image AppKit       # macOS
ghidra-vibe-dyld import --image UIKit        # iOS

# Graphics frameworks
ghidra-vibe-dyld import --image CoreGraphics
ghidra-vibe-dyld import --image Metal

# Private frameworks
ghidra-vibe-dyld import --image SkyLight
```

---

## Expected Results

### Cache Discovery

**macOS:**
```
/System/Library/dyld/dyld_shared_cache_arm64e
```
Or Cryptexes variant on newer systems.

**Linux:**
```
/home/user/.local/share/ghidra-vibe/ipsw-cache/dyld_shared_cache_arm64e
```
Or custom path via `GHIDRA_VIBE_IPSW_CACHE`.

### Framework Listing

Should return **100+ frameworks**, including:
- Standard: Foundation, CoreFoundation, AppKit, UIKit
- Graphics: CoreGraphics, Metal, MetalKit, SpriteKit
- Media: CoreAudio, AVFoundation, CoreMedia
- Private: SkyLight, SpringBoard, BackBoardServices

### AppKit Import

**Expected output:**
```
OK: imported AppKit
project=/path/to/project
program=AppKit
```

**Project structure:**
```
~/Documents/GhidraVibe/projects/dsc/VibeDSC.gpr
└── AppKit (program)
    ├── Functions (~30,000+)
    ├── Data Types
    ├── Symbol Tree
    └── Classes (ObjC/Swift)
```

### NSWindow Decompilation

**Example function:** `NSWindow::init`

**Expected decompilation output:**
```c
void * -[NSWindow init](void * self, char * _cmd) {
    void *rax;
    
    rax = [self initWithContentRect:NSZeroRect
                          styleMask:0x1
                            backing:0x2
                              defer:NO];
    return rax;
}
```

Should show:
- Method signature
- ObjC message sends
- Constants and enums
- Control flow
- Type information

---

## Troubleshooting

### "No cache found"

**macOS:**
- Check Xcode/CLT installed
- Try: `sudo xcode-select --switch /Applications/Xcode.app`

**Linux:**
- Run: `ghidra-vibe-dyld setup-ipsw`
- Or set `GHIDRA_VIBE_IPSW_CACHE` manually

### "Import failed"

- Check heap size: `GHIDRA_VIBE_MAXMEM=24G`
- Check disk space: imports are large (~1GB+)
- Check log: `~/Library/Logs/GhidraVibe/dsc-import-latest.log`

### "MCP not reachable"

- Ensure GhidraVibe is running
- Check MCP URL: default is `http://127.0.0.1:8092`
- Set: `export GHIDRA_VIBE_MCP_URL=http://127.0.0.1:8092`

### "No functions found"

- Enable analysis: `--analyze 1`
- Wait for auto-analysis to complete
- Check Symbol Tree for imports

### "Decompilation empty"

- Ensure Apple symbols enabled: `GHIDRA_VIBE_APPLE_SYMBOLS=1`
- Run auto-analysis if skipped
- Some functions may be stubs/trampolines

---

## Performance Notes

### Import Times (Typical)

| Framework | Size | Import Time | Analysis Time |
|-----------|------|-------------|---------------|
| Foundation | ~2MB | 30-60s | 2-5 min |
| AppKit | ~6MB | 2-3 min | 10-15 min |
| UIKit | ~8MB | 3-5 min | 15-20 min |

### Heap Requirements

- Small frameworks (<5MB): 8GB heap sufficient
- Large frameworks (>5MB): 16GB+ recommended
- Multiple concurrent imports: 24GB+

Set via: `export GHIDRA_VIBE_MAXMEM=24G`

---

## Continuous Integration

The CI workflow automatically tests:

1. **Cache discovery** (both platforms)
2. **Framework listing** (validates 100+ frameworks)
3. **Script functionality** (help, commands)
4. **Build validation** (ensures scripts are packaged)

Run locally:
```bash
# Parity test (includes dyld checks)
./gui-tests/test-gui-parity.sh

# Full dyld workflow
./gui-tests/test-dyld-workflow.sh

# Full decompilation test (needs running GhidraVibe)
./gui-tests/test-dyld-decompile-mcp.sh
```

---

## Framework Selection Examples

You can select and analyze **any** framework from the shared cache:

### Common Frameworks

```bash
# System
ghidra-vibe-dyld import --image Foundation
ghidra-vibe-dyld import --image CoreFoundation
ghidra-vibe-dyld import --image libSystem

# UI
ghidra-vibe-dyld import --image AppKit
ghidra-vibe-dyld import --image UIKit
ghidra-vibe-dyld import --image SwiftUI

# Graphics
ghidra-vibe-dyld import --image CoreGraphics
ghidra-vibe-dyld import --image Metal
ghidra-vibe-dyld import --image MetalKit

# Networking
ghidra-vibe-dyld import --image CFNetwork
ghidra-vibe-dyld import --image Network

# Security
ghidra-vibe-dyld import --image Security
ghidra-vibe-dyld import --image CryptoKit
```

### Private Frameworks

```bash
ghidra-vibe-dyld import --image SkyLight
ghidra-vibe-dyld import --image SpringBoard
ghidra-vibe-dyld import --image BackBoardServices
```

All frameworks support full decompilation and analysis!
