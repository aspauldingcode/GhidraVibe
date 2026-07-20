#!/usr/bin/env bash
# Compat: CodeBrowser loop now delegates to full stock 1:1 parity gates.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/scripts/stock-parity-loop.sh"