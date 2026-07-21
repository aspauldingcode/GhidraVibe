#!/usr/bin/env bash
# Content hash of paths that affect packaged release artifacts.
# Used by CI to skip beta rebuilds when only docs/unrelated files changed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TARGET="${1:-macos}"

case "$TARGET" in
  macos)
    PATHS=(
      flake.nix
      flake.lock
      macos/GhidraVibe
      native-ui
      nix/macos
      nix/ghidra
      nix/extensions
      nix/share
      nix/agent
      scripts/extract-stock-help.py
      scripts/ghidra-vibe-mcp-headless
      scripts/lib/detect-maxmem.sh
      macos/GhidraVibe/scripts/package-app.sh
      macos/GhidraVibe/scripts/package-dmg.sh
    )
    ;;
  linux)
    PATHS=(
      flake.nix
      flake.lock
      linux/GhidraVibe
      native-ui
      nix/ghidra
      nix/extensions
      nix/share
      nix/agent
      scripts/ghidra-vibe-mcp-headless
      scripts/lib/detect-maxmem.sh
    )
    ;;
  *)
    echo "usage: $0 [macos|linux]" >&2
    exit 2
    ;;
esac

EXISTING=()
for p in "${PATHS[@]}"; do
  [[ -e "$p" ]] || continue
  EXISTING+=("$p")
done
if [[ ${#EXISTING[@]} -eq 0 ]]; then
  echo "no release paths found for $TARGET" >&2
  exit 1
fi

# Newline paths (portable; Apple Git lacks hash-object -z).
FILES="$(git ls-files -- "${EXISTING[@]}" | LC_ALL=C sort)"
if [[ -z "$FILES" ]]; then
  echo "no tracked release files for $TARGET" >&2
  exit 1
fi

printf '%s\n' "$FILES" \
  | git hash-object --stdin-paths \
  | LC_ALL=C sort \
  | git hash-object --stdin
