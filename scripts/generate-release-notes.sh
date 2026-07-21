#!/usr/bin/env bash
# Emit markdown release notes from git history (stdout).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CHANNEL="${1:-auto}" # auto | beta | tag
REF_NAME="${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD)}"
SHA="$(git rev-parse HEAD)"
SHORT="$(git rev-parse --short HEAD)"

if [[ "$CHANNEL" == "auto" ]]; then
  if [[ "${GITHUB_REF:-}" == refs/tags/* || "$REF_NAME" == v* ]]; then
    CHANNEL=tag
  else
    CHANNEL=beta
  fi
fi

prev=""
if [[ "$CHANNEL" == "tag" ]]; then
  prev="$(git describe --tags --abbrev=0 "${REF_NAME}^" 2>/dev/null || true)"
else
  prev="$(git describe --tags --abbrev=0 2>/dev/null || true)"
fi

range="HEAD"
if [[ -n "$prev" ]]; then
  range="${prev}..HEAD"
fi

if [[ "$CHANNEL" == "tag" ]]; then
  echo "## GhidraVibe ${REF_NAME}"
else
  echo "## GhidraVibe Beta"
  echo
  echo "Rolling prerelease from \`master\` (\`${SHORT}\`)."
fi
echo
echo "- **Commit:** \`${SHA}\`"
echo "- **Range:** \`${range}\`"
echo
echo "### Changes"
echo
# Prefer conventional-commit subjects; fall back to oneline.
if git log --format='%s' "$range" 2>/dev/null | grep -q .; then
  git log --format='- %s (%h)' "$range" | head -80
else
  echo "- Initial packaging commit"
fi
echo
echo "### Install"
echo
echo "1. Download the \`.dmg\` asset from this release."
echo "2. Open it and drag **GhidraVibe** into Applications."
echo "3. Or develop from source: \`nix run\` (see README)."
echo
echo "### MCP (optional)"
echo
echo "With the app running, point Cursor at the bridges under the nix result"
echo "\`share/ghidra-mcp/\` (see docs/CURSOR.md in the repo)."
echo "Engine default: \`http://127.0.0.1:8089\` · GuiControl: \`http://127.0.0.1:8091\`."
