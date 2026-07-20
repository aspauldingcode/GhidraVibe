# JSpace RAG — reverse-engineering discovery (Rust)

GhidraVibe ships **JSpace** as a **Rust** hybrid retrieval layer so the agent can
*think about* reverse engineering before calling Ghidra MCP tools.

No Python. No cloud. Index + vectors stay on disk.

## Why (“mental model” for RE)

1. **Retrieve** similar functions, strings, and playbook cards  
2. **Orient** (current selection + neighbors)  
3. **Act** via Ghidra MCP (decompile, xrefs, rename, dyld)

## JSpace optimizations

| Optimization | Behavior |
| --- | --- |
| Function-centric chunks | One card per symbol / decompile / string |
| Hybrid search | SQLite **FTS5** + **hashing vectors** (384-d, blake2) |
| RE query expansion | crypto, objc, swift/SwiftUI, dyld, auth, network, ui… |
| Discovery packs | Investigation context + suggested MCP moves |
| Playbook seeds | Offline triage/ObjC/Swift/DSC/crypto/auth/SkyLight |

## CLI (Rust)

```bash
ghidra-vibe-jspace init
ghidra-vibe-jspace index
ghidra-vibe-jspace search "keychain"
ghidra-vibe-jspace discover "how does login validate the password?"
ghidra-vibe-jspace stats
```

Build: `nix build .#ghidra-vibe-tools` or `cargo build --release` in `rust/`.

DB: `GHIDRA_VIBE_JSPACE_DB` (default `.ghidra-vibe-jspace/jspace.sqlite`).

## Agent / Cursor

- In-app Agent calls `rag_discover` (vibe MCP) on every message; rules are injected.
- Unified vibe MCP (`:8092`): `rag_discover`, `rag_search`, `rag_index`, `rag_stats`, plus `rules_*`.
- Also: Rust `ghidra-vibe-rag-mcp` stdio bridge (same tool names).
- GuiControl: `POST /rag/discover`, `POST /rag/index`, `GET /rag/stats`.
- Smoke: `gui-tests/smoke-rag-agent.sh`.

## Workflow

```text
Open DSC image → analyze → ghidra-vibe-jspace index
Ask: “where is SkyLight display geometry decided?”
→ JSpace cards → decompile top hit → rename → re-index
```
