#!/usr/bin/env bash
# Smoke: ghidra-vibe-apple unpack/find-bin/resources against a tiny synthetic .app
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
APPLE="${GHIDRA_VIBE_APPLE:-$REPO/scripts/ghidra-vibe-apple}"
chmod +x "$APPLE"

TMP="$(mktemp -d -t ghidra-vibe-apple-smoke-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

APP="$TMP/Smoke.app"
mkdir -p "$APP"
# Minimal Info.plist + fake Mach-O placeholder (find-bin falls back if not Mach-O)
cat >"$APP/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Smoke</string>
  <key>CFBundleIdentifier</key>
  <string>dev.ghidravibe.smoke</string>
</dict>
</plist>
EOF
printf 'MZ' >"$APP/Smoke"  # not Mach-O; resources still work
echo 'hello' >"$APP/Localizable.strings"
/usr/bin/plutil -convert binary1 -o "$APP/Info.bin.plist" "$APP/Info.plist" 2>/dev/null || cp "$APP/Info.plist" "$APP/Info.bin.plist"

"$APPLE" resources --app "$APP" | tee "$TMP/resources.txt"
grep -q 'Info.plist' "$TMP/resources.txt"
grep -q 'Localizable.strings' "$TMP/resources.txt"

"$APPLE" decode-plist --file "$APP/Info.plist" | tee "$TMP/plist.txt"
grep -q 'CFBundleExecutable' "$TMP/plist.txt"

# IPA round-trip
PAYLOAD="$TMP/ipa_root/Payload"
mkdir -p "$PAYLOAD"
cp -R "$APP" "$PAYLOAD/"
(cd "$TMP/ipa_root" && zip -qr "$TMP/Smoke.ipa" Payload)
UNPACKED="$("$APPLE" unpack --ipa "$TMP/Smoke.ipa" --out "$TMP/unpacked")"
[[ -d "$UNPACKED" ]]
[[ -f "$UNPACKED/Info.plist" ]]

echo "OK smoke-apple-cli"
