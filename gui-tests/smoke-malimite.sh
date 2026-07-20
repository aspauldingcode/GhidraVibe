#!/usr/bin/env bash
# Malimite-parity smoke: libraries, harvest, db, translate prompt, apple wrapper.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
export PYTHONPATH="$REPO/scripts/lib"
APPLE="$REPO/scripts/ghidra-vibe-apple"
chmod +x "$APPLE"

TMP="$(mktemp -d -t malimite-smoke-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

APP="$TMP/Smoke.app"
mkdir -p "$APP"
cat >"$APP/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Smoke</string>
  <key>CFBundleIdentifier</key><string>dev.ghidravibe.smoke</string>
</dict></plist>
EOF
echo 'secret_token_value' >"$APP/Localizable.strings"
printf '\xfe\xed\xfa\xcfdeadbeef' >"$APP/Smoke"

n="$("$APPLE" libraries list | wc -l | tr -d ' ')"
[[ "$n" -ge 40 ]] || { echo "FAIL: expected >=40 libraries, got $n" >&2; exit 1; }

DB="$TMP/m.db"
"$APPLE" harvest --root "$APP" --db "$DB" | tee "$TMP/harvest.txt"
grep -q ResourceStrings "$TMP/harvest.txt" || true
"$APPLE" db stats --db "$DB" | tee "$TMP/stats.json"
grep -q ResourceStrings "$TMP/stats.json"

"$APPLE" info --app "$APP" | tee "$TMP/info.json"
grep -q CFBundleExecutable "$TMP/info.json"

echo 'void foo() { return; }' >"$TMP/fn.c"
"$APPLE" translate --action summarize --code-file "$TMP/fn.c" --language Swift | tee "$TMP/translate.txt"
grep -Eiq 'summar|function|prompt|void foo' "$TMP/translate.txt"

# Seed Classes/Functions manually
python3 - <<PY
from malimite.db import MalimiteDB
db = MalimiteDB("$DB")
db.insert_class("SmokeClass", ["foo", "bar"], "Smoke")
db.insert_function("foo", "SmokeClass", "void foo() {}", "Smoke")
db.insert_function_reference("foo", "SmokeClass", "bar", "SmokeClass", 0, "Smoke")
db.close()
print("seeded")
PY
"$APPLE" db classes --db "$DB" | grep -q SmokeClass
"$APPLE" db refs --db "$DB" foo | grep -q bar

echo "OK smoke-malimite"
