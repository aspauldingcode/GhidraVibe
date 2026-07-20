"""CLI: ``PYTHONPATH=scripts/lib python3 -m malimite …``"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

from . import __version__
from . import ai as ai_mod
from . import libraries as lib_mod
from . import plist as plist_mod
from . import resources as res_mod
from .db import MalimiteDB
from .pipeline import analyze, find_bin, load_dump_into_db, unpack_ipa


def _print_json(obj) -> None:
    print(json.dumps(obj, indent=2, default=str))


def cmd_unpack(args: argparse.Namespace) -> int:
    out = Path(args.out) if args.out else Path(tempfile.mkdtemp(prefix="malimite-ipa-"))
    app = unpack_ipa(args.ipa, out)
    print(app)
    return 0


def cmd_find_bin(args: argparse.Namespace) -> int:
    app = Path(args.app)
    if args.ipa:
        out = Path(tempfile.mkdtemp(prefix="malimite-ipa-"))
        app = unpack_ipa(args.ipa, out)
    print(find_bin(app))
    return 0


def cmd_resources(args: argparse.Namespace) -> int:
    root = args.app or args.dir
    for path in res_mod.list_resources(root):
        print(path)
    return 0


def cmd_harvest(args: argparse.Namespace) -> int:
    db = MalimiteDB(args.db)
    n = res_mod.harvest(args.root, db)
    print(f"OK: harvested {n} resource strings → {args.db}")
    _print_json(db.stats())
    db.close()
    return 0


def cmd_decode_plist(args: argparse.Namespace) -> int:
    path = Path(args.file)
    if path.suffix == ".mobileprovision" or path.name.endswith(".mobileprovision"):
        data = plist_mod.decode_mobileprovision_file(path)
    else:
        data = plist_mod.decode_plist(path)
    _print_json(data)
    return 0


def cmd_info(args: argparse.Namespace) -> int:
    info = plist_mod.parse_info_plist(args.app)
    _print_json(info)
    return 0


def cmd_libraries(args: argparse.Namespace) -> int:
    cfg = args.config
    sub = args.libraries_cmd
    if sub == "list":
        for name in lib_mod.load_active(cfg):
            print(name)
        return 0
    if sub == "add":
        for name in lib_mod.add_libraries(args.names, cfg):
            print(name)
        return 0
    if sub == "remove":
        for name in lib_mod.remove_libraries(args.names, cfg):
            print(name)
        return 0
    if sub == "reset":
        for name in lib_mod.reset_config(cfg):
            print(name)
        return 0
    print(f"Unknown libraries subcommand: {sub}", file=sys.stderr)
    return 2


def _db_path(args: argparse.Namespace) -> Path:
    return Path(args.db)


def cmd_db(args: argparse.Namespace) -> int:
    sub = args.db_cmd
    path = _db_path(args)
    if sub == "init":
        db = MalimiteDB(path)
        print(f"OK: initialized {path}")
        _print_json(db.stats())
        db.close()
        return 0

    db = MalimiteDB(path)
    try:
        if sub == "stats":
            _print_json(db.stats())
            return 0
        if sub == "classes":
            _print_json(db.get_all_classes_and_functions())
            return 0
        if sub == "functions":
            cls = getattr(args, "klass", None) or getattr(args, "class_name", None)
            if cls:
                rows = db.conn.execute(
                    """
                    SELECT FunctionName, ParentClass, ExecutableName, DecompilationCode
                    FROM Functions WHERE ParentClass = ? LIMIT ?
                    """,
                    (cls, args.limit),
                ).fetchall()
            else:
                rows = db.conn.execute(
                    """
                    SELECT FunctionName, ParentClass, ExecutableName, DecompilationCode
                    FROM Functions LIMIT ?
                    """,
                    (args.limit,),
                ).fetchall()
            _print_json([dict(r) for r in rows])
            return 0
        if sub == "search":
            _print_json(db.search(args.query))
            return 0
        if sub == "strings":
            _print_json(db.get_macho_strings(args.limit))
            return 0
        if sub == "resources":
            _print_json(db.get_resource_strings(args.limit))
            return 0
        if sub == "refs":
            _print_json(db.get_function_references(args.function))
            return 0
    finally:
        db.close()
    print(f"Unknown db subcommand: {sub}", file=sys.stderr)
    return 2


def cmd_analyze(args: argparse.Namespace) -> int:
    result = analyze(
        bundle_or_ipa=args.input,
        project_dir=args.project,
        db_path=args.db,
        headless=args.headless,
        scripts_dir=args.scripts_dir,
    )
    _print_json(result)
    return 0


def cmd_import_dump(args: argparse.Namespace) -> int:
    db = MalimiteDB(args.db)
    counts = load_dump_into_db(
        db,
        classes_json=args.classes,
        functions_json=args.functions,
        strings_json=args.strings,
    )
    print(f"OK: imported {counts}")
    _print_json(db.stats())
    db.close()
    return 0


def cmd_translate(args: argparse.Namespace) -> int:
    code = Path(args.code_file).read_text(encoding="utf-8")
    text, functions = ai_mod.translate_local(
        args.action, code, language=args.language
    )
    print(text)
    if functions:
        print("\n--- parsed BEGIN_FUNCTION/END_FUNCTION ---", file=sys.stderr)
        for i, fn in enumerate(functions, 1):
            print(f"[{i}] {len(fn)} chars", file=sys.stderr)
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="malimite",
        description="Malimite-parity Apple RE helpers for GhidraVibe (stdlib only).",
    )
    p.add_argument("--version", action="version", version=f"malimite {__version__}")
    sub = p.add_subparsers(dest="command", required=True)

    sp = sub.add_parser("unpack", help="Unpack IPA → Payload/*.app")
    sp.add_argument("--ipa", required=True)
    sp.add_argument("--out", default=None)
    sp.set_defaults(func=cmd_unpack)

    sp = sub.add_parser("find-bin", help="Resolve main Mach-O from .app / IPA")
    sp.add_argument("--app", default=None)
    sp.add_argument("--ipa", default=None)
    sp.set_defaults(func=cmd_find_bin)

    sp = sub.add_parser("resources", help="List Apple resource paths")
    sp.add_argument("--app", default=None)
    sp.add_argument("--dir", default=None)
    sp.set_defaults(func=cmd_resources)

    sp = sub.add_parser("harvest", help="Harvest resource strings into SQLite DB")
    sp.add_argument("--root", required=True)
    sp.add_argument("--db", required=True)
    sp.set_defaults(func=cmd_harvest)

    sp = sub.add_parser("decode-plist", help="Decode plist to JSON")
    sp.add_argument("--file", required=True)
    sp.set_defaults(func=cmd_decode_plist)

    sp = sub.add_parser("info", help="Parse Info.plist key fields")
    sp.add_argument("--app", required=True)
    sp.set_defaults(func=cmd_info)

    sp = sub.add_parser("libraries", help="Manage skip-list libraries")
    sp.add_argument(
        "--config",
        default=None,
        help="JSON config path (default ~/.ghidra-vibe/malimite-libraries.json)",
    )
    lib_sub = sp.add_subparsers(dest="libraries_cmd", required=True)
    lib_sub.add_parser("list").set_defaults(func=cmd_libraries)
    add_p = lib_sub.add_parser("add")
    add_p.add_argument("names", nargs="+")
    add_p.set_defaults(func=cmd_libraries)
    rem_p = lib_sub.add_parser("remove")
    rem_p.add_argument("names", nargs="+")
    rem_p.set_defaults(func=cmd_libraries)
    lib_sub.add_parser("reset").set_defaults(func=cmd_libraries)

    sp = sub.add_parser("db", help="SQLite project database operations")
    db_sub = sp.add_subparsers(dest="db_cmd", required=True)

    def _add_db_path(parser: argparse.ArgumentParser) -> None:
        parser.add_argument("--db", required=True, help="Path to .db file")
        parser.set_defaults(func=cmd_db)

    init_p = db_sub.add_parser("init")
    _add_db_path(init_p)
    stats_p = db_sub.add_parser("stats")
    _add_db_path(stats_p)
    classes_p = db_sub.add_parser("classes")
    _add_db_path(classes_p)
    fn_p = db_sub.add_parser("functions")
    _add_db_path(fn_p)
    fn_p.add_argument("--limit", type=int, default=100)
    fn_p.add_argument("--class", dest="klass", default=None, help="Filter by ParentClass")
    se_p = db_sub.add_parser("search")
    _add_db_path(se_p)
    se_p.add_argument("query")
    st_p = db_sub.add_parser("strings")
    _add_db_path(st_p)
    st_p.add_argument("--limit", type=int, default=100)
    rs_p = db_sub.add_parser("resources")
    _add_db_path(rs_p)
    rs_p.add_argument("--limit", type=int, default=100)
    rf_p = db_sub.add_parser("refs")
    _add_db_path(rf_p)
    rf_p.add_argument("function")

    sp = sub.add_parser("analyze", help="Unpack, harvest, optional headless dump")
    sp.add_argument("input", help=".ipa or .app path")
    sp.add_argument("--project", required=True)
    sp.add_argument("--db", required=True)
    sp.add_argument("--headless", default=None)
    sp.add_argument("--scripts-dir", default=None)
    sp.set_defaults(func=cmd_analyze)

    sp = sub.add_parser("import-dump", help="Import DumpClassDataVibe JSON into DB")
    sp.add_argument("--db", required=True)
    sp.add_argument("--classes", default=None)
    sp.add_argument("--functions", default=None)
    sp.add_argument("--strings", default=None)
    sp.set_defaults(func=cmd_import_dump)

    sp = sub.add_parser("translate", help="LLM prompt / OpenAI translation")
    sp.add_argument(
        "--action",
        required=True,
        choices=["auto_fix", "summarize", "find_vulnerabilities"],
    )
    sp.add_argument("--code-file", required=True)
    sp.add_argument(
        "--language",
        default="Swift",
        choices=["Swift", "Objective-C"],
    )
    sp.set_defaults(func=cmd_translate)

    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command in ("find-bin",) and not args.app and not args.ipa:
        parser.error("find-bin requires --app or --ipa")
    if args.command == "resources" and not args.app and not args.dir:
        parser.error("resources requires --app or --dir")
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
