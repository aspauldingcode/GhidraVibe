"""Swift name demangling (Malimite DemangleSwift + ``swift demangle`` CLI)."""

from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class DemangledName:
    class_name: str
    full_method_name: str

    def __str__(self) -> str:
        if self.class_name and self.full_method_name:
            return f"{self.class_name}.{self.full_method_name}"
        return self.class_name or self.full_method_name or ""


def _find_next_number_index(s: str) -> int:
    for i, ch in enumerate(s):
        if ch.isdigit() and ch != "0":
            return i
    return -1


def _extract_number(s: str) -> int:
    number_chars: list[str] = []
    leading_zero_skipped = False
    for ch in s:
        if ch.isdigit():
            if ch != "0" or leading_zero_skipped:
                number_chars.append(ch)
                leading_zero_skipped = True
        else:
            break
    return int("".join(number_chars)) if number_chars else 0


def demangle_swift_name(mangled: str) -> Optional[DemangledName]:
    """Port of Malimite ``DemangleSwift.demangleSwiftName`` (prefix ``_$s``)."""
    if mangled is None or not mangled.startswith("_$s"):
        return None

    try:
        remaining = mangled[3:]
        class_name_length = _extract_number(remaining)
        length_digits = len(str(class_name_length))
        class_name = remaining[length_digits : length_digits + class_name_length]
        remaining = remaining[length_digits + class_name_length :]

        method_parts: list[str] = []
        while remaining:
            number_index = _find_next_number_index(remaining)
            if number_index == -1:
                break
            remaining_after = remaining[number_index:]
            length = _extract_number(remaining_after)
            number_length = len(str(length))
            segment = remaining_after[number_length : number_length + length]
            method_parts.append(segment)
            remaining = remaining_after[number_length + length :]

        return DemangledName(class_name, "".join(method_parts))
    except Exception:
        return None


def demangle_via_swift_cli(name: str) -> Optional[str]:
    """Call ``swift demangle`` when the toolchain is on PATH."""
    if not name:
        return None
    swift = shutil.which("swift")
    if not swift:
        return None
    try:
        proc = subprocess.run(
            [swift, "demangle", name],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    out = (proc.stdout or "").strip()
    if not out:
        return None
    # Typical: "_$s… ---> Module.Type.method(...)"
    if "--->" in out:
        out = out.split("--->", 1)[1].strip()
    # First line only
    return out.splitlines()[0].strip() or None


def demangle_best(name: str) -> str:
    """Prefer ``swift demangle``; fall back to built-in Malimite-style parser."""
    if not name:
        return name
    cli = demangle_via_swift_cli(name)
    if cli and cli != name:
        return cli
    parsed = demangle_swift_name(name)
    if parsed is not None:
        text = str(parsed)
        if text:
            return text
    return name
