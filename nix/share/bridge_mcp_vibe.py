#!/usr/bin/env python3
"""MCP stdio bridge for GhidraVibe extension HTTP (Malimite/dyld/rules/RAG/nav)."""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

VIBE_URL = os.environ.get("GHIDRA_VIBE_MCP_EXT_URL", "http://127.0.0.1:8092").rstrip("/")


def http(method: str, path: str, body: dict | None = None) -> dict:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"{VIBE_URL}{path}",
        data=data,
        method=method,
        headers={"Content-Type": "application/json"} if data else {},
    )
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw else {"ok": True}
    except urllib.error.HTTPError as e:
        return {"ok": False, "error": e.read().decode() or str(e)}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": str(e)}


def list_tools() -> list:
    schema = http("GET", "/mcp/schema")
    return schema.get("tools") or []


def handle_tool(name: str, args: dict) -> dict:
    return http("POST", f"/{name}", args or {})


def main() -> None:
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
            result = {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "ghidra-vibe", "version": "0.1.0"},
            }
        elif method == "notifications/initialized":
            continue
        elif method == "tools/list":
            result = {"tools": list_tools()}
        elif method == "tools/call":
            params = msg.get("params") or {}
            out = handle_tool(params.get("name", ""), params.get("arguments") or {})
            result = {
                "content": [{"type": "text", "text": json.dumps(out, indent=2, default=str)}],
                "isError": not out.get("ok", True) and "error" in out,
            }
        elif method == "ping":
            result = {}
        else:
            result = {"error": f"unsupported {method}"}
        sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": result}) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
