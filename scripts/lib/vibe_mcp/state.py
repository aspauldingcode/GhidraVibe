"""In-memory nav/undo stacks shared by MCP clients (UI + agents)."""

from __future__ import annotations

from dataclasses import dataclass, field
from threading import Lock
from typing import Any


@dataclass
class VibeSessionState:
    nav_stack: list[str] = field(default_factory=list)
    nav_index: int = -1
    undo_stack: list[dict[str, Any]] = field(default_factory=list)
    redo_stack: list[dict[str, Any]] = field(default_factory=list)
    selection: dict[str, Any] = field(default_factory=dict)
    lock: Lock = field(default_factory=Lock)

    def nav_push(self, address: str) -> dict[str, Any]:
        with self.lock:
            if self.nav_index >= 0 and self.nav_index < len(self.nav_stack) - 1:
                self.nav_stack = self.nav_stack[: self.nav_index + 1]
            if not self.nav_stack or self.nav_stack[-1] != address:
                self.nav_stack.append(address)
            self.nav_index = len(self.nav_stack) - 1
            self.selection["address"] = address
            return self.nav_snapshot()

    def nav_back(self) -> dict[str, Any]:
        with self.lock:
            if self.nav_index > 0:
                self.nav_index -= 1
                self.selection["address"] = self.nav_stack[self.nav_index]
            return self.nav_snapshot()

    def nav_forward(self) -> dict[str, Any]:
        with self.lock:
            if self.nav_index < len(self.nav_stack) - 1:
                self.nav_index += 1
                self.selection["address"] = self.nav_stack[self.nav_index]
            return self.nav_snapshot()

    def nav_snapshot(self) -> dict[str, Any]:
        addr = self.nav_stack[self.nav_index] if 0 <= self.nav_index < len(self.nav_stack) else None
        return {
            "ok": True,
            "address": addr,
            "index": self.nav_index,
            "stack": list(self.nav_stack),
            "can_back": self.nav_index > 0,
            "can_forward": self.nav_index < len(self.nav_stack) - 1,
        }

    def clear_selection(self) -> dict[str, Any]:
        with self.lock:
            self.selection = {}
            return {"ok": True, "selection": {}}

    def push_undo(self, op: dict[str, Any]) -> None:
        with self.lock:
            self.undo_stack.append(op)
            self.redo_stack.clear()

    def undo(self) -> dict[str, Any]:
        with self.lock:
            if not self.undo_stack:
                return {"ok": False, "error": "nothing to undo"}
            op = self.undo_stack.pop()
            self.redo_stack.append(op)
            return {"ok": True, "undone": op, "hint": "re-apply inverse via analysis MCP if needed"}

    def redo(self) -> dict[str, Any]:
        with self.lock:
            if not self.redo_stack:
                return {"ok": False, "error": "nothing to redo"}
            op = self.redo_stack.pop()
            self.undo_stack.append(op)
            return {"ok": True, "redone": op}


SESSION = VibeSessionState()
