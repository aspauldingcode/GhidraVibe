"""Plist / Info.plist / mobileprovision helpers (Malimite PlistUtils parity)."""

from __future__ import annotations

import json
import plistlib
import subprocess
from pathlib import Path
from typing import Any, Dict, Optional, Union


PathLike = Union[str, Path]


def is_binary_plist(data: bytes) -> bool:
    """True when bytes start with the Apple binary plist magic ``bplist``."""
    if not data or len(data) < 6:
        return False
    return data[:6] == b"bplist"


def decode_plist(path: PathLike) -> Any:
    """Decode a plist file to a Python object.

    Tries ``plistlib`` first; falls back to ``plutil -convert json`` when available.
    """
    p = Path(path)
    raw = p.read_bytes()
    try:
        return plistlib.loads(raw)
    except Exception:
        pass

    # plutil fallback (macOS / Cross-platform installs)
    try:
        proc = subprocess.run(
            ["plutil", "-convert", "json", "-o", "-", str(p)],
            check=False,
            capture_output=True,
        )
        if proc.returncode == 0 and proc.stdout:
            return json.loads(proc.stdout.decode("utf-8"))
    except FileNotFoundError:
        pass

    # Last resort: XML/text already readable as UTF-8 plist
    try:
        return plistlib.loads(raw)
    except Exception as exc:
        raise ValueError(f"Unable to decode plist: {p}") from exc


def parse_info_plist(app_path: PathLike) -> Dict[str, Optional[str]]:
    """Read ``Info.plist`` under an ``.app`` and return key bundle fields."""
    app = Path(app_path)
    info = app / "Info.plist"
    if not info.is_file():
        # Some layouts nest Contents/Info.plist (macOS bundles)
        alt = app / "Contents" / "Info.plist"
        info = alt if alt.is_file() else info
    if not info.is_file():
        return {
            "CFBundleExecutable": None,
            "CFBundleIdentifier": None,
            "CFBundleName": None,
        }
    data = decode_plist(info)
    if not isinstance(data, dict):
        return {
            "CFBundleExecutable": None,
            "CFBundleIdentifier": None,
            "CFBundleName": None,
        }

    def _s(key: str) -> Optional[str]:
        val = data.get(key)
        if val is None:
            return None
        return str(val)

    return {
        "CFBundleExecutable": _s("CFBundleExecutable"),
        "CFBundleIdentifier": _s("CFBundleIdentifier"),
        "CFBundleName": _s("CFBundleName"),
    }


def extract_mobileprovision_xml(data: bytes) -> str:
    """Unwrap ``.mobileprovision`` CMS (Malimite BouncyCastle CMS parity).

    Order:
      1. macOS ``security cms -D`` (native CryptoKit/Security stack — not BouncyCastle)
      2. OpenSSL ``smime -verify -noverify`` if present
      3. Embedded ``<?xml … </plist>`` byte scan (unsigned / cleartext payload)
    """
    if not data:
        raise ValueError("empty mobileprovision data")

    # 1) Apple Security framework CLI
    try:
        proc = subprocess.run(
            ["security", "cms", "-D", "-i", "/dev/stdin"],
            input=data,
            check=False,
            capture_output=True,
        )
        if proc.returncode == 0 and proc.stdout and b"<?xml" in proc.stdout:
            return proc.stdout.decode("utf-8", errors="replace")
    except FileNotFoundError:
        pass

    # 2) OpenSSL CMS/SMIME
    try:
        proc = subprocess.run(
            ["openssl", "smime", "-inform", "DER", "-verify", "-noverify"],
            input=data,
            check=False,
            capture_output=True,
        )
        if proc.returncode == 0 and proc.stdout and b"<?xml" in proc.stdout:
            return proc.stdout.decode("utf-8", errors="replace")
    except FileNotFoundError:
        pass

    # 3) Cleartext XML embedded in the signed blob (Malimite fallback)
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        text = data.decode("latin-1", errors="replace")

    start = text.find("<?xml")
    if start < 0:
        raw_start = data.find(b"<?xml")
        if raw_start < 0:
            raise ValueError("Failed to locate XML plist in mobileprovision")
        raw_end = data.find(b"</plist>", raw_start)
        if raw_end < 0:
            raise ValueError("Failed to locate </plist> in mobileprovision")
        return data[raw_start : raw_end + len(b"</plist>")].decode("utf-8", errors="replace")

    end = text.find("</plist>", start)
    if end < 0:
        raise ValueError("Failed to locate </plist> in mobileprovision")
    return text[start : end + len("</plist>")]


def decode_mobileprovision_file(path: PathLike) -> Any:
    """CMS-unwrap a ``.mobileprovision`` and return the plist as a Python object."""
    xml = extract_mobileprovision_xml(Path(path).read_bytes())
    return plistlib.loads(xml.encode("utf-8"))