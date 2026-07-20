# Dyld shared cache (first-class, IDA-like)

Opening a macOS/iOS framework from the system shared cache is a **built-in File /
toolbar / Tool Chest action** — not an MCP addon pane you have to discover.

## How IDA does it (what we mirror)

| IDA 9.4 | GhidraVibe |
| --- | --- |
| Open `dyld_shared_cache_*` (header / index) | **File → Open Framework from Shared Cache…** |
| DSC Index widget — filter images | Framework picker search (or Window → Shared Cache) |
| Load selected module (+ deps) | **Open** → `DyldCacheFileSystem` import |
| Local symbols / ObjC / DWARF | Apple symbols on by default |
| Listing / decompile / graph | Auto: Listing, Decompile, Function Graph, Classes |

References: [IDA DSC workflow](https://docs.hex-rays.com/9.4/core/disassembler/concepts/dsc-workflow),
Ghidra `DyldCacheFileSystem` / `AutoImporter.importByUsingBestGuess(FSRL, …)`.

## Native UI (primary path)

1. **File → Open Framework from Shared Cache…** (`⌘⇧O`)  
   or Project Window **Shared Cache** tile  
   or CodeBrowser toolbar **Framework…**
2. Search (e.g. `AppKit`, `SwiftUI`, `SkyLight`) → select → **Open**
3. CodeBrowser opens with:
   - Listing + Functions
   - Decompile (entry / main / first interesting function)
   - Function Graph
   - **Classes** left dock (ObjC / Swift)
4. Optional: enable **Auto Analyze after open** in the picker (slower; IDA-like default is open first)

Advanced: **File → Browse Shared Cache…** or Window → Shared Cache for the full index provider.

## On-device cache locations (Apple Silicon)

Tried in order:

1. `/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e`
2. `/System/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e`
3. `/System/Library/dyld/dyld_shared_cache_arm64e`

Split siblings (`.01`, `.dyldlinkedit`, …) stay next to the base file —
Ghidra’s `SplitDyldCache` reads them automatically.

## MCP / CLI (automation — same engine)

| Tool / CLI | Role |
| --- | --- |
| `dyld_find_cache` / `ghidra-vibe-dyld find-cache` | Locate cache |
| `dyld_list_images` / `list --query …` | Index filter |
| `dyld_import_image` / `import --image …` | Open module |

```bash
ghidra-vibe-dyld list --query AppKit
ghidra-vibe-dyld import --image AppKit
gui-tests/smoke-appkit-decompile.sh
```

## Apple symbols

Default **on** (`GHIDRA_VIBE_APPLE_SYMBOLS=1`): DSC local symbols + DWARF / ObjC /
demangler analyzers. Set `=0` only when debugging the loader.

## What we do **not** do by default

- Whole-cache load as one program
- `ipsw dyld extract` (only if both `GHIDRA_VIBE_ALLOW_IPSW=1` and
  `GHIDRA_VIBE_FORCE_EXTRACT=1`)
