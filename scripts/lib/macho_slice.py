"""Thin fat Mach-O binaries to the host arch before Ghidra import."""

from __future__ import annotations

import os
import platform
import shutil
import subprocess
import tempfile
from pathlib import Path

_FAT_MAGICS = {
    b"\xca\xfe\xba\xbe",
    b"\xbe\xba\xfe\xca",
    b"\xca\xfe\xd0\x0d",
    b"\x0d\xd0\xfe\xca",
}


def preferred_arches(machine: str | None = None) -> list[str]:
    host = (machine or platform.machine()).lower()
    if host in {"arm64", "aarch64"}:
        return ["arm64e", "arm64", "x86_64"]
    return ["x86_64", "arm64e", "arm64"]


def is_fat_macho(path: str | os.PathLike[str]) -> bool:
    p = Path(path)
    if not p.is_file():
        return False
    try:
        with p.open("rb") as fh:
            return fh.read(4) in _FAT_MAGICS
    except OSError:
        return False


def thin_macho(path: str | os.PathLike[str]) -> tuple[str, str | None]:
    """Return (path, arch) after thinning. arch is None when the file was already thin."""
    src = Path(path)
    if not src.is_file() or not is_fat_macho(src):
        return str(src), None
    lipo = shutil.which("lipo")
    if not lipo:
        return str(src), None
    try:
        avail = subprocess.check_output([lipo, "-archs", str(src)], text=True).split()
    except (subprocess.CalledProcessError, OSError):
        return str(src), None
    arch = next((a for a in preferred_arches() if a in avail), None)
    if not arch:
        return str(src), None
    out_dir = Path(
        os.environ.get(
            "GHIDRA_VIBE_SLICE_DIR",
            str(Path(tempfile.gettempdir()) / "ghidra-vibe-slices"),
        )
    )
    out_dir.mkdir(parents=True, exist_ok=True)
    dest = out_dir / src.name
    try:
        subprocess.run(
            [lipo, "-thin", arch, str(src), "-output", str(dest)],
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, OSError):
        return str(src), None
    return str(dest), arch
