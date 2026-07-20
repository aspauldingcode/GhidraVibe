"""Default Apple framework skip-list (Malimite LibraryDefinitions parity)."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Iterable, List, Optional, Sequence, Set

# Exactly matches Malimite LibraryDefinitions.java DEFAULT_LIBRARIES
DEFAULT_LIBRARIES: List[str] = [
    "UIKit",
    "Foundation",
    "CoreData",
    "CoreGraphics",
    "CoreLocation",
    "AVFoundation",
    "WebKit",
    "Security",
    "NetworkExtension",
    "SystemConfiguration",
    "CoreBluetooth",
    "CoreMotion",
    "Photos",
    "Contacts",
    "HealthKit",
    "HomeKit",
    "MapKit",
    "MessageUI",
    "StoreKit",
    "UserNotifications",
    "SwiftStandardLibrary",
    "SwiftUI",
    "Combine",
    "CoreFoundation",
    "QuartzCore",
    "CFNetwork",
    "CoreImage",
    "Metal",
    "SceneKit",
    "ARKit",
    "SpriteKit",
    "GameKit",
    "BackgroundTasks",
    "CloudKit",
    "FileProvider",
    "CoreText",
    "Vision",
    "TextKit",
    "CoreML",
    "NaturalLanguage",
    "AppTrackingTransparency",
    "AuthenticationServices",
    "Intents",
    "CallKit",
    "MediaPlayer",
    "PassKit",
]

DEFAULT_CONFIG_PATH = Path.home() / ".ghidra-vibe" / "malimite-libraries.json"


def get_default_libraries() -> List[str]:
    return list(DEFAULT_LIBRARIES)


def default_config_path() -> Path:
    return DEFAULT_CONFIG_PATH


def _empty_config() -> dict:
    return {"added": [], "removed": []}


def _read_config(config_path: Optional[os.PathLike | str] = None) -> dict:
    path = Path(config_path) if config_path else DEFAULT_CONFIG_PATH
    if not path.is_file():
        return _empty_config()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return _empty_config()
    added = data.get("added") or []
    removed = data.get("removed") or []
    if not isinstance(added, list):
        added = []
    if not isinstance(removed, list):
        removed = []
    return {
        "added": [str(x) for x in added],
        "removed": [str(x) for x in removed],
    }


def save_config(
    config_path: Optional[os.PathLike | str],
    added: Sequence[str],
    removed: Sequence[str],
) -> Path:
    path = Path(config_path) if config_path else DEFAULT_CONFIG_PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "added": sorted({str(x) for x in added if str(x).strip()}),
        "removed": sorted({str(x) for x in removed if str(x).strip()}),
    }
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return path


def load_active(config_path: Optional[os.PathLike | str] = None) -> List[str]:
    """Active libraries = defaults - removed + added (sorted), like Malimite."""
    cfg = _read_config(config_path)
    active: Set[str] = set(DEFAULT_LIBRARIES)
    active.difference_update(cfg["removed"])
    active.update(cfg["added"])
    return sorted(active)


def add_libraries(
    names: Iterable[str],
    config_path: Optional[os.PathLike | str] = None,
) -> List[str]:
    cfg = _read_config(config_path)
    added = set(cfg["added"])
    removed = set(cfg["removed"])
    for name in names:
        name = str(name).strip()
        if not name:
            continue
        removed.discard(name)
        if name not in DEFAULT_LIBRARIES:
            added.add(name)
    save_config(config_path, sorted(added), sorted(removed))
    return load_active(config_path)


def remove_libraries(
    names: Iterable[str],
    config_path: Optional[os.PathLike | str] = None,
) -> List[str]:
    cfg = _read_config(config_path)
    added = set(cfg["added"])
    removed = set(cfg["removed"])
    for name in names:
        name = str(name).strip()
        if not name:
            continue
        if name in added:
            added.discard(name)
        else:
            removed.add(name)
    save_config(config_path, sorted(added), sorted(removed))
    return load_active(config_path)


def reset_config(config_path: Optional[os.PathLike | str] = None) -> List[str]:
    save_config(config_path, [], [])
    return load_active(config_path)
