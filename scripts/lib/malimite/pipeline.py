"""IPA unpack / analyze pipeline wiring headless Ghidra dumps into MalimiteDB."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import zipfile
from pathlib import Path
from typing import Any, Dict, Optional, Union

from . import plist as plist_mod
from .db import MalimiteDB
from .resources import harvest

PathLike = Union[str, Path]


def unpack_ipa(ipa: PathLike, out: PathLike) -> Path:
    """Extract an IPA zip into ``out`` and return the ``Payload/*.app`` path."""
    ipa_path = Path(ipa)
    out_path = Path(out)
    if not ipa_path.is_file():
        raise FileNotFoundError(f"IPA not found: {ipa_path}")
    out_path.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(ipa_path, "r") as zf:
        zf.extractall(out_path)

    payload = out_path / "Payload"
    apps = sorted(payload.glob("*.app")) if payload.is_dir() else []
    if not apps:
        # Some archives nest oddly — search one level deeper
        apps = sorted(out_path.rglob("*.app"))
    if not apps:
        raise FileNotFoundError(f"No Payload/*.app in IPA: {ipa_path}")
    return apps[0]


def find_bin(app: PathLike) -> Path:
    """Resolve the main Mach-O executable inside an ``.app`` bundle."""
    app_path = Path(app)
    if not app_path.is_dir():
        raise NotADirectoryError(f"Not an app bundle: {app_path}")

    info = plist_mod.parse_info_plist(app_path)
    exe = info.get("CFBundleExecutable")
    candidates = []
    if exe:
        candidates.append(app_path / exe)
        candidates.append(app_path / "Contents" / "MacOS" / exe)

    for cand in candidates:
        if cand.is_file():
            return cand

    # Fallback: look for Mach-O magic in app root / Contents/MacOS
    search_dirs = [app_path, app_path / "Contents" / "MacOS"]
    for d in search_dirs:
        if not d.is_dir():
            continue
        for f in sorted(d.iterdir()):
            if not f.is_file():
                continue
            try:
                magic = f.read_bytes()[:4]
            except OSError:
                continue
            # MH_MAGIC / MH_CIGAM / FAT
            if magic in (b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",
                         b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
                         b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
                return f

    raise FileNotFoundError(f"Could not find main Mach-O in {app_path}")


def _resolve_headless(headless: Optional[PathLike]) -> Optional[Path]:
    if headless:
        p = Path(headless)
        if p.is_file() and os.access(p, os.X_OK):
            return p
    env = os.environ.get("GHIDRA_VIBE_HEADLESS")
    if env and Path(env).is_file():
        return Path(env)
    which = shutil.which("ghidra-analyzeHeadless")
    if which:
        return Path(which)
    # Repo-relative wrapper
    here = Path(__file__).resolve()
    wrapper = here.parents[2] / "ghidra-vibe-analyzeHeadless"
    if wrapper.is_file():
        return wrapper
    return None


def _script_exists(scripts_dir: Path, name: str) -> bool:
    return (scripts_dir / name).is_file()


def load_dump_into_db(
    db: MalimiteDB,
    classes_json: Optional[PathLike] = None,
    functions_json: Optional[PathLike] = None,
    strings_json: Optional[PathLike] = None,
) -> Dict[str, int]:
    """Import DumpClassDataVibe JSON artifacts into ``db``."""
    counts = {"classes": 0, "functions": 0, "strings": 0}
    if classes_json and Path(classes_json).is_file():
        counts["classes"] = db.import_class_json(classes_json)
    if functions_json and Path(functions_json).is_file():
        counts["functions"] = db.import_functions_json(functions_json)
    if strings_json and Path(strings_json).is_file():
        counts["strings"] = db.import_strings_json(strings_json)
    return counts


def analyze(
    bundle_or_ipa: PathLike,
    project_dir: PathLike,
    db_path: PathLike,
    headless: Optional[PathLike] = None,
    scripts_dir: Optional[PathLike] = None,
) -> Dict[str, Any]:
    """Unpack if needed, harvest resources, write info.json, optionally run headless dumps."""
    src = Path(bundle_or_ipa)
    project = Path(project_dir)
    project.mkdir(parents=True, exist_ok=True)
    work = project / "work"
    work.mkdir(parents=True, exist_ok=True)

    app: Path
    unpacked_from: Optional[Path] = None
    if src.suffix.lower() == ".ipa" or src.is_file() and zipfile.is_zipfile(src):
        unpack_dir = work / "ipa"
        if unpack_dir.exists():
            shutil.rmtree(unpack_dir)
        app = unpack_ipa(src, unpack_dir)
        unpacked_from = src
    elif src.is_dir() and (src.suffix == ".app" or (src / "Info.plist").exists()
                           or (src / "Contents" / "Info.plist").exists()):
        app = src
    else:
        raise ValueError(f"Expected .ipa or .app bundle: {src}")

    info = plist_mod.parse_info_plist(app)
    try:
        binary = find_bin(app)
    except FileNotFoundError:
        binary = None

    info_out = {
        "app": str(app),
        "binary": str(binary) if binary else None,
        "unpacked_from": str(unpacked_from) if unpacked_from else None,
        **info,
    }
    info_path = project / "info.json"
    info_path.write_text(json.dumps(info_out, indent=2) + "\n", encoding="utf-8")

    db = MalimiteDB(db_path)
    harvested = harvest(app, db)
    db.set_meta("info", json.dumps(info_out))
    db.set_meta("app_path", str(app))
    if binary:
        db.set_meta("binary", str(binary))

    result: Dict[str, Any] = {
        "app": str(app),
        "binary": str(binary) if binary else None,
        "info_json": str(info_path),
        "db_path": str(Path(db_path)),
        "resource_strings": harvested,
        "headless": None,
        "dump": None,
    }

    scripts = Path(scripts_dir) if scripts_dir else Path(__file__).resolve().parents[2] / "ghidra_scripts"
    # Prefer repo ghidra_scripts next to scripts/
    repo_scripts = Path(__file__).resolve().parents[3] / "ghidra_scripts"
    if not scripts.is_dir() and repo_scripts.is_dir():
        scripts = repo_scripts
    elif repo_scripts.is_dir():
        scripts = repo_scripts

    import_script = "ImportAppleBundle.java"
    dump_class = "DumpClassDataVibe.java"
    dump_entry = "DumpEntrypointsVibe.java"
    dump_refs = "DumpFunctionRefsVibe.java"
    have_import = _script_exists(scripts, import_script)
    have_dump = _script_exists(scripts, dump_class)
    have_entry = _script_exists(scripts, dump_entry)
    have_refs = _script_exists(scripts, dump_refs)

    hl = _resolve_headless(headless)
    if hl and binary and (have_import or have_dump):
        ghidra_proj = project / "ghidra"
        ghidra_proj.mkdir(parents=True, exist_ok=True)
        proj_name = "MalimiteAnalyze"
        program = binary.name
        dump_dir = project / "dump"
        dump_dir.mkdir(parents=True, exist_ok=True)
        entry_json = dump_dir / "entrypoints.json"
        refs_json = dump_dir / "refs.json"

        cmd = [
            str(hl),
            str(ghidra_proj),
            proj_name,
            "-scriptPath",
            str(scripts),
            "-overwrite",
            "-max-cpu",
            os.environ.get("GHIDRA_VIBE_MAX_CPU", "2"),
        ]
        if have_import:
            cmd.extend(["-preScript", import_script, str(binary), program])
        if have_dump:
            cmd.extend(["-postScript", dump_class, str(dump_dir)])
        if have_entry:
            cmd.extend(["-postScript", dump_entry, str(entry_json)])
        if have_refs:
            cmd.extend(["-postScript", dump_refs, str(refs_json)])

        env = os.environ.copy()
        env.setdefault("GHIDRA_VIBE_APPLE_SYMBOLS", "1")
        env.setdefault("GHIDRA_VIBE_ANALYZE", "1")
        proc = subprocess.run(
            cmd,
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )
        result["headless"] = {
            "cmd": cmd,
            "returncode": proc.returncode,
            "stdout_tail": (proc.stdout or "")[-4000:],
            "stderr_tail": (proc.stderr or "")[-2000:],
        }

        classes_json = dump_dir / "classes.json"
        functions_json = dump_dir / "functions.json"
        strings_json = dump_dir / "strings.json"
        counts = load_dump_into_db(
            db,
            classes_json if classes_json.is_file() else None,
            functions_json if functions_json.is_file() else None,
            strings_json if strings_json.is_file() else None,
        )
        if entry_json.is_file():
            try:
                entry_data = json.loads(entry_json.read_text(encoding="utf-8"))
                db.set_meta("entrypoints", json.dumps(entry_data))
            except json.JSONDecodeError:
                pass
        if refs_json.is_file():
            counts["refs"] = db.import_refs_json(refs_json)
        result["dump"] = counts
    else:
        result["headless"] = {
            "skipped": True,
            "reason": "headless or scripts unavailable"
            if not hl
            else "missing binary or scripts",
            "headless_bin": str(hl) if hl else None,
            "scripts_dir": str(scripts),
            "have_import": have_import,
            "have_dump": have_dump,
            "have_entry": have_entry,
            "have_refs": have_refs,
        }

    result["stats"] = db.stats()
    db.close()
    return result
