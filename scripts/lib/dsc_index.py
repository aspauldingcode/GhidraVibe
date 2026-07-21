#!/usr/bin/env python3
"""On-device dyld shared cache image index (IDA-like DSC Index, no extract).

Platform support:
  - macOS: on-device cache at /System/Library/dyld/
  - Linux: ipsw-extracted cache (via GHIDRA_VIBE_IPSW_CACHE)

Parses the system cache header / sibling .map file. Never shells out to ipsw.
"""
from __future__ import annotations

import argparse
import os
import platform
import struct
import sys
from pathlib import Path

# macOS on-device cache locations
CACHE_CANDIDATES_MACOS = (
    "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e",
    "/System/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e",
    "/System/Library/dyld/dyld_shared_cache_arm64e",
    "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_x86_64",
    "/System/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_x86_64",
    "/System/Library/dyld/dyld_shared_cache_x86_64",
)

# Modern dyld_cache_header: imagesOffset/imagesCount at 0x1c0 (macOS 13+)
IMAGES_OFFSET_OFF = 0x1C0
# Legacy (pre-imagesOffset move)
IMAGES_OFFSET_OLD_OFF = 0x18


def find_cache() -> Path:
    """Locate dyld shared cache: on-device (macOS) or ipsw-extracted (Linux)."""
    system = platform.system()
    
    if system == "Linux":
        # Linux: check ipsw-extracted cache locations
        ipsw_cache = os.environ.get("GHIDRA_VIBE_IPSW_CACHE")
        if ipsw_cache:
            p = Path(ipsw_cache)
            if p.is_file():
                return p
        
        # Check default Linux locations
        home = Path.home()
        xdg_data = Path(os.environ.get("XDG_DATA_HOME", home / ".local" / "share"))
        linux_candidates = [
            home / ".local" / "share" / "ghidra-vibe" / "ipsw-cache" / "dyld_shared_cache_arm64e",
            home / "Documents" / "GhidraVibe" / "ipsw-cache" / "dyld_shared_cache_arm64e",
            xdg_data / "ghidra-vibe" / "ipsw-cache" / "dyld_shared_cache_arm64e",
        ]
        for c in linux_candidates:
            if c.is_file():
                return c
        
        raise FileNotFoundError(
            "No ipsw cache found on Linux. Run: ghidra-vibe-dyld setup-ipsw\n"
            "Or set GHIDRA_VIBE_IPSW_CACHE to your extracted cache path."
        )
    
    # macOS: on-device cache
    for c in CACHE_CANDIDATES_MACOS:
        p = Path(c)
        if p.is_file():
            return p
    
    raise FileNotFoundError("No on-device dyld shared cache found")



def _read_cstring(data: bytes, off: int) -> str:
    if off < 0 or off >= len(data):
        return ""
    end = data.find(b"\x00", off)
    if end < 0:
        end = min(len(data), off + 1024)
    return data[off:end].decode("utf-8", errors="replace")


def list_from_header(cache: Path) -> list[tuple[int, str]]:
    """Return (unslid_address, install_path) from dyld_cache_image_info[].

    The macOS cryptex *base* cache is a small header (~MB) with paths inline;
    split subcaches are not needed for the index.
    """
    # Cap read — base header + image table + path pool fits in a few MB.
    max_bytes = int(os.environ.get("GHIDRA_VIBE_DSC_INDEX_BYTES", str(8 * 1024 * 1024)))
    with cache.open("rb") as fh:
        data = fh.read(max_bytes)
    if not data.startswith(b"dyld_v1"):
        raise ValueError(f"Not a dyld shared cache: {cache}")

    images_offset, images_count = struct.unpack_from("<II", data, IMAGES_OFFSET_OFF)
    if images_offset == 0 or images_count == 0:
        images_offset, images_count = struct.unpack_from("<II", data, IMAGES_OFFSET_OLD_OFF)
    if images_offset == 0 or images_count == 0:
        raise ValueError("Could not locate images table in cache header")

    out: list[tuple[int, str]] = []
    for i in range(images_count):
        off = images_offset + i * 32
        if off + 32 > len(data):
            break
        address, _mod, _inode, path_off, _pad = struct.unpack_from("<QQQII", data, off)
        path = _read_cstring(data, path_off)
        if path:
            out.append((address, path))
    if not out:
        raise ValueError("Parsed zero image paths from header")
    return out


def list_from_map(cache: Path) -> list[tuple[int, str]]:
    """Fallback: sibling .map text (paths only; address=0)."""
    map_path = Path(str(cache) + ".map")
    if not map_path.is_file():
        raise FileNotFoundError(map_path)
    out: list[tuple[int, str]] = []
    for line in map_path.read_text(errors="replace").splitlines():
        line = line.strip()
        if line.startswith("/") and not line.startswith("//"):
            out.append((0, line))
    return out


def list_images(cache: Path | None = None) -> list[tuple[int, str]]:
    cache = cache or find_cache()
    try:
        return list_from_header(cache)
    except Exception as exc:  # noqa: BLE001 — fall back to .map
        try:
            return list_from_map(cache)
        except Exception as exc2:  # noqa: BLE001
            raise RuntimeError(f"header={exc}; map={exc2}") from exc2


def resolve_image(query: str, cache: Path | None = None) -> str:
    """Resolve short name (AppKit) or substring to a full install path."""
    q = query.strip()
    if q.startswith("/") and any(q == p for _, p in list_images(cache)):
        return q
    aliases = {
        "appkit": "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit",
        "skylight": "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
    }
    key = q.lower().removesuffix(".framework")
    if key in aliases:
        want = aliases[key]
        for _, p in list_images(cache):
            if p == want:
                return p
        return want
    matches = [p for _, p in list_images(cache) if q.lower() in p.lower()]
    if not matches:
        raise LookupError(f"No DSC image matching {query!r}")
    # Prefer exact basename / shortest path
    matches.sort(key=lambda p: (0 if p.rstrip("/").endswith("/" + q) else 1, len(p)))
    return matches[0]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="On-device DSC image index")
    ap.add_argument("command", choices=("find-cache", "list", "resolve"))
    ap.add_argument("--cache", type=Path, default=None)
    ap.add_argument("--query", default="")
    ap.add_argument("--image", default="")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    if args.command == "find-cache":
        print(find_cache())
        return 0

    cache = args.cache or find_cache()
    if args.command == "list":
        rows = list_images(cache)
        q = args.query.lower()
        for addr, path in rows:
            if q and q not in path.lower():
                continue
            if args.json:
                print(f'{{"address":{addr},"path":{path!r}}}')
            else:
                print(path)
        return 0

    if args.command == "resolve":
        img = args.image or args.query
        if not img:
            print("--image required", file=sys.stderr)
            return 2
        print(resolve_image(img, cache))
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
