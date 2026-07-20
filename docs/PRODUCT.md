# Product: GhidraVibe *is* Ghidra

GhidraVibe is **not** a remote controller for stock `ghidra-bin` or Swing
`GhidraRun`. It **is** Ghidra — built from source — with a native GUI and
first-class additions.

## What users get

Use it as **normal, full Ghidra**: projects, programs, analyzers, decompiler,
listing, data types, scripts, navigation — the whole RE workflow.

| Capability | How |
|------------|-----|
| Full Ghidra program engine | Gradle **from-source** (never `ghidra-bin`) |
| GUI | Native SwiftUI (macOS) / GTK (Linux) — replaces Swing FrontEnd/CodeBrowser |
| Optional MCP | Agents / Cursor / IDEs can drive the same engine when desired |
| Agents / LLMs | Xcode-style Agent sidebar + JSpace RAG; Metal Ollama OpenAI-compat (ANEMLL stub) |
| dyld shared cache | IDA-like on-device DSC open / index / load module |
| Swift / SwiftUI / ObjC | Malimite-inspired Apple RE (IPA/app bundle, Swift classes) |

## What it is not

- A thin shell that puppets someone else’s Ghidra install
- Swing-first with a native overlay
- “MCP required to reverse engineer” — MCP is optional control, not the app

## Architecture in one line

```
Ghidra source → nix from-source build → full engine
              + native GUI (product window, engine in-process)
              + true headless CLI for agents/batch
              + optional MCP / dyld / Malimite
```

**GUI vs headless:** the app embeds the Ghidra JVM in the same process (normal
Ghidra). `ghidra-vibe-mcp-headless` is only for true headless / agent use.

Details: [ARCHITECTURE.md](ARCHITECTURE.md), [GUI.md](GUI.md),
[STOCK_PARITY.md](STOCK_PARITY.md) (1:1 stock feature/UX bar), [DYLD.md](DYLD.md),
[APPLE.md](APPLE.md), [CURSOR.md](CURSOR.md).
