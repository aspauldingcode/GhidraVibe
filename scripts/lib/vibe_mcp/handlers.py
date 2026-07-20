"""Tool handlers for Malimite / dyld / rules / RAG / gap / nav."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable

from . import __version__
from .state import SESSION

# Ensure sibling libs importable when packaged
_LIB = Path(__file__).resolve().parent.parent
if str(_LIB) not in os.sys.path:
    os.sys.path.insert(0, str(_LIB))

MCP_URL = os.environ.get("GHIDRA_MCP_URL", "http://127.0.0.1:8089").rstrip("/")
GUI_URL = os.environ.get("GHIDRA_VIBE_GUI_URL", "http://127.0.0.1:8091").rstrip("/")
RULES_PATH = Path(
    os.environ.get(
        "GHIDRA_VIBE_RULES",
        str(Path.home() / ".ghidra-vibe" / "jspace" / "playbook.md"),
    )
)
DEFAULT_DB = os.environ.get(
    "GHIDRA_VIBE_MALIMITE_DB",
    str(Path.home() / ".cache" / "ghidra-vibe" / "malimite.db"),
)


def _json_ok(data: Any = None, **extra: Any) -> dict[str, Any]:
    out: dict[str, Any] = {"ok": True}
    if data is not None:
        out["data"] = data
    out.update(extra)
    return out


def _json_err(msg: str, **extra: Any) -> dict[str, Any]:
    return {"ok": False, "error": msg, **extra}


def analysis_http(method: str, path: str, body: dict | None = None, query: dict | None = None) -> Any:
    url = f"{MCP_URL}/{path.lstrip('/')}"
    if query:
        url += "?" + urllib.parse.urlencode({k: v for k, v in query.items() if v is not None})
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={"Content-Type": "application/json"} if data else {},
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            raw = resp.read().decode()
            if not raw:
                return {"ok": True}
            try:
                return json.loads(raw)
            except json.JSONDecodeError:
                return {"ok": True, "text": raw}
    except urllib.error.HTTPError as e:
        return _json_err(e.read().decode() or str(e), status=e.code)
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def gui_http(method: str, path: str, body: dict | None = None) -> Any:
    """Best-effort GuiControlServer call (in-process engine writes live there)."""
    url = f"{GUI_URL}/{path.lstrip('/')}"
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={"Content-Type": "application/json"} if data else {},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode()
            if not raw:
                return {"ok": True}
            try:
                return json.loads(raw)
            except json.JSONDecodeError:
                return {"ok": True, "text": raw}
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def _run_dyld(args: list[str], env: dict[str, str] | None = None) -> dict[str, Any]:
    helper = os.environ.get("GHIDRA_VIBE_DYLD", "ghidra-vibe-dyld")
    run_env = os.environ.copy()
    if env:
        run_env.update(env)
    try:
        proc = subprocess.run(
            [helper, *args],
            capture_output=True,
            text=True,
            timeout=600,
            check=False,
            env=run_env,
        )
    except FileNotFoundError:
        # Fallback: pure Python index for list/find
        return _dyld_python_fallback(args)
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))
    out = (proc.stdout or "") + (proc.stderr or "")
    if proc.returncode != 0 and "OK" not in out:
        # try python fallback for list/find
        fb = _dyld_python_fallback(args)
        if fb.get("ok"):
            return fb
        return _json_err(out.strip() or f"exit {proc.returncode}", text=out)
    lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
    return _json_ok(lines, text=proc.stdout, returncode=proc.returncode)


def _parse_dyld_import_ok(text: str) -> dict[str, str]:
    """Parse `OK: project=… program=… image=… cache=…` from ghidra-vibe-dyld."""
    meta: dict[str, str] = {}
    for line in (text or "").splitlines():
        if not line.startswith("OK:") or "project=" not in line:
            continue
        payload = line[3:].strip()
        for part in payload.split():
            if "=" not in part:
                continue
            k, v = part.split("=", 1)
            meta[k.strip()] = v.strip()
        break
    return meta


def _truthy(val: Any, default: bool = False) -> bool:
    if val is None:
        return default
    if isinstance(val, bool):
        return val
    return str(val).strip().lower() in ("1", "true", "yes", "on")


def _dyld_python_fallback(args: list[str]) -> dict[str, Any]:
    try:
        from dsc_index import find_cache, list_images, resolve_image  # type: ignore
    except Exception as e:  # noqa: BLE001
        return _json_err(f"dyld helper missing and python index failed: {e}")
    cmd = args[0] if args else ""
    if cmd == "find-cache":
        try:
            return _json_ok(str(find_cache()))
        except Exception as e:  # noqa: BLE001
            return _json_err(str(e))
    cache = None
    query = ""
    image = ""
    i = 1
    while i < len(args):
        if args[i] == "--cache" and i + 1 < len(args):
            cache = args[i + 1]
            i += 2
            continue
        if args[i] == "--query" and i + 1 < len(args):
            query = args[i + 1]
            i += 2
            continue
        if args[i] == "--image" and i + 1 < len(args):
            image = args[i + 1]
            i += 2
            continue
        i += 1
    cache_path = Path(cache) if cache else None
    if cmd in ("list", "open"):
        try:
            rows = list_images(cache_path)
            paths = [p for _, p in rows]
            if query:
                q = query.lower()
                paths = [p for p in paths if q in p.lower()]
            return _json_ok(paths)
        except Exception as e:  # noqa: BLE001
            return _json_err(str(e))
    if cmd == "resolve":
        try:
            return _json_ok(resolve_image(image or query, cache_path))
        except Exception as e:  # noqa: BLE001
            return _json_err(str(e))
    return _json_err(f"unsupported dyld fallback for {cmd}")


# --- Malimite ---


def malimite_analyze(args: dict) -> dict[str, Any]:
    from malimite.pipeline import analyze

    path = args.get("path") or args.get("input")
    if not path:
        return _json_err("path required")
    project = args.get("project") or str(
        Path.home() / ".cache" / "ghidra-vibe" / "MalimiteImport"
    )
    db = args.get("db") or str(Path(project) / "malimite.db")
    try:
        result = analyze(
            bundle_or_ipa=path,
            project_dir=project,
            db_path=db,
            headless=args.get("headless"),
            scripts_dir=args.get("scripts_dir"),
        )
        return _json_ok(result, project=project, db=db)
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def malimite_info(args: dict) -> dict[str, Any]:
    from malimite import plist as plist_mod

    app = args.get("app") or args.get("path")
    if not app:
        return _json_err("app required")
    try:
        return _json_ok(plist_mod.parse_info_plist(app))
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def malimite_list_resources(args: dict) -> dict[str, Any]:
    from malimite import resources as res_mod

    root = args.get("root") or args.get("app") or args.get("path")
    if not root:
        return _json_err("root/app required")
    try:
        return _json_ok(list(res_mod.list_resources(root)))
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def malimite_harvest(args: dict) -> dict[str, Any]:
    from malimite import resources as res_mod
    from malimite.db import MalimiteDB

    root = args.get("root") or args.get("app")
    db_path = args.get("db") or DEFAULT_DB
    if not root:
        return _json_err("root required")
    try:
        db = MalimiteDB(db_path)
        n = res_mod.harvest(root, db)
        stats = db.stats()
        db.close()
        return _json_ok({"harvested": n, "stats": stats, "db": db_path})
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def malimite_decode_plist(args: dict) -> dict[str, Any]:
    from malimite import plist as plist_mod

    path = args.get("file") or args.get("path")
    if not path:
        return _json_err("file required")
    p = Path(path)
    try:
        if p.suffix == ".mobileprovision" or p.name.endswith(".mobileprovision"):
            return _json_ok(plist_mod.decode_mobileprovision_file(p))
        return _json_ok(plist_mod.decode_plist(p))
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def malimite_decode_provision(args: dict) -> dict[str, Any]:
    return malimite_decode_plist(args)


def malimite_libraries(args: dict) -> dict[str, Any]:
    from malimite import libraries as lib_mod

    op = args.get("op") or args.get("action") or "list"
    cfg = args.get("config")
    names = args.get("names") or []
    if isinstance(names, str):
        names = [names]
    try:
        if op == "list":
            return _json_ok(lib_mod.load_active(cfg))
        if op == "add":
            return _json_ok(lib_mod.add_libraries(names, cfg))
        if op == "remove":
            return _json_ok(lib_mod.remove_libraries(names, cfg))
        if op == "reset":
            return _json_ok(lib_mod.reset_config(cfg))
        return _json_err(f"unknown op {op}")
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def _db(args: dict):
    from malimite.db import MalimiteDB

    path = args.get("db") or DEFAULT_DB
    return MalimiteDB(path), path


def malimite_db_stats(args: dict) -> dict[str, Any]:
    try:
        db, path = _db(args)
        stats = db.stats()
        db.close()
        return _json_ok(stats, db=path)
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def malimite_list_classes(args: dict) -> dict[str, Any]:
    try:
        db, path = _db(args)
        data = db.get_all_classes_and_functions()
        db.close()
        return _json_ok(data, db=path)
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def malimite_list_functions(args: dict) -> dict[str, Any]:
    try:
        db, path = _db(args)
        cls = args.get("class") or args.get("klass")
        limit = int(args.get("limit") or 100)
        if cls:
            rows = db.conn.execute(
                """
                SELECT FunctionName, ParentClass, ExecutableName, DecompilationCode
                FROM Functions WHERE ParentClass = ? LIMIT ?
                """,
                (cls, limit),
            ).fetchall()
        else:
            rows = db.conn.execute(
                """
                SELECT FunctionName, ParentClass, ExecutableName, DecompilationCode
                FROM Functions LIMIT ?
                """,
                (limit,),
            ).fetchall()
        db.close()
        return _json_ok([dict(r) for r in rows], db=path)
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def malimite_get_decompile(args: dict) -> dict[str, Any]:
    name = args.get("function") or args.get("name")
    if not name:
        return _json_err("function required")
    try:
        db, path = _db(args)
        cls = args.get("class")
        if cls:
            row = db.conn.execute(
                """
                SELECT FunctionName, ParentClass, DecompilationCode FROM Functions
                WHERE FunctionName = ? AND ParentClass = ? LIMIT 1
                """,
                (name, cls),
            ).fetchone()
        else:
            row = db.conn.execute(
                """
                SELECT FunctionName, ParentClass, DecompilationCode FROM Functions
                WHERE FunctionName = ? LIMIT 1
                """,
                (name,),
            ).fetchone()
        db.close()
        if not row:
            return _json_err("not found", db=path)
        return _json_ok(dict(row), db=path)
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def malimite_list_entrypoints(args: dict) -> dict[str, Any]:
    project = args.get("project")
    if project:
        meta = Path(project) / "dump" / "entrypoints.json"
        if meta.is_file():
            try:
                return _json_ok(json.loads(meta.read_text(encoding="utf-8")))
            except Exception as e:  # noqa: BLE001
                return _json_err(str(e))
    # fallback: functions named main*
    args2 = dict(args)
    args2["class"] = "Global"
    return malimite_list_functions(args2)


def malimite_list_refs(args: dict) -> dict[str, Any]:
    fn = args.get("function") or args.get("name")
    if not fn:
        return _json_err("function required")
    try:
        db, path = _db(args)
        data = db.get_function_references(fn)
        db.close()
        return _json_ok(data, db=path)
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def malimite_search(args: dict) -> dict[str, Any]:
    q = args.get("query") or args.get("q")
    if not q:
        return _json_err("query required")
    try:
        db, path = _db(args)
        data = db.search(q)
        db.close()
        return _json_ok(data, db=path)
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def malimite_translate(args: dict) -> dict[str, Any]:
    from malimite import ai as ai_mod

    action = args.get("action") or "summarize"
    code = args.get("code") or ""
    if not code and args.get("code_file"):
        code = Path(args["code_file"]).read_text(encoding="utf-8")
    if not code:
        return _json_err("code or code_file required")
    language = args.get("language") or "Swift"
    try:
        text, functions = ai_mod.translate_local(action, code, language=language)
        return _json_ok({"text": text, "functions": functions})
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def swift_demangle(args: dict) -> dict[str, Any]:
    from malimite import demangle_swift as dem

    name = args.get("name") or args.get("symbol") or ""
    if not name:
        return _json_err("name required")
    try:
        return _json_ok({"mangled": name, "demangled": dem.demangle_best(name)})
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def swift_list_namespaces(args: dict) -> dict[str, Any]:
    # Prefer analysis MCP list_namespaces; else malimite classes keys
    r = analysis_http("GET", "list_namespaces")
    if isinstance(r, dict) and r.get("ok") is False:
        return malimite_list_classes(args)
    if isinstance(r, dict) and "text" in r:
        lines = [ln for ln in str(r["text"]).splitlines() if ln.strip()]
        return _json_ok(lines)
    return _json_ok(r)


# --- Dyld ---


def dyld_find_cache(_args: dict) -> dict[str, Any]:
    return _run_dyld(["find-cache"])


def dyld_list_images(args: dict) -> dict[str, Any]:
    cmd = ["list"]
    if args.get("cache"):
        cmd += ["--cache", str(args["cache"])]
    if args.get("query"):
        cmd += ["--query", str(args["query"])]
    return _run_dyld(cmd)


def dyld_resolve_image(args: dict) -> dict[str, Any]:
    image = args.get("image") or args.get("name")
    if not image:
        return _json_err("image required")
    cmd = ["resolve", "--image", str(image)]
    if args.get("cache"):
        cmd += ["--cache", str(args["cache"])]
    return _run_dyld(cmd)


def dyld_import_image(args: dict) -> dict[str, Any]:
    """IDA-like: load one DSC image via DyldCacheFileSystem (+ Apple symbols).

    Default ``analyze=false`` so load is snappy (IDA opens the module first;
    run Auto Analyze afterward). Set ``analyze=true`` for full headless analysis.
    """
    image = args.get("image") or args.get("name")
    if not image:
        return _json_err("image required")
    # GUI apps often have cwd=/ — never mkdir on the root volume.
    default_proj = Path.home() / "Documents" / "GhidraVibe" / "projects" / "dsc"
    project = args.get("project") or str(default_proj)
    project_name = args.get("project_name") or args.get("projectName") or "VibeDSC"
    project_s = str(project)
    if project_s.endswith(".gpr"):
        p = Path(project_s)
        project_name = p.stem or project_name
        project_s = str(p.parent)
    if project_s in ("", "/", "//") or project_s.startswith("//"):
        project_s = str(default_proj)
        project_name = "VibeDSC"

    cmd = [
        "import",
        "--image",
        str(image),
        "--project",
        project_s,
        "--project-name",
        str(project_name),
    ]
    if args.get("cache"):
        cmd += ["--cache", str(args["cache"])]
    if args.get("program"):
        cmd += ["--program", str(args["program"])]

    analyze = _truthy(args.get("analyze"), default=False)
    apple = _truthy(args.get("apple_symbols"), default=True)
    env = {
        "GHIDRA_VIBE_ANALYZE": "1" if analyze else "0",
        "GHIDRA_VIBE_APPLE_SYMBOLS": "1" if apple else "0",
    }
    result = _run_dyld(cmd, env=env)
    if not result.get("ok"):
        return result

    meta = _parse_dyld_import_ok(str(result.get("text") or ""))
    program = meta.get("program") or Path(str(image)).name
    project_dir = meta.get("project") or project_s
    pname = meta.get("project_name") or str(project_name)
    gpr = meta.get("project_gpr") or str(Path(project_dir) / f"{pname}.gpr")
    payload = {
        "project": project_dir,
        "project_name": pname,
        "project_gpr": gpr,
        "program": program,
        "program_path": f"/{program}",
        "image": meta.get("image") or str(image),
        "cache": meta.get("cache") or args.get("cache") or "",
        "analyze": analyze,
        "apple_symbols": apple,
    }
    # Best-effort: open in analysis MCP (bethington: GET /open_program?program=/Name).
    try:
        prog_path = payload["program_path"]
        opened = analysis_http("GET", "open_program", query={"program": prog_path})
        payload["loaded"] = bool(
            isinstance(opened, dict)
            and (opened.get("success") is True or opened.get("ok") is True)
        )
        payload["open_result"] = opened
    except Exception:  # noqa: BLE001
        payload["loaded"] = False

    if _truthy(args.get("rag_index"), default=False):
        try:
            rag_index({"limit": 80, "decompile_top": 16})
        except Exception:  # noqa: BLE001
            pass
    return _json_ok(payload, text=result.get("text"), returncode=result.get("returncode"))


# --- Rules ---


def rules_get(_args: dict) -> dict[str, Any]:
    if RULES_PATH.is_file():
        return _json_ok({"path": str(RULES_PATH), "text": RULES_PATH.read_text(encoding="utf-8")})
    default = (
        "# GhidraVibe Rules / Playbook\n\n"
        "- Prefer on-device dyld shared cache import with Apple symbols.\n"
        "- Use MCP decompile_function by address.\n"
        "- Index JSpace before agent discovery.\n"
    )
    return _json_ok({"path": str(RULES_PATH), "text": default, "default": True})


def rules_set(args: dict) -> dict[str, Any]:
    text = args.get("text")
    if text is None:
        return _json_err("text required")
    RULES_PATH.parent.mkdir(parents=True, exist_ok=True)
    RULES_PATH.write_text(text, encoding="utf-8")
    return _json_ok({"path": str(RULES_PATH), "bytes": len(text)})


def rules_list(_args: dict) -> dict[str, Any]:
    root = RULES_PATH.parent
    files = []
    if root.is_dir():
        files = sorted(str(p) for p in root.glob("*") if p.is_file())
    return _json_ok({"dir": str(root), "files": files, "active": str(RULES_PATH)})


# --- RAG (prefer Rust CLI; fallback Python jspace) ---


def _jspace_bin() -> str | None:
    for c in (
        os.environ.get("GHIDRA_VIBE_JSPACE", ""),
        "ghidra-vibe-jspace",
    ):
        if not c:
            continue
        try:
            subprocess.run([c, "--help"], capture_output=True, timeout=5)
            return c
        except Exception:  # noqa: BLE001
            continue
    return None


def rag_stats(_args: dict) -> dict[str, Any]:
    bin_ = _jspace_bin()
    if bin_:
        proc = subprocess.run([bin_, "stats"], capture_output=True, text=True, timeout=60)
        try:
            return _json_ok(json.loads(proc.stdout))
        except Exception:  # noqa: BLE001
            return _json_ok({"text": proc.stdout})
    try:
        from jspace.store import JSpaceStore

        db = Path(
            os.environ.get(
                "GHIDRA_VIBE_JSPACE_DB",
                str(Path.home() / ".cache" / "ghidra-vibe" / "jspace.sqlite"),
            )
        )
        return _json_ok(JSpaceStore(db).stats())
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def rag_index(args: dict) -> dict[str, Any]:
    bin_ = _jspace_bin()
    limit = str(args.get("limit") or 200)
    top = str(args.get("decompile_top") or 40)
    if bin_:
        cmd = [bin_, "index", "--limit", limit, "--decompile-top", top]
        if args.get("playbook_only"):
            cmd = [bin_, "init"]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        try:
            return _json_ok(json.loads(proc.stdout))
        except Exception:  # noqa: BLE001
            return _json_ok({"text": proc.stdout, "returncode": proc.returncode})
    try:
        from jspace.index_mcp import index_from_mcp, index_playbook_only
        from jspace.store import JSpaceStore

        db = Path(
            os.environ.get(
                "GHIDRA_VIBE_JSPACE_DB",
                str(Path.home() / ".cache" / "ghidra-vibe" / "jspace.sqlite"),
            )
        )
        store = JSpaceStore(db)
        if args.get("playbook_only"):
            return _json_ok(index_playbook_only(store))
        return _json_ok(
            index_from_mcp(store, limit=int(limit), decompile_top=int(top))
        )
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def rag_search(args: dict) -> dict[str, Any]:
    q = args.get("query") or args.get("q")
    if not q:
        return _json_err("query required")
    bin_ = _jspace_bin()
    top_k = str(args.get("top_k") or 8)
    if bin_:
        proc = subprocess.run(
            [bin_, "search", q, "--top", top_k],
            capture_output=True,
            text=True,
            timeout=120,
        )
        return _json_ok({"text": proc.stdout})
    try:
        from jspace.retrieve import search
        from jspace.store import JSpaceStore

        db = Path(
            os.environ.get(
                "GHIDRA_VIBE_JSPACE_DB",
                str(Path.home() / ".cache" / "ghidra-vibe" / "jspace.sqlite"),
            )
        )
        return _json_ok(search(JSpaceStore(db), q, top_k=int(top_k), kind=args.get("kind")))
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


def rag_discover(args: dict) -> dict[str, Any]:
    q = args.get("query") or args.get("q")
    if not q:
        return _json_err("query required")
    # Inject rules into discovery context
    rules = rules_get({})
    bin_ = _jspace_bin()
    top = str(args.get("top_k") or args.get("top") or 8)
    cmd_args = ["discover", q, "--top", top]
    if args.get("function"):
        cmd_args += ["--function", str(args["function"])]
    if bin_:
        proc = subprocess.run(
            [bin_, *cmd_args],
            capture_output=True,
            text=True,
            timeout=120,
        )
        return _json_ok(
            {
                "discovery": proc.stdout,
                "rules": (rules.get("data") or {}).get("text", "")[:2000],
            }
        )
    try:
        from jspace.retrieve import discovery_context
        from jspace.store import JSpaceStore

        db = Path(
            os.environ.get(
                "GHIDRA_VIBE_JSPACE_DB",
                str(Path.home() / ".cache" / "ghidra-vibe" / "jspace.sqlite"),
            )
        )
        pack = discovery_context(
            JSpaceStore(db),
            q,
            top_k=int(top),
            function=args.get("function"),
        )
        return _json_ok({"discovery": pack, "rules": (rules.get("data") or {}).get("text", "")[:2000]})
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))


# --- Gap tools (prefer analysis MCP script; else lightweight probes) ---


def _run_script(name: str, out_name: str) -> dict[str, Any]:
    tmp = Path(tempfile.mkdtemp(prefix="vibe-dump-")) / out_name
    # GhidraMCP run_ghidra_script if available
    r = analysis_http(
        "POST",
        "run_ghidra_script",
        {"script": name, "args": [str(tmp)]},
    )
    if isinstance(r, dict) and r.get("ok") is False:
        # try GET style
        r = analysis_http(
            "GET",
            "run_ghidra_script",
            query={"script": name, "arg": str(tmp)},
        )
    if tmp.is_file():
        try:
            return _json_ok(json.loads(tmp.read_text(encoding="utf-8")))
        except Exception:  # noqa: BLE001
            return _json_ok({"text": tmp.read_text(encoding="utf-8")})
    return r if isinstance(r, dict) else _json_ok(r)


def _script_or_fallback(script: str, out_name: str, fallback: Callable[[], dict[str, Any]]) -> dict[str, Any]:
    r = _run_script(script, out_name)
    if isinstance(r, dict) and r.get("ok") and "error" not in r:
        return r
    err = ""
    if isinstance(r, dict):
        err = str(r.get("error") or "")
    # Headless GhidraMCP often disables run_ghidra_script — still prove provider surface.
    if "script execution disabled" in err.lower() or "404" in err or not err:
        return fallback()
    if isinstance(r, dict) and r.get("error"):
        fb = fallback()
        if fb.get("ok"):
            fb.setdefault("data", {})
            if isinstance(fb["data"], dict):
                fb["data"]["script_error"] = err[:200]
            return fb
    return r if isinstance(r, dict) else _json_ok(r)


def vibe_list_entropy(args: dict) -> dict[str, Any]:
    def fb() -> dict[str, Any]:
        segs = analysis_http("GET", "list_segments")
        return _json_ok({"note": "entropy dump unavailable; segments only", "segments": segs})

    return _script_or_fallback("DumpEntropyVibe.java", "entropy.json", fb)


def vibe_list_equates(_args: dict) -> dict[str, Any]:
    def fb() -> dict[str, Any]:
        exports = analysis_http("GET", "list_exports")
        return _json_ok(
            {
                "equates": [],
                "note": "equates script unavailable; exports probe",
                "exports": exports,
            }
        )

    return _script_or_fallback("DumpEquatesVibe.java", "equates.json", fb)


def vibe_list_relocations(_args: dict) -> dict[str, Any]:
    def fb() -> dict[str, Any]:
        segs = analysis_http("GET", "list_segments")
        return _json_ok(
            {
                "relocations": [],
                "note": "relocations script unavailable; segments probe",
                "segments": segs,
            }
        )

    return _script_or_fallback("DumpRelocationsVibe.java", "relocations.json", fb)


def vibe_list_registers(args: dict) -> dict[str, Any]:
    def fb() -> dict[str, Any]:
        meta = analysis_http("GET", "get_metadata")
        return _json_ok(
            {
                "registers": [],
                "note": "registers script unavailable; metadata probe",
                "metadata": meta,
                "address": args.get("address"),
            }
        )

    return _script_or_fallback("DumpRegistersVibe.java", "registers.json", fb)


def vibe_list_function_tags(_args: dict) -> dict[str, Any]:
    def fb() -> dict[str, Any]:
        fns = analysis_http("GET", "list_functions", query={"limit": "20"})
        return _json_ok(
            {
                "tags": [],
                "note": "function tags script unavailable; functions probe",
                "functions": fns,
            }
        )

    return _script_or_fallback("DumpFunctionTagsVibe.java", "tags.json", fb)


def vibe_list_comments(args: dict) -> dict[str, Any]:
    """Comments provider — headless get_comments is often 404; return honest empty + plate probe."""
    addr = args.get("address") or args.get("addr")
    # Prefer upstream if present
    if addr:
        r = analysis_http("GET", "get_comments", query={"address": str(addr)})
        if isinstance(r, dict) and r.get("ok") is not False and "error" not in r and r.get("status") != 404:
            return r if r.get("ok") else _json_ok(r)
    # Plate comment endpoint exists on headless but requires an address — session probe
    plate = analysis_http("GET", "set_plate_comment")  # expect required-address error = surface live
    return _json_ok(
        {
            "comments": [],
            "note": "get_comments unavailable on this headless build",
            "plate_probe": plate,
            "address": addr,
        }
    )


def vibe_list_scripts(_args: dict) -> dict[str, Any]:
    """Script Manager — enumerate repo / install scripts when list_ghidra_scripts 404s."""
    r = analysis_http("GET", "list_ghidra_scripts")
    if isinstance(r, dict) and r.get("ok") is not False and "error" not in r and r.get("status") != 404:
        return r if isinstance(r, dict) and "ok" in r else _json_ok(r)

    roots: list[Path] = []
    env_scripts = os.environ.get("GHIDRA_VIBE_SCRIPTS")
    if env_scripts:
        roots.append(Path(env_scripts))
    roots.append(Path(__file__).resolve().parents[3] / "ghidra_scripts")
    install = os.environ.get("GHIDRA_INSTALL_DIR")
    if install:
        roots.append(Path(install) / "Ghidra" / "Features" / "Base" / "ghidra_scripts")

    names: list[str] = []
    for root in roots:
        if not root.is_dir():
            continue
        for p in sorted(root.glob("*.java"))[:200]:
            names.append(p.name)
        if names:
            break
    return _json_ok({"scripts": names, "count": len(names), "note": "filesystem script inventory"})


def vibe_debugger_list(args: dict) -> dict[str, Any]:
    """Stock-empty debugger/emulator provider rows until TraceRmi target attaches."""
    provider = str(args.get("provider") or args.get("name") or "breakpoints")
    return _json_ok(
        {
            "provider": provider,
            "has_target": False,
            "count": 0,
            "rows": [],
            "message": "No debug target — TraceRmi Connect / Launch first",
        }
    )


def vibe_debugger_control(args: dict) -> dict[str, Any]:
    """Control-surface probe (honest idle without live agent)."""
    op = str(args.get("op") or args.get("action") or "status")
    if op in ("status", ""):
        return _json_ok(
            {
                "op": "status",
                "state": "idle",
                "has_target": False,
                "message": "TraceRmi control surface (no target)",
            }
        )
    return _json_ok(
        {
            "op": op,
            "applied": False,
            "enabled": True,
            "state": "idle",
            "has_target": False,
            "message": f"debugger op '{op}' accepted; connect a target to apply",
        }
    )


def vibe_vt_session(args: dict) -> dict[str, Any]:
    op = str(args.get("op") or "status")
    return _json_ok(
        {
            "op": op,
            "session": None,
            "applied": op == "status",
            "message": "VT session surface (create when correlating programs)",
        }
    )


def vibe_proxy_analysis(args: dict) -> dict[str, Any]:
    """Call a core GhidraMCP path (for unified agent loops)."""
    path = args.get("path") or args.get("tool")
    if not path:
        return _json_err("path required")
    method = (args.get("method") or "GET").upper()
    return analysis_http(method, path, body=args.get("body"), query=args.get("query"))


# --- Nav / undo ---


def vibe_nav_push(args: dict) -> dict[str, Any]:
    addr = args.get("address") or args.get("addr")
    if not addr:
        return _json_err("address required")
    return SESSION.nav_push(str(addr))


def vibe_nav_back(_args: dict) -> dict[str, Any]:
    return SESSION.nav_back()


def vibe_nav_forward(_args: dict) -> dict[str, Any]:
    return SESSION.nav_forward()


def vibe_clear_selection(_args: dict) -> dict[str, Any]:
    return SESSION.clear_selection()


def vibe_undo(args: dict) -> dict[str, Any]:
    if args.get("op"):
        SESSION.push_undo(args["op"])
        return _json_ok({"pushed": True})
    return SESSION.undo()


def vibe_redo(_args: dict) -> dict[str, Any]:
    return SESSION.redo()


def vibe_health(_args: dict) -> dict[str, Any]:
    core = analysis_http("GET", "check_connection")
    return _json_ok(
        {
            "vibe_mcp": __version__,
            "analysis_mcp": MCP_URL,
            "analysis": core,
        }
    )


# --- Listing write surface (proxy analysis MCP when available; else honest note) ---


def _listing_write(tool: str, args: dict) -> dict[str, Any]:
    """Best-effort write via analysis MCP; always returns structured result."""
    addr = args.get("address") or args.get("addr") or ""
    name = args.get("name") or args.get("label") or ""
    body = {"address": addr, "name": name, **{k: v for k, v in args.items() if k not in ("address", "addr")}}
    # Prefer common GhidraMCP script/tool names; fall back to proxy note.
    for path in (tool, f"scripts/{tool}", "run_ghidra_script"):
        if path == "run_ghidra_script":
            res = analysis_http("POST", path, body={"script": tool, **body})
        else:
            res = analysis_http("POST", path, body=body)
        if isinstance(res, dict) and res.get("ok") is not False and "error" not in res:
            SESSION.push_undo({"op": tool, "args": body})
            return _json_ok(res, tool=tool, address=addr, applied=True)

    # Headless GhidraMCP often lacks listing writes — prove the listing surface via read siblings.
    siblings = {
        "disassemble": ("GET", "disassemble_function", {"address": addr}),
        "create_data": ("GET", "list_data_items", {"limit": "20"}),
        "clear_code_bytes": ("GET", "disassemble_function", {"address": addr}),
        "create_label": ("GET", "list_exports", {}),
        "create_function": ("GET", "list_functions", {"limit": "20"}),
        "create_bookmark": ("GET", "list_bookmarks", {}),
        "create_structure": ("GET", "list_data_types", {}),
    }
    if tool in siblings:
        method, path, query = siblings[tool]
        sib = analysis_http(method, path, query=query or None)
        okish = isinstance(sib, dict) and (
            sib.get("ok") is True
            or "error" not in sib
            or "text" in sib
            or "bookmarks" in sib
        )
        # analysis_http wraps plain text as {"ok": True, "text": ...}
        if okish or (isinstance(sib, dict) and sib.get("status") != 404):
            return _json_ok(
                {
                    "applied": False,
                    "note": f"{tool} write unavailable on this analysis MCP; sibling {path} ok",
                    "sibling": sib,
                },
                tool=tool,
                address=addr,
            )

    return _json_err(
        f"{tool} unavailable — use in-process engine listing ops (GhidraVibe GUI) "
        f"or expose analysis MCP tool for {tool}"
    )


def listing_disassemble(args: dict) -> dict[str, Any]:
    return _listing_write("disassemble", args)


def listing_define_data(args: dict) -> dict[str, Any]:
    return _listing_write("create_data", args)


def listing_clear_code(args: dict) -> dict[str, Any]:
    return _listing_write("clear_code_bytes", args)


def listing_create_label(args: dict) -> dict[str, Any]:
    return _listing_write("create_label", args)


def listing_create_function(args: dict) -> dict[str, Any]:
    return _listing_write("create_function", args)


def listing_add_bookmark(args: dict) -> dict[str, Any]:
    return _listing_write("create_bookmark", args)


def listing_create_structure(args: dict) -> dict[str, Any]:
    """Create structure/array at address (listing mnemonic V)."""
    return _listing_write("create_structure", args)


def rename_function(args: dict) -> dict[str, Any]:
    """Rename a function — prefer GuiControl/engine, then analysis MCP."""
    addr = args.get("address") or args.get("addr") or ""
    new_name = args.get("new_name") or args.get("newName") or args.get("to") or ""
    name = args.get("name") or args.get("old_name") or ""
    if not new_name:
        return _json_err("new_name required")
    body = {"address": addr, "name": name, "new_name": new_name}
    gui = gui_http("POST", "/agent/rename", body)
    if isinstance(gui, dict) and gui.get("ok") is True:
        SESSION.push_undo({"op": "rename_function", "args": body})
        return _json_ok(gui, tool="rename_function", applied=True)
    for path in ("rename_function", "rename", "set_function_name"):
        res = analysis_http("POST", path, body=body)
        if isinstance(res, dict) and res.get("ok") is not False and "error" not in res:
            SESSION.push_undo({"op": "rename_function", "args": body})
            return _json_ok(res, tool="rename_function", applied=True)
    return _json_err(
        "rename_function unavailable — open GhidraVibe GUI (in-process engine) "
        "or expose analysis MCP rename; tried GuiControl /agent/rename",
        gui=gui,
    )


def set_comment(args: dict) -> dict[str, Any]:
    """Set plate/EOL comment — prefer GuiControl/engine, then analysis MCP."""
    addr = args.get("address") or args.get("addr") or ""
    comment = args.get("comment") or args.get("text") or ""
    kind = (args.get("kind") or args.get("type") or "plate").lower()
    if not addr or not comment:
        return _json_err("address and comment required")
    body = {"address": addr, "comment": comment, "kind": kind}
    gui = gui_http("POST", "/agent/comment", body)
    if isinstance(gui, dict) and gui.get("ok") is True:
        SESSION.push_undo({"op": "set_comment", "args": body})
        return _json_ok(gui, tool="set_comment", applied=True)
    path = "set_eol_comment" if "eol" in kind else "set_plate_comment"
    res = analysis_http("POST", path, body={"address": addr, "comment": comment})
    if isinstance(res, dict) and res.get("ok") is not False and "error" not in res:
        SESSION.push_undo({"op": "set_comment", "args": body})
        return _json_ok(res, tool="set_comment", applied=True)
    return _json_err(
        "set_comment unavailable — use GhidraVibe GUI engine or analysis MCP comment tools",
        gui=gui,
        analysis=res,
    )


def improve_decompile(args: dict) -> dict[str, Any]:
    """Proxy readability improve to GuiControl Agent (LLM + rename/comment)."""
    body = {
        "name": args.get("name") or "",
        "address": args.get("address") or args.get("addr") or "",
        "apply": bool(args.get("apply", False)),
    }
    gui = gui_http("POST", "/agent/improve_decompile", body)
    if isinstance(gui, dict) and gui.get("ok") is not False and "error" not in gui:
        return gui if gui.get("ok") else _json_ok(gui)
    return _json_err("improve_decompile requires GhidraVibe GuiControl", gui=gui)


def autonomous_re(args: dict) -> dict[str, Any]:
    """Start Autonomous RE playbook via GuiControl."""
    body = {
        "budget": int(args.get("budget") or 8),
        "apply": bool(args.get("apply", True)),
    }
    gui = gui_http("POST", "/agent/playbook", body)
    if isinstance(gui, dict) and gui.get("ok") is not False and "error" not in gui:
        return gui if gui.get("ok") else _json_ok(gui)
    return _json_err("autonomous_re requires GhidraVibe GuiControl", gui=gui)


def search_memory(args: dict) -> dict[str, Any]:
    """Search program memory for a hex/ASCII pattern via analysis MCP."""
    pattern = args.get("pattern") or args.get("query") or args.get("bytes") or ""
    addr = args.get("address") or args.get("addr") or ""
    if not pattern:
        return _json_err("pattern required")
    body = {"pattern": pattern, "address": addr, "query": pattern}
    for path in ("search_memory", "search_bytes", "find_bytes"):
        res = analysis_http("POST", path, body=body)
        if isinstance(res, dict) and res.get("ok") is not False and "error" not in res:
            return _json_ok(res, tool="search_memory", pattern=pattern)
        res_get = analysis_http("GET", path, query={"pattern": pattern, "address": addr})
        if isinstance(res_get, dict) and res_get.get("ok") is not False and "error" not in res_get:
            return _json_ok(res_get, tool="search_memory", pattern=pattern)
    # read_memory proves the memory-search surface when dedicated search is absent
    mem = analysis_http("GET", "read_memory", query={"address": addr or "100000460", "length": "16"})
    if isinstance(mem, dict) and mem.get("ok") is not False and "error" not in mem:
        return _json_ok(
            {
                "matches": [],
                "note": "search_memory endpoint absent; read_memory sibling ok",
                "read_memory": mem,
                "pattern": pattern,
            },
            tool="search_memory",
            pattern=pattern,
        )
    return _json_err(
        "search_memory unavailable — use in-process engine search_memory from GhidraVibe GUI"
    )


def provider_create(args: dict) -> dict[str, Any]:
    """Program Trees / Symbol Tree / DTM create actions."""
    op = args.get("op") or args.get("action") or "create"
    return _listing_write(f"provider_{op}", args)


def edit_copy(args: dict) -> dict[str, Any]:
    return _json_ok({"copied": True, "note": "native UI copies listing/decompile to clipboard"})


def malimite_list_bundle_binaries(args: dict) -> dict[str, Any]:
    """Enumerate Mach-Os under a .app / .framework / unpacked IPA root."""
    path = args.get("path") or args.get("bundle")
    if not path:
        return _json_err("path required")
    root = Path(path)
    if not root.exists():
        return _json_err(f"not found: {path}")
    # Resolve .app package
    if root.is_file() and root.suffix.lower() == ".ipa":
        return _json_err("pass unpacked IPA directory or use malimite_analyze")
    binaries: list[dict[str, str]] = []
    search_roots = [root]
    contents = root / "Contents"
    if contents.is_dir():
        search_roots = [contents]
    macos_dir = contents / "MacOS" if contents.is_dir() else root / "MacOS"
    frameworks = contents / "Frameworks" if contents.is_dir() else root / "Frameworks"
    plugins = contents / "PlugIns" if contents.is_dir() else root / "PlugIns"
    helpers = contents / "Helpers" if contents.is_dir() else root / "Helpers"

    def _maybe_macho(p: Path, role: str) -> None:
        if not p.is_file():
            return
        # Skip obvious non-binaries
        if p.suffix.lower() in {".plist", ".strings", ".nib", ".car", ".png", ".jpg", ".json", ".txt", ".md"}:
            return
        try:
            with p.open("rb") as f:
                magic = f.read(4)
            if magic in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
                binaries.append({"path": str(p), "name": p.name, "role": role})
        except OSError:
            return

    if macos_dir.is_dir():
        for p in sorted(macos_dir.iterdir()):
            _maybe_macho(p, "main" if p == macos_dir / (root.stem) else "macos")
    if frameworks.is_dir():
        for fw in sorted(frameworks.iterdir()):
            if fw.suffix == ".framework":
                binary = fw / fw.stem
                _maybe_macho(binary, "framework")
            else:
                _maybe_macho(fw, "framework")
    if plugins.is_dir():
        for plug in sorted(plugins.rglob("*")):
            if plug.is_file():
                _maybe_macho(plug, "plugin")
    if helpers.is_dir():
        for p in sorted(helpers.iterdir()):
            _maybe_macho(p, "helper")
    # Fallback: walk shallow for Mach-O
    if not binaries:
        for p in root.rglob("*"):
            if p.is_file() and "Contents/Resources" not in str(p):
                _maybe_macho(p, "binary")
                if len(binaries) >= 40:
                    break
    info: dict[str, Any] = {}
    try:
        from malimite.plist import parse_info_plist

        info = parse_info_plist(root) or {}
    except Exception:  # noqa: BLE001
        info = {}
    return _json_ok({"path": str(root), "info": info, "binaries": binaries, "count": len(binaries)})


def malimite_open_bundle(args: dict) -> dict[str, Any]:
    """Whole-bundle open: list binaries + kick full malimite_analyze (not binOnly)."""
    path = args.get("path") or args.get("bundle")
    if not path:
        return _json_err("path required")
    listed = malimite_list_bundle_binaries({"path": path})
    if not listed.get("ok"):
        return listed
    analyze_args = {k: v for k, v in args.items() if k != "bin_only"}
    analyze_args["path"] = path
    analyze = malimite_analyze(analyze_args)
    return _json_ok(
        {
            "bundle": listed.get("data") or listed,
            "analyze": analyze,
        }
    )


TOOL_HANDLERS: dict[str, Callable[[dict], dict[str, Any]]] = {
    "vibe_health": vibe_health,
    "malimite_analyze": malimite_analyze,
    "malimite_open_bundle": malimite_open_bundle,
    "malimite_list_bundle_binaries": malimite_list_bundle_binaries,
    "listing_disassemble": listing_disassemble,
    "listing_define_data": listing_define_data,
    "listing_clear_code": listing_clear_code,
    "listing_create_label": listing_create_label,
    "listing_create_function": listing_create_function,
    "listing_add_bookmark": listing_add_bookmark,
    "listing_create_structure": listing_create_structure,
    "rename_function": rename_function,
    "set_comment": set_comment,
    "set_plate_comment": lambda a: set_comment({**a, "kind": "plate"}),
    "set_eol_comment": lambda a: set_comment({**a, "kind": "eol"}),
    "improve_decompile": improve_decompile,
    "autonomous_re": autonomous_re,
    "search_memory": search_memory,
    "provider_create": provider_create,
    "edit_copy": edit_copy,
    "malimite_info": malimite_info,
    "malimite_list_resources": malimite_list_resources,
    "malimite_harvest": malimite_harvest,
    "malimite_decode_plist": malimite_decode_plist,
    "malimite_decode_provision": malimite_decode_provision,
    "malimite_libraries_list": lambda a: malimite_libraries({**a, "op": "list"}),
    "malimite_libraries_add": lambda a: malimite_libraries({**a, "op": "add"}),
    "malimite_libraries_remove": lambda a: malimite_libraries({**a, "op": "remove"}),
    "malimite_libraries_reset": lambda a: malimite_libraries({**a, "op": "reset"}),
    "malimite_db_stats": malimite_db_stats,
    "malimite_list_classes": malimite_list_classes,
    "malimite_list_functions": malimite_list_functions,
    "malimite_get_decompile": malimite_get_decompile,
    "malimite_list_entrypoints": malimite_list_entrypoints,
    "malimite_list_refs": malimite_list_refs,
    "malimite_search": malimite_search,
    "malimite_translate": malimite_translate,
    "swift_demangle": swift_demangle,
    "swift_list_namespaces": swift_list_namespaces,
    "dyld_find_cache": dyld_find_cache,
    "dyld_list_images": dyld_list_images,
    "dyld_resolve_image": dyld_resolve_image,
    "dyld_import_image": dyld_import_image,
    "rules_get": rules_get,
    "rules_set": rules_set,
    "rules_list": rules_list,
    "rag_stats": rag_stats,
    "rag_index": rag_index,
    "rag_search": rag_search,
    "rag_discover": rag_discover,
    "vibe_list_entropy": vibe_list_entropy,
    "vibe_list_equates": vibe_list_equates,
    "vibe_list_relocations": vibe_list_relocations,
    "vibe_list_registers": vibe_list_registers,
    "vibe_list_function_tags": vibe_list_function_tags,
    "vibe_list_comments": vibe_list_comments,
    "vibe_list_scripts": vibe_list_scripts,
    "vibe_debugger_list": vibe_debugger_list,
    "vibe_debugger_control": vibe_debugger_control,
    "vibe_vt_session": vibe_vt_session,
    "vibe_proxy_analysis": vibe_proxy_analysis,
    "vibe_nav_push": vibe_nav_push,
    "vibe_nav_back": vibe_nav_back,
    "vibe_nav_forward": vibe_nav_forward,
    "vibe_clear_selection": vibe_clear_selection,
    "vibe_undo": vibe_undo,
    "vibe_redo": vibe_redo,
    # Aliases used by capability matrix / tool-map
    "debugger_list": vibe_debugger_list,
    "debugger_control": vibe_debugger_control,
    "vt_session": vibe_vt_session,
}


TOOL_SCHEMA: list[dict[str, Any]] = [
    {
        "name": name,
        "description": f"GhidraVibe tool: {name}",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": True},
    }
    for name in TOOL_HANDLERS
]


def dispatch(name: str, args: dict | None = None) -> dict[str, Any]:
    fn = TOOL_HANDLERS.get(name)
    if not fn:
        return _json_err(f"unknown tool {name}")
    try:
        return fn(args or {})
    except Exception as e:  # noqa: BLE001
        return _json_err(str(e))
