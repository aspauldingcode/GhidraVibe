# Swift / SwiftUI reverse engineering

## Does Ghidra support Swift?

**Yes — partially, and that is the industry baseline.**

Stock Ghidra (12.x) ships:

| Feature | Role |
| --- | --- |
| **Demangler Swift** | Calls host `swift demangle` for `$s` / `_$s` / `_T` symbols |
| **Swift Type Metadata Analyzer** | Marks up `__swift5_*` sections (types, protocols, conformances) |

There is **no separate “SwiftUI decompiler”**. SwiftUI is Swift ABI + protocol witnesses + opaque types; you recover it with demangling + metadata + decompiler on the witness methods, same as every other SRE tool.

## How people do it otherwise

1. **Ghidra / IDA / Binary Ninja** demangle + type metadata  
2. **`swift demangle` / `swift-demangle`** offline on symbol dumps  
3. **Dynamic**: Frida (`frida-swift-dump` style) for runtime names  
4. **Hopper / BN** plugins for richer Swift types (still not magical SwiftUI)

## GhidraVibe support

See also [APPLE.md](APPLE.md) for IPA/bundle import and Swift Classes UI (Malimite-inspired).

On DSC / Apple bundle import (`ImportDyldCacheImage`, `ImportAppleBundle`), analyzers enabled by default:

- Demangler Swift  
- Swift Type Metadata Analyzer  
- DWARF / ObjC / GNU demangler  

Ensure `swift` is on `PATH` (Xcode CLT / Nix `swift`). JSpace playbook card `swift` steers the agent toward metadata + demangle + MCP decompile.

```bash
# After importing a Swift-heavy image:
ghidra-vibe-jspace index
ghidra-vibe-jspace discover "where is the SwiftUI View body for this screen?"
```
