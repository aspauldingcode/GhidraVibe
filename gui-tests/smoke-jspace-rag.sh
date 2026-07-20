#!/usr/bin/env bash
# Offline JSpace RAG smoke (Rust binary; no MCP / no network for playbook path).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JSPACE="${GHIDRA_VIBE_JSPACE_BIN:-${GHIDRA_VIBE_JSPACE:-$ROOT/rust/target/release/ghidra-vibe-jspace}}"
DB="${GHIDRA_VIBE_JSPACE_DB:-$ROOT/.ghidra-vibe-jspace/smoke.sqlite}"
OUTDIR="${TMPDIR:-/tmp}"
rm -f "$DB"
export GHIDRA_VIBE_JSPACE_DB="$DB"

if [[ ! -x "$JSPACE" ]]; then
  if [[ -x "$ROOT/scripts/ghidra-vibe-jspace" ]]; then
    JSPACE="$ROOT/scripts/ghidra-vibe-jspace"
  else
    echo "missing ghidra-vibe-jspace binary at $JSPACE" >&2
    exit 1
  fi
fi

"$JSPACE" init | tee "$OUTDIR/jspace-init.json"
rg -q 'playbook' "$OUTDIR/jspace-init.json"

"$JSPACE" search "dyld shared cache AppKit" --top 5 | tee "$OUTDIR/jspace-search.json"
rg -qi 'dyld|playbook|AppKit|triage' "$OUTDIR/jspace-search.json"

"$JSPACE" discover "how do I open SkyLight from the dyld cache?" --top 5 | tee "$OUTDIR/jspace-discover.txt"
rg -qi 'RE discovery|JSpace|Suggested next MCP' "$OUTDIR/jspace-discover.txt"

"$JSPACE" discover "SwiftUI View protocol metadata" --top 5 | tee "$OUTDIR/jspace-swift.txt"
rg -qi 'swift|SwiftUI|demangle|metadata' "$OUTDIR/jspace-swift.txt"

"$JSPACE" stats | tee "$OUTDIR/jspace-stats.json"
rg -q 'chunks' "$OUTDIR/jspace-stats.json"

# Docs live in the repo; skip when this script is a lone nix store file.
if [[ -d "$ROOT/docs" ]]; then
  test -f "$ROOT/docs/RAG.md"
  test -f "$ROOT/docs/SWIFT.md"
fi
echo "OK smoke-jspace-rag"
