#!/usr/bin/env python3
"""Headless-compat overlay for the stock bethington GhidraMCP FastMCP bridge.

Stock ``import_file`` / ``open_program`` / ``list_project_files`` hit GUI-only
HTTP paths (``PluginTool not available``). Headless GhidraMCPHeadlessServer
exposes ``load_program`` and ``load_program_from_project``. This wrapper loads
the stock bridge and remaps those tools before FastMCP starts.
"""

from __future__ import annotations

import importlib.util
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
STOCK = HERE / "bridge_mcp_ghidra_stock.py"
_FAT = {
    b"\xca\xfe\xba\xbe",
    b"\xbe\xba\xfe\xca",
    b"\xca\xfe\xd0\x0d",
    b"\x0d\xd0\xfe\xca",
}


def _looks_gui_only(text: str) -> bool:
    low = (text or "").lower()
    return (
        "requires gui" in low
        or "plugintool not available" in low
        or "plugin tool not available" in low
    )


def _pick(data: dict | None, params: dict | None, *keys: str) -> str:
    for src in (data or {}, params or {}):
        for key in keys:
            val = src.get(key)
            if val is not None and str(val).strip():
                return str(val).strip()
    return ""


def _program_path(raw: str) -> str:
    s = (raw or "").strip()
    if not s:
        return s
    return s if s.startswith("/") else f"/{s}"


def _thin_file(path: str) -> str:
    src = Path(path)
    if not src.is_file():
        return path
    try:
        with src.open("rb") as fh:
            if fh.read(4) not in _FAT:
                return path
    except OSError:
        return path
    lipo = shutil.which("lipo")
    if not lipo:
        return path
    try:
        avail = subprocess.check_output([lipo, "-archs", str(src)], text=True).split()
    except (subprocess.CalledProcessError, OSError):
        return path
    host = platform.machine().lower()
    prefer = (
        ["arm64e", "arm64", "x86_64"]
        if host in {"arm64", "aarch64"}
        else ["x86_64", "arm64e", "arm64"]
    )
    arch = next((a for a in prefer if a in avail), None)
    if not arch:
        return path
    dest_dir = Path(
        os.environ.get(
            "GHIDRA_VIBE_SLICE_DIR",
            str(Path(tempfile.gettempdir()) / "ghidra-vibe-slices"),
        )
    )
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / src.name
    try:
        subprocess.run(
            [lipo, "-thin", arch, str(src), "-output", str(dest)],
            check=True,
            capture_output=True,
        )
    except (subprocess.CalledProcessError, OSError):
        return path
    return str(dest)


def _remap_payload(name: str, data: dict | None, params: dict | None) -> tuple[str, str, dict]:
    """Return (method, endpoint, payload) for a remapped GUI-only tool."""
    if name == "import_file":
        raw = _pick(data, params, "file", "path", "filename")
        p = Path(raw) if raw else None
        if p is not None and p.is_file():
            return "POST", "load_program", {"file": _thin_file(str(p))}
        if raw:
            return "POST", "load_program_from_project", {"path": _program_path(raw)}
        return "POST", "load_program", {"file": raw}
    if name == "open_program":
        raw = _pick(data, params, "path", "program", "name", "program_path")
        p = Path(raw) if raw else None
        if p is not None and p.is_file():
            return "POST", "load_program", {"file": _thin_file(str(p))}
        return "POST", "load_program_from_project", {"path": _program_path(raw)}
    if name == "list_project_files":
        return "GET", "list_open_programs", params or {}
    return "GET", name, params or {}


def _endpoint_name(endpoint: str) -> str:
    return endpoint.strip("/").split("/")[-1]


def _load_stock():
    if not STOCK.is_file():
        raise SystemExit(f"stock bridge missing: {STOCK}")
    spec = importlib.util.spec_from_file_location("bridge_mcp_ghidra_stock", STOCK)
    if spec is None or spec.loader is None:
        raise SystemExit(f"cannot load stock bridge: {STOCK}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["bridge_mcp_ghidra_stock"] = mod
    spec.loader.exec_module(mod)
    return mod


def main() -> None:
    mod = _load_stock()
    orig_get = mod.dispatch_get
    orig_post = mod.dispatch_post

    def _try_remap(method: str, endpoint: str, data: dict | None, params: dict | None, first: str) -> str:
        if not _looks_gui_only(first):
            return first
        name = _endpoint_name(endpoint)
        if name not in {"import_file", "open_program", "list_project_files"}:
            return first
        alt_method, alt_ep, payload = _remap_payload(name, data, params)
        if alt_method == "GET":
            return orig_get(alt_ep, params=payload or None)
        return orig_post(alt_ep, payload)

    def dispatch_get(endpoint: str, params: dict | None = None, retries: int = 3) -> str:
        text = orig_get(endpoint, params=params, retries=retries)
        return _try_remap("GET", endpoint, None, params, text)

    def dispatch_post(
        endpoint: str, data: dict, retries: int = 3, query_params: dict | None = None
    ) -> str:
        text = orig_post(endpoint, data, retries=retries, query_params=query_params)
        return _try_remap("POST", endpoint, data, query_params, text)

    mod.dispatch_get = dispatch_get
    mod.dispatch_post = dispatch_post
    # Also remap if a future stock build routes import_file to GET.
    if hasattr(mod, "main"):
        mod.main()
        return
    raise SystemExit("stock bridge has no main()")


if __name__ == "__main__":
    main()
