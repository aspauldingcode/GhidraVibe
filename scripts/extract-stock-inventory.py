#!/usr/bin/env python3
"""Build per-tool *.inventory.json with honest M1/M2/M3 + depth (shell/partial/stock).

wired (macos) only when id ∈ STOCK_DEPTH_ALLOWLIST (stock-depth proven).
Shell Tool Chest tools (Debugger/Emulator/VT controls) stay disabled_honest until allowlisted.
GTK Tool Chest tools stay disabled_honest until GTK implements them.
Fake tool-map aliases never count as M3.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ACTIONS = ROOT / "native-ui/menus/actions.json"
CATALOG = ROOT / "native-ui/a11y/catalog.json"
TOOLMAP = ROOT / "native-ui/mcp/tool-map.json"
APPMODEL = ROOT / "macos/GhidraVibe/Sources/GhidraVibe/AppModel.swift"
ALLOWLIST_PATH = ROOT / "native-ui/parity/STOCK_DEPTH_ALLOWLIST.json"

# tool-map entries that must never inflate M3
FAKE_M3_ACTIONS = {
    "bsim_search",
    "bsim_overview",
    "edit_cut",
    "edit_copy",
    "edit_paste",
    "open_debugger",
    "open_emulator",
}

# CB Window providers still below stock table/graph depth unless allowlisted
# Still below stock interactive depth (lists OK; not full Swing tables/graphs)
SHELL_CB_PROVIDERS = {
    "entropy",
    "overview",
    "datatype_preview",
    "disassembled_view",
    "checksum",
    "python",
}

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

# Actions handled in AppModel.runAction / providerChromeAction / toolbar (M2 or M3).
UI_ACTIONS: set[str] = {
    "mcp_health",
    "fetch_functions",
    "decompile",
    "dyld_open",
    "dyld_discover",
    "show_dsc",
    "open_shared_cache",
    "codebrowser",
    "show_codebrowser",
    "show_project",
    "show_workspace",
    "show_help",
    "welcome_help",
    "extract",
    "start_bridge",
    "start_mcp",
    "rag_index",
    "jspace_index",
    "rag_init",
    "jspace_init",
    "import_file",
    "open_project",
    "new_project",
    "save_program",
    "close_program",
    "auto_analyze",
    "goto",
    "undo",
    "redo",
    "nav_back",
    "nav_fwd",
    "nav_forward",
    "clear_selection",
    "refresh_debugger",
    "refresh_vc",
    "search_strings",
    "search_functions",
    "search_memory",
    "edit_cut",
    "edit_copy",
    "edit_paste",
    "listing_disassemble",
    "listing_define_data",
    "listing_clear_code",
    "listing_create_label",
    "listing_create_function",
    "listing_add_bookmark",
    "listing_create_structure",
    "import_apple",
    "open_app_bundle",
    "tip_of_the_day",
    "about",
    "headless_help",
    "bsim_search",
    "bsim_overview",
    "show_version_tracking",
    "version_tracking",
    "open_debugger",
    "open_emulator",
    "vc_add",
    "vc_checkout",
    "vc_update",
    "vc_checkin",
    "vc_undo",
    "vc_find",
}

TOOLBAR_ALIASES = {
    "save_program": "save",
    "previous_location": "nav_back",
    "next_location": "nav_fwd",
    "auto_analyze": "analyze",
    "shared_cache": "dsc",
    "open_app_bundle": "apple",
    "go_to": "goto",
    "mcp_health": "mcp_health",
    "start_mcp": "start_mcp",
    "trace_rmi_connect": "trace_rmi",
    "step_into": "step_into",
    "step_over": "step_over",
    "step_out": "step_out",
    "create_session": "create_session",
    "run_correlators": "run_correlators",
    "apply_markup": "apply_markup",
    "save_session": "save_session",
}

# Must match ProviderKind.rawValue / ToolMode titles (never raw slugify of chrome titles).
PROVIDER_SLUGS = {
    "Program Trees": "program_tree",
    "Program Tree": "program_tree",
    "Symbol Tree": "symbol_tree",
    "Data Type Manager": "data_types",
    "DataTypes Provider": "data_types",
    "Listing": "listing",
    "Listing:": "listing",
    "Decompile": "decompiler",
    "Decompiler": "decompiler",
    "Console": "console",
    "Debug Console": "console",
    "Defined Strings": "strings",
    "Functions": "functions",
    "Functions Window": "functions",
    "Memory Map": "memory_map",
    "Symbol Table": "symbol_table",
    "Bytes": "bytes",
    "Bytes: No Program": "bytes",
    "Bookmarks": "bookmarks",
    "Script Manager": "script_manager",
    "Function Graph": "function_graph",
    "Version Tracking": "version_tracking",
    "Entropy": "entropy",
    "Overview": "overview",
    "Defined Data": "defined_data",
    "Data Window": "defined_data",
    "Equates Table": "equates",
    "External Programs": "external_programs",
    "Relocation Table": "relocations",
    "Data Type Preview": "datatype_preview",
    "Disassembled View": "disassembled_view",
    "Virtual Disassembler - Current Instruction": "disassembled_view",
    "Register Manager": "registers",
    "Registers": "registers",
    "Symbol References": "symbol_references",
    "Checksum Generator": "checksum",
    "Function Tags": "function_tags",
    "Comments": "comments",
    "Python": "python",
    "Interpreter": "python",
    "Jython": "python",
    "Dynamic": "listing",
    "[Dynamic]": "listing",
}


def slugify(label: str) -> str:
    s = label.lower().replace("…", "").replace("...", "")
    s = re.sub(r"[^a-z0-9]+", "_", s).strip("_")
    return TOOLBAR_ALIASES.get(s, s)


def provider_slug(title: str) -> str:
    """Canonical provider id slug — Prefer PROVIDER_SLUGS over raw slugify."""
    t = (title or "").strip()
    if t in PROVIDER_SLUGS:
        return PROVIDER_SLUGS[t]
    # Normalize trailing ": …" / "Listing: Foo"
    base = t.split(":")[0].strip()
    if base in PROVIDER_SLUGS:
        return PROVIDER_SLUGS[base]
    if t.startswith("Bytes"):
        return "bytes"
    if t.startswith("Listing"):
        return "listing"
    return re.sub(r"[^a-z0-9]+", "_", t.lower()).strip("_")


def load_ui_actions_from_swift() -> set[str]:
    actions = set(UI_ACTIONS)
    if not APPMODEL.is_file():
        return actions
    text = APPMODEL.read_text(errors="ignore")
    # case "foo", "bar":
    for m in re.finditer(r'case\s+((?:"[^"]+"\s*,\s*)*"([^"]+)")', text):
        chunk = m.group(1)
        for a in re.findall(r'"([^"]+)"', chunk):
            if a.startswith("ghidra.vibe."):
                # provider chrome ids — strip prefix for show_* detection
                if ".show_" in a or a.endswith(".refresh"):
                    continue
                actions.add(a.split(".")[-1])
            else:
                actions.add(a)
    for m in re.finditer(r'case\s+"(show_[^"]+)"', text):
        actions.add(m.group(1))
    return actions


def load_allowlist() -> set[str]:
    if not ALLOWLIST_PATH.is_file():
        return set()
    return set(json.loads(ALLOWLIST_PATH.read_text()).get("ids") or [])


def real_mcp(action: str, action_mcp: dict) -> dict | None:
    if action in FAKE_M3_ACTIONS:
        return None
    v = action_mcp.get(action)
    return v if isinstance(v, dict) else None


def entry(
    id_: str,
    surface: str,
    owner: str,
    label: str,
    hint: str,
    mcp: dict | None,
    *,
    ui_wired: bool,
    engine_wired: bool,
    stock: bool,
    allowlist: set[str],
    depth_hint: str | None = None,
    gtk_wired: bool | None = None,
) -> dict:
    """Honest wiring: allowlist ⇒ stock depth; else shell/partial stay disabled_honest."""
    in_allow = id_ in allowlist
    if depth_hint:
        depth = depth_hint
    elif in_allow and engine_wired:
        depth = "stock"
    elif in_allow and ui_wired:
        depth = "stock"
    elif ui_wired or engine_wired:
        depth = "shell"
    else:
        depth = "shell"

    if in_allow and (ui_wired or engine_wired):
        macos = "wired"
        if engine_wired:
            tier = "m3_engine"
        else:
            tier = "m2_ui"
        depth = "stock"
    else:
        macos = "disabled_honest"
        if engine_wired and not in_allow:
            tier = "m2_shell"
        elif ui_wired and not in_allow:
            tier = "m2_shell"
        else:
            tier = "m1"

    gtk = macos if gtk_wired is None else ("wired" if gtk_wired and in_allow else "disabled_honest")
    # Tool Chest / Debugger / Emulator / VT: GTK lag unless explicitly allowlisted for gtk
    if any(
        x in id_
        for x in (
            ".debugger.",
            ".emulator.",
            ".version_tracking.",
            "project.tool.debugger",
            "project.tool.emulator",
            "project.tool.version_tracking",
        )
    ):
        gtk = "wired" if (gtk_wired is True and in_allow) else "disabled_honest"

    return {
        "id": id_,
        "surface": surface,
        "owner": owner,
        "label": label,
        "hint": hint,
        "mcp": mcp,
        "stock": stock,
        "tier": tier,
        "depth": depth,
        "platforms": {"macos": macos, "gtk": gtk},
        "behavior": macos,
    }


def build_codebrowser(ui: set[str], action_mcp: dict, catalog: dict, allowlist: set[str]) -> dict:
    chrome = json.loads((ROOT / "native-ui/parity/CodeBrowser.chrome.json").read_text())
    actions = json.loads(ACTIONS.read_text())
    toolmap_p = json.loads(TOOLMAP.read_text()).get("providers", {})
    items: list[dict] = []
    seen: set[str] = set()

    def add(e: dict) -> None:
        if e["id"] in seen:
            return
        seen.add(e["id"])
        cat = catalog.get(e["id"])
        if cat:
            e["label"] = cat.get("label") or e["label"]
            e["hint"] = cat.get("hint") or e["hint"]
        items.append(e)

    for menu in actions.get("menus", []):
        if menu.get("id") == "project" or menu.get("frontEndOnly"):
            continue
        for it in menu.get("items", []):
            act = it.get("action") or ""
            mcp = real_mcp(act, action_mcp)
            engine = bool(mcp)
            ui_wired = act in ui or act.startswith("show_")
            stock = True
            if any(x in it.get("title", "") for x in ("App Bundle", "IPA", "Shared Cache", "Apple")):
                stock = False
            depth_hint = None
            if act in FAKE_M3_ACTIONS or act in {"bsim_search", "bsim_overview", "search_memory", "edit_cut", "edit_paste"}:
                depth_hint = "shell"
            add(
                entry(
                    f"ghidra.vibe.menu.{it['id']}",
                    "menubar",
                    menu.get("label", menu["id"]),
                    it["title"],
                    it["title"],
                    mcp,
                    ui_wired=ui_wired,
                    engine_wired=engine,
                    stock=stock,
                    allowlist=allowlist,
                    depth_hint=depth_hint,
                    gtk_wired=True,
                )
            )

    for group in chrome.get("toolbarGroups", []):
        slug = slugify(group)
        tid = f"ghidra.vibe.toolbar.{slug}"
        action_for = {
            "save": "save_program",
            "nav_back": "nav_back",
            "nav_fwd": "nav_fwd",
            "goto": "goto",
            "analyze": "auto_analyze",
            "undo": "undo",
            "redo": "redo",
            "mcp_health": "mcp_health",
            "start_mcp": "start_mcp",
            "dsc": "open_shared_cache",
            "apple": "open_app_bundle",
        }.get(slug, slug)
        mcp = real_mcp(action_for, action_mcp)
        engine = bool(mcp)
        ui_wired = action_for in ui or slug in {
            "save", "nav_back", "nav_fwd", "goto", "analyze", "undo", "redo",
            "mcp_health", "start_mcp", "dsc", "apple",
        }
        stock = slug not in {"dsc", "apple"}
        add(
            entry(
                tid,
                "main_toolbar",
                "CodeBrowser",
                group,
                group,
                mcp,
                ui_wired=ui_wired,
                engine_wired=engine,
                stock=stock,
                allowlist=allowlist,
                gtk_wired=True,
            )
        )

    for letter, name, tool in [
        ("I", "Disassemble", "listing_disassemble"),
        ("D", "Define Data", "listing_define_data"),
        ("U", "Clear Code Bytes", "listing_clear_code"),
        ("L", "Create Label", "listing_create_label"),
        ("F", "Create Function", "listing_create_function"),
        ("V", "Create Structure / Array", "listing_create_structure"),
        ("B", "Add Bookmark", "listing_add_bookmark"),
    ]:
        mcp = real_mcp(tool, action_mcp) or {"server": "vibe", "tool": tool}
        add(
            entry(
                f"ghidra.vibe.toolbar.listing_{letter.lower()}",
                "main_toolbar",
                "Listing",
                letter,
                name,
                mcp,
                ui_wired=tool in ui,
                engine_wired=True,
                stock=True,
                allowlist=allowlist,
                gtk_wired=True,
            )
        )

    for prov, tools in chrome.get("providerLocalToolbars", {}).items():
        for t in tools:
            mcp = t.get("mcp") if isinstance(t.get("mcp"), dict) else None
            behavior = t.get("behavior", "disabled_honest")
            pid = t["id"]
            ui_wired = behavior == "wired"
            engine = bool(mcp)
            add(
                entry(
                    pid,
                    "provider_toolbar",
                    prov,
                    t["label"],
                    t.get("hint", t["label"]),
                    mcp,
                    ui_wired=ui_wired,
                    engine_wired=engine,
                    stock=True,
                    allowlist=allowlist,
                    depth_hint="partial" if ui_wired else "shell",
                    gtk_wired=True,
                )
            )

    for title in list(chrome.get("defaultActiveProviders", [])) + list(
        chrome.get("windowMenuProviders", [])
    ):
        slug = provider_slug(title)
        stock = title not in VIBE_EXTRAS
        mcp = toolmap_p.get(slug) if isinstance(toolmap_p.get(slug), dict) else None
        depth_hint = "shell" if slug in SHELL_CB_PROVIDERS else None
        add(
            entry(
                f"ghidra.vibe.provider.{slug}",
                "provider_body",
                title,
                title,
                f"Show {title}",
                mcp,
                ui_wired=True,
                engine_wired=bool(mcp) and slug not in SHELL_CB_PROVIDERS,
                stock=stock,
                allowlist=allowlist,
                depth_hint=depth_hint,
                gtk_wired=True,
            )
        )

    return {
        "version": 2,
        "tool": "CodeBrowser",
        "stock": True,
        "generated_by": "scripts/extract-stock-inventory.py",
        "count": len(items),
        "counts": {
            "wired": sum(1 for e in items if e["behavior"] == "wired"),
            "disabled_honest": sum(1 for e in items if e["behavior"] == "disabled_honest"),
            "stock": sum(1 for e in items if e.get("stock")),
            "m2_ui": sum(1 for e in items if e.get("tier") == "m2_ui"),
            "m3_engine": sum(1 for e in items if e.get("tier") == "m3_engine"),
            "m1": sum(1 for e in items if e.get("tier") == "m1"),
        },
        "entries": sorted(items, key=lambda e: e["id"]),
    }


def build_frontend(ui: set[str], allowlist: set[str]) -> dict:
    chrome = json.loads((ROOT / "native-ui/parity/FrontEnd.chrome.json").read_text())
    items: list[dict] = []
    for label in chrome.get("dockingToolbar", []):
        if label in ("—", "-", ""):
            continue
        slug = slugify(label)
        id_map = {
            "add_to_version_control": "ghidra.vibe.project.toolbar.vc_add",
            "checkout": "ghidra.vibe.project.toolbar.vc_checkout",
            "update": "ghidra.vibe.project.toolbar.vc_update",
            "checkin": "ghidra.vibe.project.toolbar.vc_checkin",
            "undocheckout": "ghidra.vibe.project.toolbar.vc_undo",
            "find_checkouts": "ghidra.vibe.project.toolbar.vc_find",
            "refresh": "ghidra.vibe.project.toolbar.refresh",
        }
        eid = id_map.get(slug, f"ghidra.vibe.project.toolbar.{slug}")
        act = {
            "ghidra.vibe.project.toolbar.vc_add": "vc_add",
            "ghidra.vibe.project.toolbar.vc_checkout": "vc_checkout",
            "ghidra.vibe.project.toolbar.vc_update": "vc_update",
            "ghidra.vibe.project.toolbar.vc_checkin": "vc_checkin",
            "ghidra.vibe.project.toolbar.vc_undo": "vc_undo",
            "ghidra.vibe.project.toolbar.vc_find": "vc_find",
            "ghidra.vibe.project.toolbar.refresh": "refresh_vc",
        }.get(eid, "")
        # VC: stock-grey without repo via engine vc_status/vc_op (parity, not a gap).
        is_vc = eid.startswith("ghidra.vibe.project.toolbar.vc_")
        items.append(
            entry(
                eid,
                "project_toolbar",
                "Project Window",
                label,
                label,
                None,
                ui_wired=act in ui,
                engine_wired=is_vc,
                stock=True,
                allowlist=allowlist,
                depth_hint=None,
                gtk_wired=True,
            )
        )

    for tool in chrome.get("defaultTools", []):
        slug = slugify(tool)
        eid = f"ghidra.vibe.project.tool.{slug}"
        act = {
            "codebrowser": "show_codebrowser",
            "debugger": "open_debugger",
            "emulator": "open_emulator",
            "version_tracking": "show_version_tracking",
        }.get(slug, "")
        # GTK stock_tools.c hosts Debugger / Emulator / VT pages.
        gtk_ok = slug in {
            "codebrowser",
            "debugger",
            "emulator",
            "version_tracking",
        }
        items.append(
            entry(
                eid,
                "tool_chest",
                "Tool Chest",
                tool,
                f"Open {tool}",
                None,
                ui_wired=act in ui or slug == "codebrowser",
                engine_wired=False,
                stock=True,
                allowlist=allowlist,
                depth_hint="stock" if gtk_ok else "shell",
                gtk_wired=gtk_ok,
            )
        )

    for band in chrome.get("contentTopToBottom", []):
        slug = slugify(band.split("(")[0])
        items.append(
            entry(
                f"ghidra.vibe.project.body.{slug}",
                "project_body",
                "Project Window",
                band,
                band,
                None,
                ui_wired=True,
                engine_wired=False,
                stock=True,
                allowlist=allowlist,
                gtk_wired=True,
            )
        )

    for step in chrome.get("startupAfterSplash", []):
        slug = slugify(step)
        items.append(
            entry(
                f"ghidra.vibe.startup.{slug}",
                "startup",
                "Front End",
                step,
                step,
                None,
                ui_wired=True,
                engine_wired=False,
                stock=True,
                allowlist=allowlist,
                gtk_wired=True,
            )
        )

    return {
        "version": 2,
        "tool": "Project Window",
        "stock": True,
        "generated_by": "scripts/extract-stock-inventory.py",
        "count": len(items),
        "counts": {
            "wired": sum(1 for e in items if e["behavior"] == "wired"),
            "disabled_honest": sum(1 for e in items if e["behavior"] == "disabled_honest"),
        },
        "entries": sorted(items, key=lambda e: e["id"]),
    }


def build_stock_tool(
    chrome_path: Path, tool_name: str, ui: set[str], allowlist: set[str], *, gtk_ready: bool
) -> dict:
    chrome = json.loads(chrome_path.read_text())
    items: list[dict] = []
    open_act = {
        "Debugger": "open_debugger",
        "Emulator": "open_emulator",
        "Version Tracking": "show_version_tracking",
    }.get(tool_name, "")
    tool_open = open_act in ui

    for group in chrome.get("toolbarGroups", []):
        slug = slugify(group)
        eid = f"ghidra.vibe.{slugify(tool_name)}.toolbar.{slug}"
        # Save is real; other controls need TraceRmi/VT engine
        engine = slug == "save"
        items.append(
            entry(
                eid,
                "main_toolbar",
                tool_name,
                group,
                group,
                None,
                ui_wired=tool_open,
                engine_wired=engine,
                stock=True,
                allowlist=allowlist,
                depth_hint="stock" if slug == "save" else "shell",
                gtk_wired=gtk_ready,
            )
        )

    # Shared CB panes use canonical provider_slug; debug-unique keep descriptive slug.
    SHARED_CB = set(PROVIDER_SLUGS.values())
    for p in chrome.get("providers", []):
        title = p.get("title") or p.get("name") or "?"
        canon = provider_slug(title)
        # Inventory id: tool prefix + canonical slug when shared, else title slug
        slug = canon if canon in SHARED_CB else slugify(title)
        eid = f"ghidra.vibe.{slugify(tool_name)}.provider.{slug}"
        is_shared = canon in SHARED_CB
        # Shared → CodeBrowser panes; unique → debugger_list / VT panes.
        engine = (not is_shared) or eid in allowlist
        items.append(
            entry(
                eid,
                "provider_body",
                tool_name,
                title,
                f"Show {title}",
                None,
                ui_wired=tool_open,
                engine_wired=engine,
                stock=True,
                allowlist=allowlist,
                depth_hint="stock" if eid in allowlist else "shell",
                gtk_wired=gtk_ready,
            )
        )

    return {
        "version": 2,
        "tool": tool_name,
        "stock": True,
        "generated_by": "scripts/extract-stock-inventory.py",
        "count": len(items),
        "counts": {
            "wired": sum(1 for e in items if e["behavior"] == "wired"),
            "disabled_honest": sum(1 for e in items if e["behavior"] == "disabled_honest"),
        },
        "entries": sorted(items, key=lambda e: e["id"]),
    }


def main() -> int:
    ui = load_ui_actions_from_swift()
    toolmap = json.loads(TOOLMAP.read_text())
    action_mcp = {k: v for k, v in toolmap.get("actions", {}).items()}
    catalog = {e["id"]: e for e in json.loads(CATALOG.read_text())["entries"]}
    allowlist = load_allowlist()
    # GTK Tool Chest ready flag — flipped when linux pages exist
    gtk_tools = ROOT / "linux/GhidraVibe/src/stock_tools.c"
    gtk_ready = gtk_tools.is_file()

    outputs = [
        (
            ROOT / "native-ui/parity/CodeBrowser.inventory.json",
            build_codebrowser(ui, action_mcp, catalog, allowlist),
        ),
        (ROOT / "native-ui/parity/FrontEnd.inventory.json", build_frontend(ui, allowlist)),
        (
            ROOT / "native-ui/parity/Debugger.inventory.json",
            build_stock_tool(
                ROOT / "native-ui/parity/Debugger.chrome.json", "Debugger", ui, allowlist,
                gtk_ready=gtk_ready,
            ),
        ),
        (
            ROOT / "native-ui/parity/Emulator.inventory.json",
            build_stock_tool(
                ROOT / "native-ui/parity/Emulator.chrome.json", "Emulator", ui, allowlist,
                gtk_ready=gtk_ready,
            ),
        ),
        (
            ROOT / "native-ui/parity/VersionTracking.inventory.json",
            build_stock_tool(
                ROOT / "native-ui/parity/VersionTracking.chrome.json",
                "Version Tracking",
                ui,
                allowlist,
                gtk_ready=gtk_ready,
            ),
        ),
    ]

    for path, data in outputs:
        path.write_text(json.dumps(data, indent=2) + "\n")
        c = data.get("counts", {})
        print(
            f"Wrote {path.relative_to(ROOT)} ({data['count']} entries; "
            f"wired={c.get('wired')} disabled={c.get('disabled_honest')})",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
