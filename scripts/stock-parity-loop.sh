#!/usr/bin/env bash
# Full stock 1:1 parity gates (universe → chrome → inventory → a11y → impl → gaps).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0
run() {
  echo "==> $*"
  if ! "$@"; then
    echo "FAIL: $*" >&2
    fail=1
  fi
}
run "$ROOT/scripts/check-stock-universe.sh"
run python3 "$ROOT/scripts/extract-stock-inventory.py"
run python3 "$ROOT/scripts/sync-tracked-gaps.py"
run python3 "$ROOT/scripts/sync-stock-catalog.py"
run python3 "$ROOT/scripts/generate-stock-parity-ids.py"
run "$ROOT/scripts/check-codebrowser-inventory.sh"
run "$ROOT/scripts/check-a11y-ids.sh"
run "$ROOT/scripts/check-codebrowser-impl.sh"
run "$ROOT/scripts/check-liquid-glass.sh"
run "$ROOT/scripts/check-stock-tracked-gaps.sh"
run "$ROOT/scripts/check-capability-matrix.sh"
if [[ "$fail" -ne 0 ]]; then
  echo "Stock parity loop: FAIL — fix list above and re-run" >&2
  exit 1
fi
echo "Stock parity loop: OK (static gates). See docs/STOCK_PARITY.md"
