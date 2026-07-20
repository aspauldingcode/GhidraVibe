#!/usr/bin/env python3
"""Build CAPABILITY_MATRIX.json from stock inventories + STOCK_UNIVERSE + tool-map.

Every stock wired inventory id and every universe module gets a probe.
Wave E / null tool-map / live TraceRmi → runtime_gap (never silent skip).
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PARITY = ROOT / "native-ui/parity"
TOOLMAP_PATH = ROOT / "native-ui/mcp/tool-map.json"
ACTIONS_PATH = ROOT / "native-ui/menus/actions.json"
OUT = PARITY / "CAPABILITY_MATRIX.json"

# Wave E / honest-unwired M3 (null tool-map or live agent required)
RUNTIME_GAP_ACTIONS = {
    "bsim_search",
    "bsim_overview",
    "edit_cut",
    "edit_paste",
}
RUNTIME_GAP_ID_SUBSTR = (
    "bsim.",
    "menu.bsim.",
    "pyghidra",
)

# Provider slug → MCP tool (from tool-map providers + extras)
PROVIDER_MCP_FALLBACK = {
    "console": ("analysis", "check_connection"),
    # list_project_files requires GUI mode on headless — segments prove Program Trees M3.
    "program_tree": ("analysis", "list_segments"),
    "version_tracking": ("vibe", "vt_session"),
    "comments": ("vibe", "vibe_list_comments"),
    "script_manager": ("vibe", "vibe_list_scripts"),
    "python": ("vibe", "vibe_list_scripts"),
}

# Debugger/Emulator-unique provider slugs → engine debugger_list
DEBUG_UNIQUE_SLUGS = {
    "breakpoints",
    "stack",
    "threads",
    "watches",
    "modules",
    "memory",
    "regions",
    "time",
    "pcode_stepper",
    "memview",
    "static_mappings",
    "memory_range_mappings",
    "terminal",
    "bundle_manager",
    "diff_details",
    "diff_apply_settings",
    "function_call_graph",
    "function_call_trees",
    "instruction_info",
    "objects",
    "interpreter",
    "jython",
    "connections",
    "model",
    "debug_console",
}


def load_json(path: Path) -> dict:
    return json.loads(path.read_text())


def action_from_menu_id(eid: str) -> str | None:
    # ghidra.vibe.menu.file.save → need actions.json
    return None


def build_action_index(actions: dict) -> dict[str, str]:
    """menu item id → action string (file.save → save_program)."""
    out: dict[str, str] = {}
    for menu in actions.get("menus", []):
        for it in menu.get("items", []):
            mid = it.get("id", "")
            act = it.get("action", "")
            if mid and act:
                out[mid] = act
                out[f"ghidra.vibe.menu.{mid}"] = act
    return out


def toolbar_action(eid: str) -> str | None:
    """Map toolbar inventory id to runAction id."""
    # ghidra.vibe.toolbar.save → save_program
    # ghidra.vibe.toolbar.listing_i → listing_disassemble
    listing = {
        "listing_i": "listing_disassemble",
        "listing_d": "listing_define_data",
        "listing_u": "listing_clear_code",
        "listing_l": "listing_create_label",
        "listing_f": "listing_create_function",
        "listing_v": "listing_create_structure",
        "listing_b": "listing_add_bookmark",
    }
    m = re.search(r"\.toolbar\.(.+)$", eid)
    if not m:
        return None
    slug = m.group(1)
    if slug in listing:
        return listing[slug]
    aliases = {
        "save": "save_program",
        "analyze": "auto_analyze",
        "goto": "goto",
        "undo": "undo",
        "redo": "redo",
        "nav_back": "nav_back",
        "nav_fwd": "nav_fwd",
        "mcp_health": "mcp_health",
        "start_mcp": "start_mcp",
        "dsc": "open_shared_cache",
        "apple": "open_app_bundle",
        "tracermi_connect": "debugger_control",
        "launch": "debugger_control",
        "interrupt": "debugger_control",
        "resume": "debugger_control",
        "step_into": "debugger_control",
        "step_over": "debugger_control",
        "step_out": "debugger_control",
        "emulate": "debugger_control",
        "step": "debugger_control",
        "skip": "debugger_control",
        "finish": "debugger_control",
        "create_session": "vt_session",
        "run_correlators": "vt_session",
        "apply_markup": "vt_session",
        "save_session": "vt_session",
    }
    return aliases.get(slug, slug)


def provider_slug_from_id(eid: str) -> str | None:
    m = re.search(r"\.provider\.([a-z0-9_]+)$", eid)
    return m.group(1) if m else None


def mcp_from_entry(entry: dict, toolmap: dict, provider_slug: str | None) -> dict | None:
    # Capability overrides beat inventory/tool-map when headless cannot exercise a tool.
    if provider_slug and provider_slug in PROVIDER_MCP_FALLBACK:
        fb = PROVIDER_MCP_FALLBACK[provider_slug]
        return {"server": fb[0], "tool": fb[1]}
    mcp = entry.get("mcp")
    if isinstance(mcp, dict) and mcp.get("tool"):
        return {"server": mcp.get("server", "analysis"), "tool": mcp["tool"]}
    if provider_slug:
        p = toolmap.get("providers", {}).get(provider_slug)
        if isinstance(p, dict):
            tool = p.get("tool")
            tools = p.get("tools")
            if tool:
                return {"server": p.get("server", "analysis"), "tool": tool}
            if tools:
                return {"server": p.get("server", "analysis"), "tool": tools[0]}
    return None


def classify_inventory(
    entry: dict,
    *,
    action_index: dict[str, str],
    toolmap: dict,
) -> dict:
    eid = entry["id"]
    surface = entry.get("surface", "")
    tier = entry.get("tier", "m2_ui")
    label = entry.get("label", "")
    base = {
        "id": eid,
        "kind": "inventory",
        "tool": entry.get("owner") or "",
        "inventory_tool": None,  # filled by caller
        "surface": surface,
        "label": label,
        "tier": tier,
        "stock": True,
    }

    # Wave E / BSim menus
    if any(s in eid for s in RUNTIME_GAP_ID_SUBSTR) or "bsim" in eid:
        return {
            **base,
            "probe": "runtime_gap",
            "probe_spec": {"reason": "Wave E — BSim DB UI / live agent path not capability-proven"},
            "pass_rule": "listed_in_runtime_gaps",
        }

    # VC toolbar — stock grey without repo
    if ".toolbar.vc_" in eid or eid.endswith(".vc_add") or "project.toolbar.vc_" in eid:
        op = eid.rsplit(".", 1)[-1]
        return {
            **base,
            "probe": "engine",
            "probe_spec": {"method": "vc_op", "args": {"op": op}, "via": "mcp_or_engine"},
            "pass_rule": "ok_true_or_grey_without_repo",
        }

    # Project refresh
    if eid.endswith("project.toolbar.refresh"):
        return {
            **base,
            "probe": "gui_action",
            "probe_spec": {"action": "refresh_vc"},
            "pass_rule": "gui_action_accepted",
        }

    provider_slug = provider_slug_from_id(eid)

    # Debugger/Emulator unique providers → vibe/engine debugger_list (honest empty without target)
    if provider_slug and provider_slug in DEBUG_UNIQUE_SLUGS and (
        ".debugger." in eid or ".emulator." in eid
    ):
        return {
            **base,
            "probe": "engine",
            "probe_spec": {
                "method": "debugger_list",
                "args": {"provider": label or provider_slug},
                "via": "vibe_or_engine",
            },
            "pass_rule": "json_has_rows_or_has_target_false",
        }

    # Tool chest
    if surface == "tool_chest" or ".project.tool." in eid:
        act = {
            "codebrowser": "show_codebrowser",
            "debugger": "open_debugger",
            "emulator": "open_emulator",
            "version_tracking": "show_version_tracking",
        }.get(eid.rsplit(".", 1)[-1], "")
        return {
            **base,
            "probe": "gui_action",
            "probe_spec": {"action": act or "show_project", "a11y_id": eid},
            "pass_rule": "gui_action_accepted",
        }

    # Startup / project body — a11y exists when app up
    if surface in ("startup", "project_body"):
        return {
            **base,
            "probe": "gui_a11y",
            "probe_spec": {"a11y_id": eid},
            "pass_rule": "a11y_catalog_or_gui_state",
        }

    # Provider toolbar subcontrols → parent provider a11y + optional mcp
    if surface == "provider_toolbar":
        return {
            **base,
            "probe": "gui_a11y",
            "probe_spec": {"a11y_id": eid},
            "pass_rule": "a11y_catalog_or_gui_state",
        }

    # Resolve action for menus/toolbars
    act = action_index.get(eid)
    if not act and surface == "menubar":
        # ghidra.vibe.menu.help.headless → headless_help
        short = eid.replace("ghidra.vibe.menu.", "")
        act = action_index.get(short) or action_index.get(f"ghidra.vibe.menu.{short}")
    if not act and ("toolbar" in surface or ".toolbar." in eid):
        act = toolbar_action(eid)

    # Null tool-map actions → runtime_gap
    if act in RUNTIME_GAP_ACTIONS:
        return {
            **base,
            "probe": "runtime_gap",
            "probe_spec": {"reason": f"action {act} is null/Wave-E in tool-map", "action": act},
            "pass_rule": "listed_in_runtime_gaps",
        }

    # MCP from entry or provider
    mcp = mcp_from_entry(entry, toolmap, provider_slug)
    if act and act in toolmap.get("actions", {}):
        mapped = toolmap["actions"][act]
        if mapped is None:
            return {
                **base,
                "probe": "runtime_gap",
                "probe_spec": {"reason": f"tool-map actions.{act} is null", "action": act},
                "pass_rule": "listed_in_runtime_gaps",
            }
        if isinstance(mapped, dict) and mapped.get("tool"):
            mcp = {"server": mapped.get("server", "analysis"), "tool": mapped["tool"]}

    # Debugger/emulator/VT toolbar with debugger_control / vt_session
    if act == "debugger_control" or (
        act is None and any(x in eid for x in (".debugger.toolbar.", ".emulator.toolbar."))
    ):
        op = eid.rsplit(".", 1)[-1]
        return {
            **base,
            "probe": "engine",
            "probe_spec": {
                "method": "debugger_control",
                "args": {"op": op},
                "via": "mcp_or_engine",
            },
            "pass_rule": "json_ok_or_applied",
        }
    if act == "vt_session" or ".version_tracking.toolbar." in eid:
        op = eid.rsplit(".", 1)[-1]
        return {
            **base,
            "probe": "engine",
            "probe_spec": {"method": "vt_session", "args": {"op": op}, "via": "mcp_or_engine"},
            "pass_rule": "json_ok_or_applied",
        }

    if mcp and mcp.get("tool"):
        return {
            **base,
            "probe": "mcp",
            "probe_spec": {
                "server": mcp["server"],
                "tool": mcp["tool"],
                "action": act,
                "a11y_id": eid if surface == "provider_body" else None,
            },
            "pass_rule": "mcp_success_non_error",
        }

    # Provider body without MCP → gui show + a11y
    if surface == "provider_body" or provider_slug:
        show = f"show_{provider_slug}" if provider_slug else None
        return {
            **base,
            "probe": "gui_action",
            "probe_spec": {"action": show or "mcp_health", "a11y_id": eid},
            "pass_rule": "gui_action_accepted",
        }

    # Default M2 gui action
    if act:
        return {
            **base,
            "probe": "gui_action",
            "probe_spec": {"action": act, "a11y_id": eid},
            "pass_rule": "gui_action_accepted",
        }

    return {
        **base,
        "probe": "gui_a11y",
        "probe_spec": {"a11y_id": eid},
        "pass_rule": "a11y_catalog_or_gui_state",
    }


def classify_module(category: str, name: str) -> dict:
    eid = (
        f"ghidra.vibe.module.{category.lower()}."
        f"{re.sub(r'[^a-z0-9]+', '_', name.lower()).strip('_')}"
    )
    # Live TraceRmi agents + full PyGhidra IDE are Wave E runtime gaps.
    # BSim *jars* must be present; BSim *DB UI menus* are separate inventory runtime_gaps.
    if name == "PyGhidra" or name.startswith("Debugger-agent-"):
        return {
            "id": eid,
            "kind": "module",
            "tool": category,
            "surface": "module",
            "label": name,
            "tier": "m3_engine",
            "stock": True,
            "probe": "runtime_gap",
            "probe_spec": {
                "category": category,
                "name": name,
                "reason": "Wave E — full PyGhidra IDE / live TraceRmi agent session",
            },
            "pass_rule": "listed_in_runtime_gaps",
        }
    return {
        "id": eid,
        "kind": "module",
        "tool": category,
        "surface": "module",
        "label": name,
        "tier": "m3_engine",
        "stock": True,
        "probe": "module_present",
        "probe_spec": {"category": category, "name": name},
        "pass_rule": "module_jar_present",
    }


def main() -> int:
    toolmap = load_json(TOOLMAP_PATH)
    actions = load_json(ACTIONS_PATH) if ACTIONS_PATH.is_file() else {"menus": []}
    # Prefer native-ui menus; fall back to Swift resources copy
    alt = ROOT / "macos/GhidraVibe/Sources/GhidraVibe/Resources/actions.json"
    if not ACTIONS_PATH.is_file() and alt.is_file():
        actions = load_json(alt)
    action_index = build_action_index(actions)
    universe = load_json(PARITY / "STOCK_UNIVERSE.json")

    cases: list[dict] = []
    seen: set[str] = set()

    for inv_path in sorted(PARITY.glob("*.inventory.json")):
        inv = load_json(inv_path)
        inv_tool = inv.get("tool", inv_path.stem)
        for e in inv.get("entries", []):
            if not e.get("stock", True):
                continue
            macos = (e.get("platforms") or {}).get("macos", e.get("behavior"))
            if macos != "wired":
                continue
            case = classify_inventory(e, action_index=action_index, toolmap=toolmap)
            case["inventory_tool"] = inv_tool
            if case["id"] in seen:
                continue
            seen.add(case["id"])
            cases.append(case)

    modules = universe.get("modules") or {}
    for category, names in modules.items():
        for name in names:
            case = classify_module(category, name)
            if case["id"] in seen:
                continue
            seen.add(case["id"])
            cases.append(case)

    cases.sort(key=lambda c: c["id"])
    by_probe: dict[str, int] = {}
    for c in cases:
        by_probe[c["probe"]] = by_probe.get(c["probe"], 0) + 1

    payload = {
        "version": 1,
        "generated_by": "scripts/generate-capability-matrix.py",
        "description": "Executable stock capability probes — every wired inventory id + universe module",
        "count": len(cases),
        "counts_by_probe": by_probe,
        "cases": cases,
    }
    OUT.write_text(json.dumps(payload, indent=2) + "\n")
    print(
        f"Wrote {OUT.relative_to(ROOT)} cases={len(cases)} probes={by_probe}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
