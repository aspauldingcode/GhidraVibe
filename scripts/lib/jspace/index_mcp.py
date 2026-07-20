"""Index live Ghidra MCP analysis into JSpace (functions, strings, notes)."""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from .store import JSpaceStore

MCP_URL = os.environ.get("GHIDRA_MCP_URL", "http://127.0.0.1:8089").rstrip("/")


def mcp_get(path: str, params: dict[str, str] | None = None, timeout: float = 60) -> str:
    url = f"{MCP_URL}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except urllib.error.URLError as e:
        raise RuntimeError(f"MCP unreachable at {MCP_URL}: {e}") from e


def parse_methods(text: str) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("{") or line.startswith("["):
            continue
        # Common: "name @ address" or "address name"
        if " @ " in line:
            name, _, addr = line.partition(" @ ")
            rows.append({"name": name.strip(), "address": addr.strip().split()[0]})
        elif "\t" in line:
            parts = [p.strip() for p in line.split("\t") if p.strip()]
            if len(parts) >= 2:
                rows.append({"name": parts[0], "address": parts[1]})
        else:
            rows.append({"name": line.split()[0], "address": ""})
    return rows


def decompile_one(name: str, timeout: float = 90) -> str:
    try:
        return mcp_get("/decompile", {"name": name}, timeout=timeout)
    except Exception:  # noqa: BLE001
        return ""


def index_from_mcp(
    store: JSpaceStore,
    *,
    program: str = "",
    limit: int = 200,
    decompile_top: int = 40,
    include_strings: bool = True,
) -> dict[str, Any]:
    methods_raw = mcp_get("/methods")
    methods = parse_methods(methods_raw)[:limit]
    n_fn = 0
    n_dec = 0
    for i, m in enumerate(methods):
        name = m["name"]
        addr = m.get("address") or ""
        body = f"Function {name} at {addr}"
        store.upsert(
            chunk_id=f"fn:{addr or name}",
            kind="function",
            name=name,
            address=addr,
            program=program,
            text=body,
            meta={"source": "methods"},
        )
        n_fn += 1
        if i < decompile_top:
            dec = decompile_one(name)
            if dec and "error" not in dec.lower()[:40]:
                store.upsert(
                    chunk_id=f"dec:{addr or name}",
                    kind="decompile",
                    name=name,
                    address=addr,
                    program=program,
                    text=dec[:8000],
                    meta={"source": "decompile"},
                )
                n_dec += 1

    n_str = 0
    if include_strings:
        try:
            raw = mcp_get("/list_strings") if False else mcp_get("/strings")
        except Exception:  # noqa: BLE001
            try:
                raw = mcp_get("/listStrings")
            except Exception:  # noqa: BLE001
                raw = ""
        if raw:
            for j, line in enumerate(raw.splitlines()[:500]):
                s = line.strip()
                if len(s) < 4:
                    continue
                store.upsert(
                    chunk_id=f"str:{j}:{hash(s) & 0xFFFFFFFF:x}",
                    kind="string",
                    name=s[:80],
                    address="",
                    program=program,
                    text=s[:2000],
                    meta={"source": "strings"},
                )
                n_str += 1

    # Seed RE playbook cards (always available offline)
    for key, text in PLAYBOOK.items():
        store.upsert(
            chunk_id=f"playbook:{key}",
            kind="playbook",
            name=key,
            text=text,
            meta={"source": "jspace-playbook"},
        )

    return {
        "ok": True,
        "functions": n_fn,
        "decompiles": n_dec,
        "strings": n_str,
        "playbook": len(PLAYBOOK),
        "stats": store.stats(),
    }


def index_playbook_only(store: JSpaceStore) -> dict[str, Any]:
    for key, text in PLAYBOOK.items():
        store.upsert(
            chunk_id=f"playbook:{key}",
            kind="playbook",
            name=key,
            text=text,
            meta={"source": "jspace-playbook"},
        )
    return {"ok": True, "playbook": len(PLAYBOOK), "stats": store.stats()}


PLAYBOOK: dict[str, str] = {
    "triage": (
        "RE triage loop: (1) list interesting strings/imports (2) locate xrefs "
        "(3) decompile callers (4) rename with role (5) follow data flow to sinks "
        "(crypto/network/file). Prefer small confirmed facts."
    ),
    "objc": (
        "ObjC/Swift: find objc_msgSend stubs, recover selectors from __objc_methname, "
        "map class clusters, watch retain/release imbalance, check Swift demangler names."
    ),
    "dyld": (
        "DSC workflow: open on-device dyld_shared_cache → DSC Index → load one framework "
        "(AppKit/SkyLight/…) via DyldCacheFileSystem with Apple local symbols. Do not ipsw-extract."
    ),
    "crypto": (
        "Crypto hunt: CommonCrypto/CCCrypt, SecKey, AES/SHA constants, key material in "
        "stack buffers, wrap/unwrap APIs, compare to known KDF patterns."
    ),
    "auth": (
        "Auth path: password/token strings → validators → Keychain/LAContext → entitlement "
        "checks → network login. Note bypass candidates near strcmp/memcmp."
    ),
    "ui-windowing": (
        "Windowing: UI frameworks → WindowServer (e.g. AppKit/SkyLight as examples). Track CGS/SLS symbols, event taps, "
        "display geometry, and security-sensitive screen capture APIs."
    ),
}
