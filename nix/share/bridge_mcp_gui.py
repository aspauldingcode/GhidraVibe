#!/usr/bin/env python3
"""MCP stdio bridge for GhidraVibe GuiControlServer (HTTP JSON)."""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

GUI_URL = os.environ.get("GHIDRA_VIBE_GUI_URL", "http://127.0.0.1:8091").rstrip("/")


def http(method: str, path: str, body: dict | None = None) -> dict:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"{GUI_URL}{path}",
        data=data,
        method=method,
        headers={"Content-Type": "application/json"} if data else {},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw else {"ok": True}
    except urllib.error.HTTPError as e:
        return {"ok": False, "error": e.read().decode() or str(e)}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": str(e)}


TOOLS = [
    {
        "name": "gui_health",
        "description": "Check GhidraVibe GuiControlServer health",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "gui_state",
        "description": "Get GhidraVibe UI state (sidebar, selection, status)",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "gui_navigate",
        "description": "Navigate sidebar pane",
        "inputSchema": {
            "type": "object",
            "properties": {"pane": {"type": "string"}},
            "required": ["pane"],
        },
    },
    {
        "name": "gui_select_function",
        "description": "Select a function by name, address, or id",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "address": {"type": "string"},
                "id": {"type": "string"},
            },
        },
    },
    {
        "name": "gui_search",
        "description": "Set function search query",
        "inputSchema": {
            "type": "object",
            "properties": {"query": {"type": "string"}},
            "required": ["query"],
        },
    },
    {
        "name": "gui_action",
        "description": "Run a toolbar/action id (mcp_health, fetch_functions, decompile, dyld_open, …)",
        "inputSchema": {
            "type": "object",
            "properties": {"id": {"type": "string"}},
            "required": ["id"],
        },
    },
    {
        "name": "dyld_list_caches",
        "description": "List detected dyld shared cache paths",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "dyld_list_images",
        "description": "List/filter images in the dyld shared cache",
        "inputSchema": {
            "type": "object",
            "properties": {"query": {"type": "string"}},
        },
    },
    {
        "name": "dyld_open_image",
        "description": "Import and analyze an image from the dyld shared cache",
        "inputSchema": {
            "type": "object",
            "properties": {"image": {"type": "string"}},
            "required": ["image"],
        },
    },
    {
        "name": "agent_send",
        "description": "Send a message to the GhidraVibe Agent sidebar (JSpace + local LLM tool loop)",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "message": {"type": "string"},
            },
        },
    },
    {
        "name": "agent_status",
        "description": "Agent sidebar status (backend, busy, pending edits, last message)",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "agent_playbook",
        "description": "Run Autonomous RE playbook (budgeted rename/comment pass)",
        "inputSchema": {
            "type": "object",
            "properties": {
                "budget": {"type": "integer"},
                "apply": {"type": "boolean"},
            },
        },
    },
    {
        "name": "agent_rename",
        "description": "Rename a function via in-process engine",
        "inputSchema": {
            "type": "object",
            "properties": {
                "address": {"type": "string"},
                "name": {"type": "string"},
                "new_name": {"type": "string"},
            },
            "required": ["new_name"],
        },
    },
    {
        "name": "agent_comment",
        "description": "Set plate/EOL comment via in-process engine",
        "inputSchema": {
            "type": "object",
            "properties": {
                "address": {"type": "string"},
                "comment": {"type": "string"},
                "kind": {"type": "string"},
            },
            "required": ["comment"],
        },
    },
]


def handle_tool(name: str, args: dict) -> dict:
    if name == "gui_health":
        return http("GET", "/health")
    if name == "gui_state":
        return http("GET", "/state")
    if name == "gui_navigate":
        return http("POST", "/navigate", {"pane": args.get("pane", "")})
    if name == "gui_select_function":
        return http("POST", "/select_function", args)
    if name == "gui_search":
        return http("POST", "/search", {"query": args.get("query", "")})
    if name == "gui_action":
        return http("POST", "/action", {"id": args.get("id", "")})
    if name == "dyld_list_caches":
        return http("GET", "/dyld/caches")
    if name == "dyld_list_images":
        return http("POST", "/dyld/list", {"query": args.get("query", "")})
    if name == "dyld_open_image":
        return http("POST", "/dyld/open", {"image": args.get("image", "")})
    if name == "agent_send":
        text = args.get("text") or args.get("message") or ""
        return http("POST", "/agent/send", {"text": text})
    if name == "agent_status":
        return http("GET", "/agent/status")
    if name == "agent_playbook":
        return http(
            "POST",
            "/agent/playbook",
            {
                "budget": args.get("budget", 8),
                "apply": args.get("apply", True),
            },
        )
    if name == "agent_rename":
        return http("POST", "/agent/rename", args)
    if name == "agent_comment":
        return http("POST", "/agent/comment", args)
    return {"ok": False, "error": f"unknown tool {name}"}


def main() -> None:
    # Minimal MCP-ish JSON-RPC over stdio (initialize + tools/list + tools/call)
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
                "serverInfo": {"name": "ghidra-vibe-gui", "version": "0.1.0"},
            }
        elif method == "notifications/initialized":
            continue
        elif method == "tools/list":
            result = {"tools": TOOLS}
        elif method == "tools/call":
            params = msg.get("params") or {}
            out = handle_tool(params.get("name", ""), params.get("arguments") or {})
            result = {
                "content": [{"type": "text", "text": json.dumps(out, indent=2)}],
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
