#!/usr/bin/env python3
"""MCP stdio bridge: JSpace RE RAG tools for Cursor / agents."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

# Packaged or repo layout
_HERE = Path(__file__).resolve()
_CANDIDATES = [
    _HERE.parents[1] / "lib",  # share/ghidra-vibe/lib when packaged oddly
    _HERE.parents[2] / "scripts" / "lib",  # repo: nix/share → ../../scripts/lib
    Path(os.environ.get("GHIDRA_VIBE_JSPACE_LIB", "")),
]
for c in _CANDIDATES:
    if c and (c / "jspace").is_dir():
        sys.path.insert(0, str(c))
        break

from jspace.index_mcp import index_from_mcp, index_playbook_only  # noqa: E402
from jspace.retrieve import discovery_context, search  # noqa: E402
from jspace.store import JSpaceStore  # noqa: E402

DB = Path(
    os.environ.get(
        "GHIDRA_VIBE_JSPACE_DB",
        str(Path.home() / ".cache" / "ghidra-vibe" / "jspace.sqlite"),
    )
)


def store() -> JSpaceStore:
    return JSpaceStore(DB)


TOOLS = [
    {
        "name": "rag_stats",
        "description": "JSpace index stats (chunk counts by kind)",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "rag_index",
        "description": "Index live Ghidra MCP analysis into JSpace (functions/decompiles/strings + RE playbook)",
        "inputSchema": {
            "type": "object",
            "properties": {
                "limit": {"type": "integer", "default": 200},
                "decompile_top": {"type": "integer", "default": 40},
                "playbook_only": {"type": "boolean", "default": False},
            },
        },
    },
    {
        "name": "rag_search",
        "description": "Hybrid FTS+vector search over JSpace RE cards",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "top_k": {"type": "integer", "default": 8},
                "kind": {
                    "type": "string",
                    "description": "function|decompile|string|playbook",
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "rag_discover",
        "description": (
            "Build an RE discovery context pack (mental model) for a question: "
            "current selection + JSpace neighbors + suggested MCP moves. "
            "Call this BEFORE answering reverse-engineering questions."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "top_k": {"type": "integer", "default": 8},
                "function": {"type": "string"},
                "decompile": {"type": "string"},
            },
            "required": ["query"],
        },
    },
]


def handle(name: str, args: dict) -> dict | str:
    st = store()
    try:
        if name == "rag_stats":
            return st.stats()
        if name == "rag_index":
            if args.get("playbook_only"):
                return index_playbook_only(st)
            return index_from_mcp(
                st,
                limit=int(args.get("limit") or 200),
                decompile_top=int(args.get("decompile_top") or 40),
            )
        if name == "rag_search":
            return {
                "ok": True,
                "hits": search(
                    st,
                    args["query"],
                    top_k=int(args.get("top_k") or 8),
                    kind=args.get("kind"),
                ),
            }
        if name == "rag_discover":
            return discovery_context(
                st,
                args["query"],
                top_k=int(args.get("top_k") or 8),
                current_function=args.get("function"),
                current_decompile=args.get("decompile"),
            )
        return {"ok": False, "error": f"unknown tool {name}"}
    finally:
        st.close()


def main() -> None:
    # Minimal MCP stdio (tools/list + tools/call) compatible with Cursor.
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        mid = msg.get("id")
        method = msg.get("method")
        if method == "initialize":
            print(
                json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "id": mid,
                        "result": {
                            "protocolVersion": "2024-11-05",
                            "capabilities": {"tools": {}},
                            "serverInfo": {"name": "ghidra-vibe-rag", "version": "0.1.0"},
                        },
                    }
                ),
                flush=True,
            )
        elif method == "notifications/initialized":
            continue
        elif method == "tools/list":
            print(
                json.dumps({"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}}),
                flush=True,
            )
        elif method == "tools/call":
            params = msg.get("params") or {}
            name = params.get("name")
            args = params.get("arguments") or {}
            try:
                result = handle(name, args)
                text = result if isinstance(result, str) else json.dumps(result, indent=2)
                print(
                    json.dumps(
                        {
                            "jsonrpc": "2.0",
                            "id": mid,
                            "result": {
                                "content": [{"type": "text", "text": text}],
                                "isError": False,
                            },
                        }
                    ),
                    flush=True,
                )
            except Exception as e:  # noqa: BLE001
                print(
                    json.dumps(
                        {
                            "jsonrpc": "2.0",
                            "id": mid,
                            "result": {
                                "content": [{"type": "text", "text": str(e)}],
                                "isError": True,
                            },
                        }
                    ),
                    flush=True,
                )
        elif method == "ping":
            print(json.dumps({"jsonrpc": "2.0", "id": mid, "result": {}}), flush=True)


if __name__ == "__main__":
    main()
