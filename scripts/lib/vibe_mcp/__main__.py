"""python -m vibe_mcp [--host 127.0.0.1] [--port 8092]"""

from __future__ import annotations

import argparse
import os

from .server import serve


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="vibe_mcp", description="GhidraVibe MCP extension HTTP server")
    p.add_argument("--host", default=os.environ.get("GHIDRA_VIBE_MCP_EXT_HOST", "127.0.0.1"))
    p.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("GHIDRA_VIBE_MCP_EXT_PORT", "8092")),
    )
    args = p.parse_args(argv)
    serve(host=args.host, port=args.port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
