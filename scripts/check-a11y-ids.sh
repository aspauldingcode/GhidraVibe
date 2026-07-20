#!/usr/bin/env bash
# Ensure accessibility IDs in Swift sources and smoke scripts stay aligned.
set -euo pipefail
if [[ -n "${CHECK_A11Y_ROOT:-}" ]]; then
  ROOT="$CHECK_A11Y_ROOT"
else
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi
SWIFT_DIR="$ROOT/macos/GhidraVibe/Sources"
LINUX_DIR="$ROOT/linux/GhidraVibe/src"
JSON_CATALOG="$ROOT/native-ui/a11y/catalog.json"
CATALOG_DIR="${CHECK_A11Y_OUTDIR:-$ROOT/gui-tests}"
mkdir -p "$CATALOG_DIR"
CATALOG="$CATALOG_DIR/a11y-id-catalog.txt"

python3 <<PY
import re
from pathlib import Path
root = Path(r"""$ROOT""")
pat = re.compile(r"ghidra\.vibe\.[a-z0-9_.]+")
ids = set()
for base, suffix in [
    (root / "macos/GhidraVibe/Sources", ".swift"),
    (root / "linux/GhidraVibe/src", ".c"),
    (root / "linux/GhidraVibe/src", ".h"),
]:
    if not base.is_dir():
        continue
    for f in base.rglob(f"*{suffix}"):
        if f.is_file():
            ids.update(pat.findall(f.read_text(errors="ignore")))
cat = root / "native-ui/a11y/catalog.json"
if cat.is_file():
    ids.update(pat.findall(cat.read_text(errors="ignore")))
out = Path(r"""$CATALOG""")
out.write_text("\n".join(sorted(ids)) + ("\n" if ids else ""))
tests = set()
gt = root / "gui-tests"
if gt.is_dir():
    for f in list(gt.rglob("*.ad")) + list(gt.rglob("*.sh")):
        if not f.is_file():
            continue
        tests.update(pat.findall(f.read_text(errors="ignore")))
Path(str(out) + ".tests").write_text("\n".join(sorted(tests)) + ("\n" if tests else ""))
print(len(ids))
PY

missing=0
while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  [[ "$id" == *optOut* || "$id" == *welcomeDismissed* ]] && continue
  if ! grep -qxF "$id" "$CATALOG"; then
    if ! grep -q "^${id}" "$CATALOG" && ! grep -q "^$(echo "$id" | cut -d. -f1-3)" "$CATALOG"; then
      echo "FAIL: test references unknown a11y id: $id" >&2
      missing=1
    fi
  fi
done <"$CATALOG.tests"

count="$(wc -l <"$CATALOG" | tr -d ' ')"
if [[ "$count" -lt 20 ]]; then
  echo "FAIL: a11y catalog too small ($count)" >&2
  exit 1
fi

if [[ "$missing" -ne 0 ]]; then
  echo "Catalog sample:" >&2
  head -20 "$CATALOG" >&2
  exit 1
fi

echo "OK: $count a11y ids in catalog; tests aligned"
rm -f "$CATALOG.tests"
