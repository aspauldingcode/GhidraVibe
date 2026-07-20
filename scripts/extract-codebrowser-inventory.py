#!/usr/bin/env python3
"""Compat wrapper — regenerates all stock inventories via extract-stock-inventory.py."""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "extract_stock_inventory", ROOT / "scripts/extract-stock-inventory.py"
)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)
raise SystemExit(mod.main())
