# Agents

How Cursor agents and MCP use GhidraVibe.

The **program engine** (`http://127.0.0.1:8089`) must be up whenever MCP is
used. `vibe_health` is the first call. If `analysis.ok` is false, run
`ghidra-vibe-analysis-ensure` — do not keep reversing against a dead JVM.

Rule: `.cursor/rules/analysis-always-on.mdc`.

| Binary | Role |
| --- | --- |
| `ghidra-mcp` | Engine tools; auto-starts analysis if `:8089` is down |
| `ghidra-vibe-mcp` | dyld / Malimite / rules / nav; same ensure |
| `ghidra-vibe-analysis-ensure` | Supervisor / LaunchAgent KeepAlive |

Darwin analysis JDK is IBM Semeru 21 (OpenJ9). Do not inherit HotSpot
`JAVA_HOME` (Zulu/Temurin SIGBUS).
