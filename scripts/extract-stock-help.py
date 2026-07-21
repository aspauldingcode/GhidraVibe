#!/usr/bin/env python3
"""Extract stock Ghidra JavaHelp into a native help bundle.

Reads $GHIDRA_INSTALL_DIR (or --install) product JARs, unpacks help/ HTML +
shared assets, merges TOC/map files, appends GhidraVibe addenda, and writes:

  <out>/
    toc.json map.json search.json tips.txt manifest.json
    articles/{topics,shared,vibe,...}

Package-time preferred (see macos/GhidraVibe/scripts/package-app.sh).
"""
from __future__ import annotations

import argparse
import html
import json
import os
import re
import shutil
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "native-ui" / "help"

SKIP_NAME_PARTS = (
    "_JavaHelpSearch/",
    "screenshot/",
)

SKIP_SUFFIXES = (".class", ".hs")

VIBE_PAGES: list[dict[str, str]] = [
    {
        "id": "vibe_welcome",
        "title": "GhidraVibe Overview",
        "file": "vibe/welcome.html",
        "body": """
<p>GhidraVibe is Ghidra with a native macOS/Linux GUI. The analysis engine runs
in-process; the Swing Front End is not shipped.</p>
<ul>
  <li>Project Window + CodeBrowser layout mirrored from stock tools</li>
  <li>Integrated MCP, Agent chat, JSpace RAG, and Rules</li>
  <li>On-device dyld shared cache import with Apple symbols (macOS)</li>
</ul>
<p>Accept the User Agreement on first launch, then open or create a project.</p>
""",
    },
    {
        "id": "vibe_mcp",
        "title": "Analysis MCP",
        "file": "vibe/mcp.html",
        "body": """
<p>The program engine API (default <code>http://127.0.0.1:8089</code>) runs
in-process with the GUI. Cursor and other agents can use the same endpoints or
the headless CLI. GuiControl (<code>:8091</code>) drives the native shell for
automation.</p>
""",
    },
    {
        "id": "vibe_dsc",
        "title": "Shared Cache (dyld)",
        "file": "vibe/dsc.html",
        "body": """
<p><strong>File → Open Shared Cache…</strong> opens the DSC Index. Filter
(e.g. AppKit), then Load selected or double-click to import one module with
Apple local symbols. Auto-analyze is optional afterward.</p>
""",
    },
    {
        "id": "vibe_agent",
        "title": "Agent &amp; RAG",
        "file": "vibe/agent.html",
        "body": """
<p>The Agent panel runs JSpace RAG discovery then optional MCP
decompile/list. Index JSpace after a program is loaded. Rules edits the local
playbook used by discovery. Tool permissions and completion sounds live in
Agent Setup.</p>
""",
    },
    {
        "id": "vibe_support",
        "title": "GhidraVibe Support",
        "file": "vibe/support.html",
        "body": """
<p>Docs: <code>docs/GUI.md</code>, <code>docs/DYLD.md</code>,
<code>docs/GUI_TESTING.md</code>.</p>
<p>Accessibility: <code>native-ui/a11y/catalog.json</code> — automate with
agent-device (<code>id=</code> selectors).</p>
<p><strong>GhidraClass</strong> training materials are not bundled in this Help
pass (large tree; optional follow-up). Stock JavaHelp articles and Tips are
complete.</p>
""",
    },
]


def resolve_install(explicit: str | None) -> Path:
    if explicit:
        p = Path(explicit)
        if (p / "Ghidra").is_dir():
            return p
        raise SystemExit(f"GHIDRA_INSTALL_DIR invalid: {p}")
    env = os.environ.get("GHIDRA_INSTALL_DIR", "").strip()
    if env and (Path(env) / "Ghidra").is_dir():
        return Path(env)
    store = Path("/nix/store")
    if store.is_dir():
        cands = sorted(
            store.glob("*-ghidra-vibe-*+native-*/lib/ghidra"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        for c in cands:
            if (c / "Ghidra").is_dir():
                return c
        cands = sorted(
            store.glob("*-ghidra-vibe-*/lib/ghidra"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        for c in cands:
            if (c / "Ghidra").is_dir():
                return c
    raise SystemExit(
        "Set GHIDRA_INSTALL_DIR to a Ghidra install (…/lib/ghidra) or build ghidra-vibe in nix."
    )


def should_extract(name: str) -> bool:
    if not name.startswith("help/"):
        return False
    if name.endswith("/"):
        return False
    for part in SKIP_NAME_PARTS:
        if part in name:
            return False
    if name.endswith(SKIP_SUFFIXES):
        return False
    # Keep TOC/map XML for parsing but do not copy into articles as content.
    if name.endswith(("_TOC.xml", "_map.xml", "TOC_Source.xml")):
        return False
    return True


def extract_jars(install: Path, articles: Path) -> dict[str, int]:
    stats = {"jars": 0, "files": 0, "html": 0}
    articles.mkdir(parents=True, exist_ok=True)
    for jar in sorted(install.rglob("*.jar")):
        if "javahelp" in jar.name.lower():
            continue
        try:
            zf = zipfile.ZipFile(jar)
        except zipfile.BadZipFile:
            continue
        names = [n for n in zf.namelist() if n.startswith("help/")]
        if not names:
            continue
        stats["jars"] += 1
        for name in names:
            if not should_extract(name):
                continue
            # Strip leading "help/" → articles/
            rel = name[len("help/") :]
            dest = articles / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            data = zf.read(name)
            if name.endswith((".htm", ".html")):
                text = data.decode("latin-1", errors="replace")
                text = rewrite_help_links(text, rel)
                dest.write_text(text, encoding="utf-8")
                stats["html"] += 1
            else:
                dest.write_bytes(data)
            stats["files"] += 1
    return stats


def rewrite_help_links(html_text: str, article_rel: str) -> str:
    """Rewrite help/… URLs to paths relative to the article file."""
    depth = len(Path(article_rel).parts) - 1  # dirs under articles/
    prefix = "../" * depth if depth > 0 else ""

    def repl(m: re.Match[str]) -> str:
        attr, quote, url = m.group(1), m.group(2), m.group(3)
        if url.startswith("help/"):
            url = prefix + url[len("help/") :]
        return f"{attr}={quote}{url}{quote}"

    return re.sub(
        r'(href|src)=(["\'])(help/[^"\']+)\2',
        repl,
        html_text,
        flags=re.IGNORECASE,
    )


def parse_map(xml_bytes: bytes) -> dict[str, str]:
    # Strip DOCTYPE — ElementTree chokes on JavaHelp DTD refs without network.
    text = xml_bytes.decode("latin-1", errors="replace")
    text = re.sub(r"<!DOCTYPE[^>]*>", "", text, count=1, flags=re.IGNORECASE)
    root = ET.fromstring(text)
    out: dict[str, str] = {}
    for el in root.iter():
        tag = el.tag.split("}")[-1]
        if tag.lower() != "mapid":
            continue
        target = el.attrib.get("target") or el.attrib.get("TARGET")
        url = el.attrib.get("url") or el.attrib.get("URL")
        if target and url:
            out[target] = url
    return out


def toc_item_to_dict(el: ET.Element) -> dict:
    display = el.attrib.get("display") or el.attrib.get("toc_id") or "Untitled"
    target = el.attrib.get("target") or None
    toc_id = el.attrib.get("toc_id") or display
    sort_key = el.attrib.get("text") or ""
    children = [
        toc_item_to_dict(c)
        for c in el
        if c.tag.split("}")[-1].lower() == "tocitem"
    ]
    node: dict = {
        "id": toc_id,
        "title": display,
        "sort": sort_key,
        "children": children,
    }
    if target:
        node["target"] = target
    return node


def parse_toc(xml_bytes: bytes) -> dict | None:
    text = xml_bytes.decode("latin-1", errors="replace")
    text = re.sub(r"<!DOCTYPE[^>]*>", "", text, count=1, flags=re.IGNORECASE)
    root = ET.fromstring(text)
    for el in root:
        if el.tag.split("}")[-1].lower() == "tocitem":
            return toc_item_to_dict(el)
    return None


def merge_toc(dst: dict, src: dict) -> None:
    """UniteAppend / SortMerge by toc_id (Ghidra CustomTOCView semantics, simplified)."""
    if not dst.get("target") and src.get("target"):
        dst["target"] = src["target"]
    if src.get("title") and (
        not dst.get("title") or dst.get("title") == dst.get("id")
    ):
        dst["title"] = src["title"]
    by_id = {c["id"]: c for c in dst.get("children") or []}
    for child in src.get("children") or []:
        cid = child["id"]
        if cid in by_id:
            merge_toc(by_id[cid], child)
        else:
            dst.setdefault("children", []).append(child)
            by_id[cid] = child
    children = dst.get("children") or []
    children.sort(key=lambda c: (c.get("sort") or "", c.get("title") or ""))
    dst["children"] = children


def collect_tocs_and_maps(install: Path) -> tuple[dict | None, dict[str, str]]:
    merged_root: dict | None = None
    maps: dict[str, str] = {}
    for jar in sorted(install.rglob("*.jar")):
        if "javahelp" in jar.name.lower():
            continue
        try:
            zf = zipfile.ZipFile(jar)
        except zipfile.BadZipFile:
            continue
        for name in zf.namelist():
            if not name.startswith("help/"):
                continue
            if name.endswith("_map.xml"):
                maps.update(parse_map(zf.read(name)))
            elif name.endswith("_TOC.xml") and "TOC_Source" not in name:
                node = parse_toc(zf.read(name))
                if not node:
                    continue
                if merged_root is None:
                    merged_root = node
                else:
                    merge_toc(merged_root, node)
    return merged_root, maps


def strip_html(text: str) -> str:
    text = re.sub(r"(?is)<script[^>]*>.*?</script>", " ", text)
    text = re.sub(r"(?is)<style[^>]*>.*?</style>", " ", text)
    text = re.sub(r"(?s)<[^>]+>", " ", text)
    text = html.unescape(text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def build_search_index(articles: Path, maps: dict[str, str]) -> list[dict]:
    # Prefer unique article paths; attach primary map target when known.
    path_to_target: dict[str, str] = {}
    for target, url in maps.items():
        path = url.split("#", 1)[0]
        path_to_target.setdefault(path, target)
    entries: list[dict] = []
    for path in sorted(articles.rglob("*")):
        if path.suffix.lower() not in {".htm", ".html"}:
            continue
        rel = path.relative_to(articles).as_posix()
        raw = path.read_text(encoding="utf-8", errors="replace")
        title_m = re.search(r"(?is)<title[^>]*>(.*?)</title>", raw)
        title = strip_html(title_m.group(1)) if title_m else path.stem
        body = strip_html(raw)[:4000]
        entries.append(
            {
                "id": path_to_target.get(rel, rel),
                "title": title,
                "path": rel,
                "text": body,
            }
        )
    return entries


def write_vibe_pages(articles: Path) -> list[dict]:
    vibe_dir = articles / "vibe"
    vibe_dir.mkdir(parents=True, exist_ok=True)
    css = "../../shared/DefaultStyle.css"
    toc_children = []
    for page in VIBE_PAGES:
        dest = articles / page["file"]
        dest.parent.mkdir(parents=True, exist_ok=True)
        doc = f"""<!DOCTYPE html>
<html><head>
<meta charset="utf-8"/>
<title>{page["title"]}</title>
<link rel="stylesheet" type="text/css" href="{css}"/>
<style>
  body {{ font-family: -apple-system, system-ui, sans-serif; margin: 24px; max-width: 52rem; }}
  code {{ font-size: 0.95em; }}
</style>
</head><body>
<h1>{page["title"]}</h1>
{page["body"]}
</body></html>
"""
        dest.write_text(doc, encoding="utf-8")
        target = f"GhidraVibe_{page['id']}"
        toc_children.append(
            {
                "id": page["id"],
                "title": html.unescape(page["title"].replace("&amp;", "&")),
                "sort": page["id"],
                "target": target,
                "children": [],
            }
        )
    return toc_children


def extract_tips(install: Path, out: Path) -> int:
    for jar in install.rglob("Base.jar"):
        try:
            zf = zipfile.ZipFile(jar)
        except zipfile.BadZipFile:
            continue
        name = "ghidra/app/plugin/core/totd/tips.txt"
        if name not in zf.namelist():
            continue
        raw = zf.read(name).decode("utf-8", errors="replace")
        tips = [ln.strip() for ln in raw.splitlines() if ln.strip()]
        out.write_text("\n".join(tips) + "\n", encoding="utf-8")
        return len(tips)
    raise SystemExit("tips.txt not found in Base.jar")


def copy_loose_docs(install: Path, articles: Path) -> list[str]:
    """Best-effort WhatsNew / GettingStarted markdown → simple HTML."""
    copied: list[str] = []
    docs = install / "docs"
    for name, title in (("WhatsNew.md", "What's New"), ("GettingStarted.md", "Getting Started")):
        src = docs / name
        if not src.is_file():
            alt = install / name
            src = alt if alt.is_file() else src
        if not src.is_file():
            continue
        rel = f"vibe/{src.stem.lower()}.html"
        text = html.escape(src.read_text(encoding="utf-8", errors="replace"))
        body = "<pre style='white-space:pre-wrap;font-family:ui-monospace,monospace'>" + text + "</pre>"
        dest = articles / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(
            f"""<!DOCTYPE html><html><head><meta charset="utf-8"/><title>{title}</title>
<link rel="stylesheet" href="../shared/DefaultStyle.css"/></head>
<body><h1>{title}</h1>{body}</body></html>""",
            encoding="utf-8",
        )
        copied.append(rel)
    return copied


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--install", help="GHIDRA_INSTALL_DIR (…/lib/ghidra)")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="Output help bundle")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    install = resolve_install(args.install)
    out: Path = args.out
    if out.exists():
        shutil.rmtree(out)
    articles = out / "articles"
    articles.mkdir(parents=True)

    stats = extract_jars(install, articles)
    toc_root, maps = collect_tocs_and_maps(install)
    if toc_root is None:
        raise SystemExit("No *_TOC.xml found under Ghidra JARs")

    vibe_children = write_vibe_pages(articles)
    for child in vibe_children:
        target = child["target"]
        # map target → vibe path
        page = next(p for p in VIBE_PAGES if f"GhidraVibe_{p['id']}" == target)
        maps[target] = page["file"]

    toc_root.setdefault("children", []).append(
        {
            "id": "GhidraVibe",
            "title": "GhidraVibe",
            "sort": "zz_vibe",
            "children": vibe_children,
        }
    )

    loose = copy_loose_docs(install, articles)
    tip_count = extract_tips(install, out / "tips.txt")
    search = build_search_index(articles, maps)

    # Drop internal sort keys from TOC JSON for a cleaner contract.
    def clean(node: dict) -> dict:
        out_n: dict = {
            "id": node["id"],
            "title": node["title"],
            "children": [clean(c) for c in node.get("children") or []],
        }
        if node.get("target"):
            out_n["target"] = node["target"]
        return out_n

    toc_json = clean(toc_root)
    (out / "toc.json").write_text(
        json.dumps(toc_json, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    (out / "map.json").write_text(
        json.dumps(maps, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (out / "search.json").write_text(
        json.dumps(search, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    def count_toc(n: dict) -> int:
        return 1 + sum(count_toc(c) for c in n.get("children") or [])

    manifest = {
        "version": 1,
        "install": str(install),
        "jars": stats["jars"],
        "files": stats["files"],
        "articles": stats["html"],
        "mapIds": len(maps),
        "tocNodes": count_toc(toc_json),
        "searchEntries": len(search),
        "tips": tip_count,
        "looseDocs": loose,
        "defaultTarget": "Misc_Help_Contents",
        "defaultPath": "topics/Misc/Welcome_to_Help.htm",
    }
    # Prefer Welcome map id if present
    for key in ("Misc_Help_Contents", "Misc_Welcome_to_Help", "help_contents"):
        if key in maps:
            manifest["defaultTarget"] = key
            manifest["defaultPath"] = maps[key].split("#", 1)[0]
            break
    else:
        # Fall back to first path that looks like Welcome
        for e in search:
            if "welcome" in e["title"].lower():
                manifest["defaultPath"] = e["path"]
                manifest["defaultTarget"] = e["id"]
                break

    (out / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )

    if not args.quiet:
        print(
            f"OK help bundle → {out}\n"
            f"  jars={stats['jars']} files={stats['files']} html={stats['html']}\n"
            f"  mapIds={len(maps)} tocNodes={manifest['tocNodes']} "
            f"tips={tip_count} search={len(search)}"
        )
    if stats["html"] < 200:
        print(f"WARN: expected ≥200 HTML articles, got {stats['html']}", file=sys.stderr)
        return 1
    if tip_count < 70:
        print(f"WARN: expected ≥70 tips, got {tip_count}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
