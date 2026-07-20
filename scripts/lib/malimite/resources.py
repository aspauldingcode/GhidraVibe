"""Resource discovery and string harvest (Malimite ResourceParser parity)."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Iterable, List, Protocol, Union

from . import plist as plist_mod

PathLike = Union[str, Path]

# Malimite ResourceParser patterns + .car (Apple asset catalog / Assets.car)
RESOURCE_PATTERNS: List[re.Pattern[str]] = [
    re.compile(r".*\.plist$"),
    re.compile(r".*\.strings$"),
    re.compile(r".*\.json$"),
    re.compile(r".*\.xml$"),
    re.compile(r".*\.mobileprovision$"),
    re.compile(r".*\.storyboardc$"),
    re.compile(r".*\.xcassets$"),
    re.compile(r".*\.nib$"),
    re.compile(r".*\.xib$"),
    re.compile(r".*\.car$"),
]

_PRINTABLE_SPLIT = re.compile(r"[^\x20-\x7E]+")
_MIN_SEGMENT = 4


class ResourceDB(Protocol):
    def insert_resource_string(self, resource_id: str, value: str, type_: str) -> None: ...


def is_resource(name: str) -> bool:
    for pattern in RESOURCE_PATTERNS:
        if pattern.match(name):
            return True
    return False


def resource_type(file_name: str) -> str:
    lower = file_name.lower()
    if lower.endswith(".plist"):
        return "plist"
    if lower.endswith(".strings"):
        return "strings"
    if lower.endswith(".json"):
        return "json"
    if lower.endswith(".xml"):
        return "xml"
    if lower.endswith(".mobileprovision"):
        return "mobileprovision"
    if lower.endswith(".storyboardc"):
        return "storyboard"
    if lower.endswith(".xcassets"):
        return "assets"
    if lower.endswith(".nib"):
        return "nib"
    if lower.endswith(".xib"):
        return "xib"
    if lower.endswith(".car"):
        return "car"
    return "unknown"


def list_resources(root_dir: PathLike) -> List[str]:
    root = Path(root_dir)
    found: List[str] = []
    if not root.is_dir():
        return found
    for path in root.rglob("*"):
        if path.is_file() and is_resource(path.name):
            found.append(str(path))
        elif path.is_dir() and path.suffix == ".xcassets":
            found.append(str(path))
        elif path.is_dir() and path.suffix == ".storyboardc":
            found.append(str(path))
    return sorted(set(found))


def _content_for_file(path: Path) -> str:
    name = path.name
    try:
        raw = path.read_bytes()
    except OSError:
        return ""

    if name.endswith(".plist") or name.endswith(".strings"):
        try:
            if plist_mod.is_binary_plist(raw):
                obj = plist_mod.decode_plist(path)
                return json.dumps(obj, indent=2, default=str)
            return raw.decode("utf-8", errors="replace")
        except Exception:
            return raw.decode("utf-8", errors="replace")

    if name.endswith(".mobileprovision") or name == "embedded.mobileprovision":
        try:
            return plist_mod.extract_mobileprovision_xml(raw)
        except Exception:
            return raw.decode("latin-1", errors="replace")

    return raw.decode("utf-8", errors="replace")


def _iter_printable_segments(content: str) -> Iterable[str]:
    for line in content.splitlines():
        if not line.strip():
            continue
        for segment in _PRINTABLE_SPLIT.split(line):
            trimmed = segment.strip()
            if trimmed and len(re.sub(r"\s+", "", trimmed)) > _MIN_SEGMENT:
                yield trimmed


def harvest(root_dir: PathLike, db: ResourceDB) -> int:
    """Walk ``root_dir``, decode resources, insert printable segments into ``db``.

    Returns the number of strings inserted.
    """
    root = Path(root_dir)
    count = 0
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if not is_resource(path.name):
            continue
        try:
            rel = str(path.relative_to(root))
        except ValueError:
            rel = str(path)
        content = _content_for_file(path)
        rtype = resource_type(path.name)
        for segment in _iter_printable_segments(content):
            db.insert_resource_string(rel, segment, rtype)
            count += 1
    return count
