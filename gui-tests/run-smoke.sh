#!/usr/bin/env bash
# Build GhidraVibe.app, register it, and run the agent-device accessibility smoke suite.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILT_APP="$REPO/macos/GhidraVibe/.build/GhidraVibe.app"
INSTALL_APP="${GHIDRA_VIBE_APP_INSTALL:-$HOME/Applications/GhidraVibe.app}"
APP_NAME="${APP_TARGET:-GhidraVibe}"
SESSION="${AD_SESSION:-ghidra-vibe-smoke}"
ARTIFACTS="${AD_ARTIFACTS:-$REPO/gui-tests/artifacts}"
HELPER_BIN="${AGENT_DEVICE_MACOS_HELPER_BIN:-$HOME/.agent-device/macos-helper/current/agent-device-macos-helper}"

mkdir -p "$ARTIFACTS" "$HOME/Applications"
chmod +x "$REPO/macos/GhidraVibe/scripts/package-app.sh"
"$REPO/macos/GhidraVibe/scripts/package-app.sh" "$BUILT_APP"

rm -rf "$INSTALL_APP"
cp -R "$BUILT_APP" "$INSTALL_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_APP"

if [[ ! -x "$HELPER_BIN" ]]; then
  echo "agent-device macOS helper missing at $HELPER_BIN" >&2
  echo "Build once: cp -R \"\$(dirname \"\$(readlink -f \"\$(which agent-device)\")\")/../lib/agent-device/macos-helper\" \"\$HOME/.agent-device/macos-helper-src\" && xcrun swift build -c release --package-path \"\$HOME/.agent-device/macos-helper-src\" && mkdir -p \"\$HOME/.agent-device/macos-helper/current\" && cp \"\$HOME/.agent-device/macos-helper-src/.build/release/agent-device-macos-helper\" \"\$HOME/.agent-device/macos-helper/current/\"" >&2
  exit 1
fi
export AGENT_DEVICE_MACOS_HELPER_BIN="$HELPER_BIN"

agent-device --version >/dev/null
# Ensure apps inventory can see the freshly registered bundle.
agent-device apps --platform macos --all >/dev/null || true

# Skip first-run agreement; smokeStartProject skips Welcome/Workspace for AX chrome.
defaults write dev.ghidravibe.app ghidra.vibe.userAgreementAccepted -bool true
defaults write dev.ghidravibe.app ghidra.vibe.welcomeHelpSeen -bool true
defaults write dev.ghidravibe.app ghidra.vibe.smokeStartProject -bool true

agent-device test "$REPO/gui-tests/smoke-a11y.ad" \
  --session "$SESSION" \
  --platform macos \
  --artifacts-dir "$ARTIFACTS" \
  -e "APP_TARGET=$APP_NAME" \
  --timeout 180000 \
  --reporter "junit:$ARTIFACTS/junit.xml"

echo "OK — artifacts in $ARTIFACTS"
