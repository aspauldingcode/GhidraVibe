#!/usr/bin/env python3
"""CLI entry for ghidra-vibe-jspace."""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# Allow `python -m jspace.cli` from scripts/lib
if __name__ == "__main__" and __package__ is None:
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from jspace.index_mcp import index_from_mcp, index_playbook_only  # noqa: E402
from jspace.retrieve import discovery_context, search  # noqa: E402
from jspace.store import JSpaceStore  # noqa: E402


def default_db() -> Path:
    env = os.environ.get("GHIDRA_VIBE_JSPACE_DB")
    if env:
        return Path(env)
    # scripts/lib/jspace/cli.py → parents[3] == repo root when running from checkout
    here = Path(__file__).resolve()
    root = here.parents[3] if len(here.parents) >= 4 else Path.cwd()
    return root / ".ghidra-vibe-jspace" / "jspace.sqlite"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="JSpace RE RAG for GhidraVibe")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def add_db(p: argparse.ArgumentParser) -> None:
        p.add_argument("--db", type=Path, default=None, help="JSpace sqlite path")

    p_init = sub.add_parser("init", help="Seed RE playbook cards")
    add_db(p_init)
    p_idx = sub.add_parser("index", help="Index from live Ghidra MCP")
    add_db(p_idx)
    p_idx.add_argument("--limit", type=int, default=200)
    p_idx.add_argument("--decompile-top", type=int, default=40)
    p_idx.add_argument("--playbook-only", action="store_true")
    p_idx.add_argument("--program", default="")

    p_s = sub.add_parser("search", help="Hybrid search")
    add_db(p_s)
    p_s.add_argument("query")
    p_s.add_argument("--top", type=int, default=8)
    p_s.add_argument("--kind", default=None)

    p_d = sub.add_parser("discover", help="Discovery context pack for the agent")
    add_db(p_d)
    p_d.add_argument("query")
    p_d.add_argument("--top", type=int, default=8)
    p_d.add_argument("--function", default=None)
    p_d.add_argument("--decompile-file", type=Path, default=None)

    p_st = sub.add_parser("stats")
    add_db(p_st)

    args = ap.parse_args(argv)
    db = getattr(args, "db", None) or default_db()
    store = JSpaceStore(db)
    try:
        if args.cmd == "init":
            print(json.dumps(index_playbook_only(store), indent=2))
        elif args.cmd == "index":
            if args.playbook_only:
                print(json.dumps(index_playbook_only(store), indent=2))
            else:
                print(
                    json.dumps(
                        index_from_mcp(
                            store,
                            program=args.program,
                            limit=args.limit,
                            decompile_top=args.decompile_top,
                        ),
                        indent=2,
                    )
                )
        elif args.cmd == "search":
            print(json.dumps(search(store, args.query, top_k=args.top, kind=args.kind), indent=2))
        elif args.cmd == "discover":
            dec = None
            if args.decompile_file and args.decompile_file.is_file():
                dec = args.decompile_file.read_text(errors="replace")
            print(
                discovery_context(
                    store,
                    args.query,
                    top_k=args.top,
                    current_function=args.function,
                    current_decompile=dec,
                )
            )
        elif args.cmd == "stats":
            print(json.dumps(store.stats(), indent=2))
        return 0
    finally:
        store.close()


if __name__ == "__main__":
    raise SystemExit(main())
