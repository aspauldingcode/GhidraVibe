#!/usr/bin/env bash
# Build GhidraVibe.app then wrap it in a compressed UDZO .dmg for distribution.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
APP="${1:-$ROOT/.build/GhidraVibe.app}"
DIST="${DMG_OUT_DIR:-$REPO/dist}"
VERSION="${GHIDRA_VIBE_VERSION:-}"
SHA="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"

if [[ -z "$VERSION" ]]; then
  if [[ -n "${GITHUB_REF_NAME:-}" && "${GITHUB_REF_NAME}" == v* ]]; then
    VERSION="${GITHUB_REF_NAME}"
  else
    VERSION="0.1.0-${SHA}"
  fi
fi

chmod +x "$ROOT/scripts/package-app.sh"
"$ROOT/scripts/package-app.sh" "$APP"

mkdir -p "$DIST"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/ghidravibe-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

cp -R "$APP" "$STAGE/GhidraVibe.app"
# Convenience: Applications symlink for drag-install.
ln -sf /Applications "$STAGE/Applications"

DMG_NAME="GhidraVibe-${VERSION}.dmg"
DMG_PATH="$DIST/$DMG_NAME"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "GhidraVibe" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# Stable name for CI upload / beta channel.
cp -f "$DMG_PATH" "$DIST/GhidraVibe-latest.dmg"

cat >"$DIST/latest.json" <<EOF
{
  "name": "GhidraVibe",
  "version": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$VERSION"),
  "sha": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$SHA"),
  "dmg": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$DMG_NAME"),
  "dmg_latest": "GhidraVibe-latest.dmg",
  "app": "GhidraVibe.app",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "$DMG_PATH"
ls -lh "$DMG_PATH" "$DIST/GhidraVibe-latest.dmg" "$DIST/latest.json"
