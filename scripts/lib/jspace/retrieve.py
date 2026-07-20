"""Discovery context assembly — how the agent 'thinks' about RE problems."""
from __future__ import annotations

from .embed import expand_re_query
from .store import JSpaceStore

DISCOVERY_PREAMBLE = """# RE discovery context (JSpace)
You are investigating a binary with Ghidra. Use the retrieved cards below as
working memory before calling MCP tools. Prefer evidence (addresses, names,
strings) over speculation. When unsure, decompile / list xrefs via Ghidra MCP.
"""


def search(store: JSpaceStore, query: str, *, top_k: int = 8, kind: str | None = None) -> list[dict]:
    expanded = expand_re_query(query)
    return store.hybrid_search(expanded, top_k=top_k, kind=kind)


def format_card(hit: dict, idx: int) -> str:
    name = hit.get("name") or "(unnamed)"
    addr = hit.get("address") or ""
    kind = hit.get("kind") or "chunk"
    score = hit.get("score", 0.0)
    via = hit.get("via") or ""
    text = (hit.get("text") or "")[:1200]
    return (
        f"### [{idx}] {kind} `{name}` @ {addr} (score={score:.3f} via={via})\n"
        f"{text}\n"
    )


def discovery_context(
    store: JSpaceStore,
    query: str,
    *,
    top_k: int = 8,
    current_function: str | None = None,
    current_decompile: str | None = None,
) -> str:
    """Build a mental-model pack for the agent: selection + JSpace neighbors."""
    parts = [DISCOVERY_PREAMBLE, f"## Question\n{query}\n"]
    if current_function:
        parts.append(f"## Current selection\nFunction: `{current_function}`\n")
        if current_decompile:
            parts.append("```c\n" + current_decompile[:2000] + "\n```\n")
    hits = search(store, query, top_k=top_k)
    parts.append("## Retrieved RE cards\n")
    if not hits:
        parts.append("_JSpace empty — run `ghidra-vibe-jspace index` after MCP is up._\n")
    else:
        for i, h in enumerate(hits, 1):
            parts.append(format_card(h, i))
    parts.append(
        "## Suggested next MCP moves\n"
        "- `methods` / select a card name\n"
        "- `decompile` the top hit\n"
        "- `xrefs` / `get_xrefs_to` for callers\n"
        "- rename once the role is clear\n"
    )
    return "\n".join(parts)
