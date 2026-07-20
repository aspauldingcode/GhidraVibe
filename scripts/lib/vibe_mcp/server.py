"""HTTP server for GhidraVibe MCP extension (default :8092).

GhidraMCP-style paths: GET/POST /<tool_name> with JSON body or query params.
Also: /check_connection, /mcp/schema, /tools/list, POST /tools/call
"""

from __future__ import annotations

import json
import os
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from . import __version__
from .handlers import TOOL_HANDLERS, TOOL_SCHEMA, dispatch


def _parse_args(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    parsed = urllib.parse.urlparse(handler.path)
    qs = {k: v[0] if len(v) == 1 else v for k, v in urllib.parse.parse_qs(parsed.query).items()}
    length = int(handler.headers.get("Content-Length") or 0)
    body: dict[str, Any] = {}
    if length > 0:
        raw = handler.rfile.read(length)
        if raw:
            try:
                loaded = json.loads(raw.decode())
                if isinstance(loaded, dict):
                    body = loaded
                else:
                    body = {"value": loaded}
            except json.JSONDecodeError:
                body = {"raw": raw.decode(errors="replace")}
    return {**qs, **body}


class VibeMCPHandler(BaseHTTPRequestHandler):
    server_version = f"GhidraVibeMCPExt/{__version__}"

    def log_message(self, fmt: str, *args: Any) -> None:
        if os.environ.get("GHIDRA_VIBE_MCP_EXT_DEBUG"):
            super().log_message(fmt, *args)

    def _send(self, code: int, obj: Any) -> None:
        data = json.dumps(obj, indent=2, default=str).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def _route(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.strip("/") or ""
        if path in ("", "check_connection", "check", "health"):
            self._send(200, {"ok": True, "service": "ghidra-vibe-mcp-ext", "version": __version__})
            return
        if path in ("mcp/schema", "schema", "tools/list"):
            self._send(200, {"ok": True, "tools": TOOL_SCHEMA, "count": len(TOOL_SCHEMA)})
            return
        if path == "tools/call":
            args = _parse_args(self)
            name = args.pop("name", None) or args.pop("tool", None)
            if not name:
                self._send(400, {"ok": False, "error": "name required"})
                return
            inner = args.pop("arguments", None)
            if isinstance(inner, dict):
                args = {**args, **inner}
            self._send(200, dispatch(str(name), args))
            return
        # Direct tool path
        name = path.replace("/", "_")
        if name in TOOL_HANDLERS:
            self._send(200, dispatch(name, _parse_args(self)))
            return
        # Also allow hyphenated
        alt = path.replace("-", "_")
        if alt in TOOL_HANDLERS:
            self._send(200, dispatch(alt, _parse_args(self)))
            return
        self._send(404, {"ok": False, "error": f"unknown path /{path}", "hint": "/mcp/schema"})

    def do_GET(self) -> None:  # noqa: N802
        self._route()

    def do_POST(self) -> None:  # noqa: N802
        self._route()

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()


def serve(host: str = "127.0.0.1", port: int = 8092) -> None:
    httpd = ThreadingHTTPServer((host, port), VibeMCPHandler)
    print(f"ghidra-vibe-mcp-ext listening on http://{host}:{port}", flush=True)
    print(f"schema: http://{host}:{port}/mcp/schema  tools={len(TOOL_SCHEMA)}", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("shutting down", flush=True)
        httpd.shutdown()
