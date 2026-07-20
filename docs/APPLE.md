# Apple reverse engineering (first-class App Bundle)

App / IPA / framework open is a **built-in File and toolbar action**. The
Malimite-parity pipeline (class dump, resources, refs, translate) runs under the
hood — the UI is labeled **App Bundle**, not a third-party plugin.

Attribution: [Malimite](https://github.com/LaurieWired/Malimite) (LaurieWired /
Apache-2.0) for analysis learnings.

## Native UI (primary path)

| Action | Where |
| --- | --- |
| **Open App Bundle…** | File menu, CodeBrowser toolbar **App Bundle…**, Project Window **App Bundle** tile |
| **Analyze App Bundle…** | File menu — full resources + class dump + refs into the project |
| **Classes** | Left dock (ObjC / Swift tabs) — stock-like beside Symbol Tree |
| **App Bundle** provider | Window menu — resources, strings, entrypoints, libraries, LLM translate |

Open path:

1. File → **Open App Bundle…** → pick `.app` / `.ipa` / `.framework`
2. CodeBrowser opens with Program Trees bundle map, Decompile, Function Graph, Classes
3. Use **Analyze Bundle** in the App Bundle provider (or File → Analyze App Bundle…) for the full harvest

## Feature matrix

| Capability | GhidraVibe |
| --- | --- |
| IPA / .app / Mach-O import | Open App Bundle / Analyze App Bundle |
| Whole .app open | File → Open App Bundle… |
| Info.plist / resources | App Bundle → Resources |
| Swift / ObjC classes | Classes left dock + App Bundle → Classes |
| Entrypoints / refs / strings | App Bundle tabs |
| Library skip-list | App Bundle → Libraries |
| LLM Auto Fix / Summarize | App Bundle → Translate (+ Agent) |
| Shared Cache frameworks | File → Open Framework from Shared Cache… ([DYLD.md](DYLD.md)) |

## MCP / CLI (automation)

Same tools as before (`malimite_*` on vibe MCP `:8092`, `ghidra-vibe-apple`).
Cursor/agents use the bridges; humans use File / toolbar.

```bash
ghidra-vibe-apple analyze /path/to/App.ipa --project "$PWD/ghidra-vibe-projects/AppBundle"
gui-tests/smoke-app-bundle.sh
gui-tests/smoke-malimite.sh
```

## Scripts

`ImportAppleBundle.java`, `DumpClassDataVibe.java`, `DumpEntrypointsVibe.java`,
`DumpFunctionRefsVibe.java` — invoked by the App Bundle pipeline, not by hand.
