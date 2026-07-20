#!/usr/bin/env python3
"""Extract stock Ghidra tool/provider/module universe from GHIDRA_INSTALL_DIR.

Writes native-ui/parity/STOCK_UNIVERSE.json — ground truth for 1:1 parity.
"""
from __future__ import annotations

import json
import os
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "native-ui/parity/STOCK_UNIVERSE.json"

DEFAULT_TOOLS = [
    ("CodeBrowser", "Ghidra/Configurations/Public_Release/lib/Public_Release.jar", "defaultTools/CodeBrowser.tool"),
    ("Debugger", "Ghidra/Debug/Debugger/lib/Debugger.jar", "defaultTools/Debugger.tool"),
    ("Emulator", "Ghidra/Debug/Debugger/lib/Debugger.jar", "defaultTools/Emulator.tool"),
    ("Version Tracking", "Ghidra/Features/VersionTracking/lib/VersionTracking.jar", "defaultTools/VersionTracking.tool"),
]

VIBE_EXTRAS = {
    "MCP",
    "Agent",
    "RAG / JSpace",
    "Rules",
    "Shared Cache",
    "Apple Bundle / IPA",
    "Swift Classes",
    "Code Editor",
}


def find_ghidra() -> Path:
    env = os.environ.get("GHIDRA_INSTALL_DIR") or os.environ.get("GHIDRA_HOME")
    if env:
        p = Path(env)
        if (p / "Ghidra").is_dir():
            return p
        if (p / "lib/ghidra/Ghidra").is_dir():
            return p / "lib/ghidra"
    # Prefer nix result / store paths from flake packaging
    for cand in [
        ROOT / "result/lib/ghidra",
        Path("/nix/var/nix/profiles/default"),
    ]:
        if (cand / "Ghidra").is_dir():
            return cand
    # Scan common nix store prefix (macOS CI / local)
    store = Path("/nix/store")
    if store.is_dir():
        for p in sorted(store.glob("*-ghidra-vibe-*/lib/ghidra"), reverse=True):
            if (p / "Ghidra").is_dir():
                return p
    raise SystemExit(
        "GHIDRA_INSTALL_DIR not set and no ghidra-vibe install found. "
        "Run: export GHIDRA_INSTALL_DIR=$(nix build .#ghidra-vibe --print-out-paths)/lib/ghidra"
    )


def list_modules(ghidra: Path) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for band in ("Features", "Debug", "Framework", "Processors", "Configurations"):
        base = ghidra / "Ghidra" / band
        if not base.is_dir():
            continue
        out[band] = sorted(p.name for p in base.iterdir() if p.is_dir())
    return out


def parse_tool(ghidra: Path, jar_rel: str, entry: str) -> dict:
    jar = ghidra / jar_rel
    with zipfile.ZipFile(jar) as z:
        root = ET.fromstring(z.read(entry))
    providers = []
    seen: set[tuple[str, str]] = set()
    for c in root.iter("COMPONENT_INFO"):
        title = (c.attrib.get("TITLE") or c.attrib.get("NAME") or "").strip()
        name = (c.attrib.get("NAME") or "").strip()
        owner = (c.attrib.get("OWNER") or "").strip()
        active = (c.attrib.get("ACTIVE") or "false").lower() == "true"
        group = c.attrib.get("GROUP") or ""
        key = (title or name, owner)
        if not title and not name:
            continue
        if key in seen:
            continue
        seen.add(key)
        providers.append(
            {
                "title": title or name,
                "name": name,
                "owner": owner,
                "active_default": active,
                "group": group,
                "stock": True,
            }
        )
    includes = sorted(
        {el.attrib["CLASS"] for el in root.iter("INCLUDE") if el.attrib.get("CLASS")}
    )
    packages = sorted(
        {el.attrib["NAME"] for el in root.iter("PACKAGE") if el.attrib.get("NAME")}
    )
    tool_name = ""
    for t in root.iter("TOOL"):
        tool_name = t.attrib.get("TOOL_NAME") or tool_name
    return {
        "tool_name": tool_name,
        "providers": providers,
        "include_plugins": includes,
        "packages": packages,
        "source_jar": jar_rel,
        "source_entry": entry,
    }


def slug(title: str) -> str:
    s = title.lower().strip()
    for ch in (":", "/", "[", "]", "(", ")"):
        s = s.replace(ch, " ")
    s = "_".join(s.split())
    while "__" in s:
        s = s.replace("__", "_")
    return s.strip("_") or "unnamed"


def merge_contracts(universe: dict) -> None:
    """Annotate coverage vs native-ui contracts."""
    chrome_cb = ROOT / "native-ui/parity/CodeBrowser.chrome.json"
    chrome_fe = ROOT / "native-ui/parity/FrontEnd.chrome.json"
    actions = ROOT / "native-ui/menus/actions.json"
    cb_titles: set[str] = set()
    if chrome_cb.is_file():
        cb = json.loads(chrome_cb.read_text())
        cb_titles |= set(cb.get("defaultActiveProviders") or [])
        cb_titles |= set(cb.get("windowMenuProviders") or [])
    fe_tools: list[str] = []
    if chrome_fe.is_file():
        fe = json.loads(chrome_fe.read_text())
        fe_tools = list(fe.get("defaultTools") or [])
    menu_actions: list[str] = []
    if actions.is_file():
        for menu in json.loads(actions.read_text()).get("menus", []):
            for it in menu.get("items", []):
                if it.get("action"):
                    menu_actions.append(it["action"])

    for tool in universe["tools"]:
        titles = {p["title"] for p in tool["providers"]}
        # Normalize CodeBrowser chrome titles vs stock TITLE (strip trailing ": ")
        norm = {t.rstrip(": ").strip() for t in titles}
        if tool["id"] == "CodeBrowser":
            stock_only = sorted(t for t in norm if t not in cb_titles and t not in VIBE_EXTRAS)
            vibe_in_chrome = sorted(t for t in cb_titles if t in VIBE_EXTRAS)
            missing_from_chrome = sorted(
                t for t in norm if t not in cb_titles and not any(
                    t.startswith(c.rstrip(": ")) or c.startswith(t) for c in cb_titles
                )
            )
            tool["contract_coverage"] = {
                "chrome_stock_titles": sorted(cb_titles - VIBE_EXTRAS),
                "vibe_extra_titles": vibe_in_chrome,
                "stock_providers_not_in_chrome": missing_from_chrome,
                "stock_provider_count": len(norm),
            }
        else:
            chrome_path = ROOT / f"native-ui/parity/{tool['id'].replace(' ', '')}.chrome.json"
            # Version Tracking → VersionTracking.chrome.json
            alt = {
                "Debugger": ROOT / "native-ui/parity/Debugger.chrome.json",
                "Emulator": ROOT / "native-ui/parity/Emulator.chrome.json",
                "Version Tracking": ROOT / "native-ui/parity/VersionTracking.chrome.json",
            }.get(tool["id"])
            path = alt or chrome_path
            listed: set[str] = set()
            if path.is_file():
                ch = json.loads(path.read_text())
                listed |= set(ch.get("defaultActiveProviders") or [])
                listed |= set(ch.get("windowMenuProviders") or [])
                listed |= {p.get("title", "") for p in ch.get("providers", []) if isinstance(p, dict)}
            missing = sorted(t for t in norm if t.rstrip(": ").strip() not in listed and t not in listed)
            tool["contract_coverage"] = {
                "chrome_path": str(path.relative_to(ROOT)) if path else None,
                "chrome_exists": path.is_file() if path else False,
                "stock_providers_not_in_chrome": missing,
                "stock_provider_count": len(norm),
            }

    universe["front_end"] = {
        "default_tools": ["CodeBrowser", "Debugger", "Emulator", "Version Tracking"],
        "chrome_tools": fe_tools,
        "tools_missing_from_chrome": sorted(
            set(["CodeBrowser", "Debugger", "Emulator", "Version Tracking"]) - set(fe_tools)
        ),
    }
    universe["menu_actions_in_contract"] = sorted(set(menu_actions))
    universe["vibe_extras"] = sorted(VIBE_EXTRAS)


def main() -> int:
    ghidra = find_ghidra()
    tools = []
    for tool_id, jar_rel, entry in DEFAULT_TOOLS:
        parsed = parse_tool(ghidra, jar_rel, entry)
        tools.append(
            {
                "id": tool_id,
                "slug": slug(tool_id),
                "stock": True,
                "tool_name_attr": parsed["tool_name"] or tool_id,
                "providers": parsed["providers"],
                "include_plugins": parsed["include_plugins"],
                "packages": parsed["packages"],
                "source_jar": parsed["source_jar"],
                "source_entry": parsed["source_entry"],
                "provider_count": len(parsed["providers"]),
            }
        )

    mods = list_modules(ghidra)
    universe = {
        "version": 1,
        "generated_by": "scripts/extract-stock-universe.py",
        "ghidra_install": str(ghidra),
        "parity_bar": "1:1 stock Ghidra features/functionality/UX — no permanent omissions",
        "modules": mods,
        "tools": tools,
        "summary": {
            "tool_count": len(tools),
            "provider_counts": {t["id"]: t["provider_count"] for t in tools},
            "feature_modules": len(mods.get("Features", [])),
            "debug_modules": len(mods.get("Debug", [])),
            "processors": len(mods.get("Processors", [])),
        },
    }
    merge_contracts(universe)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(universe, indent=2) + "\n")
    print(f"Wrote {OUT}", file=sys.stderr)
    print(
        f"  tools={len(tools)} "
        f"CB={tools[0]['provider_count']} "
        f"Dbg={tools[1]['provider_count']} "
        f"Emu={tools[2]['provider_count']} "
        f"VT={tools[3]['provider_count']}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
