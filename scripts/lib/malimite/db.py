"""Malimite-parity SQLite project database for GhidraVibe."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Union

PathLike = Union[str, Path]

SCHEMA_STATEMENTS: Sequence[str] = (
    """
    CREATE TABLE IF NOT EXISTS Classes (
        ClassName TEXT,
        Functions TEXT,
        ExecutableName TEXT,
        PRIMARY KEY (ClassName, ExecutableName)
    );
    """,
    """
    CREATE TABLE IF NOT EXISTS Functions (
        FunctionName TEXT,
        ParentClass TEXT,
        DecompilationCode TEXT,
        ExecutableName TEXT,
        PRIMARY KEY (FunctionName, ParentClass, ExecutableName)
    );
    """,
    """
    CREATE TABLE IF NOT EXISTS MachoStrings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        address TEXT,
        value TEXT,
        segment TEXT,
        label TEXT,
        ExecutableName TEXT
    );
    """,
    """
    CREATE TABLE IF NOT EXISTS ResourceStrings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        resourceId TEXT,
        value TEXT,
        type TEXT
    );
    """,
    """
    CREATE TABLE IF NOT EXISTS FunctionReferences (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sourceFunction TEXT,
        sourceClass TEXT,
        targetFunction TEXT,
        targetClass TEXT,
        lineNumber INTEGER,
        ExecutableName TEXT
    );
    """,
    """
    CREATE TABLE IF NOT EXISTS LocalVariableReferences (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        variableName TEXT,
        containingFunction TEXT,
        containingClass TEXT,
        lineNumber INTEGER,
        ExecutableName TEXT
    );
    """,
    """
    CREATE TABLE IF NOT EXISTS TypeInformation (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        variableName TEXT,
        variableType TEXT,
        functionName TEXT,
        className TEXT,
        lineNumber INTEGER,
        ExecutableName TEXT
    );
    """,
    """
    CREATE TABLE IF NOT EXISTS Meta (
        key TEXT PRIMARY KEY,
        value TEXT
    );
    """,
)

ENTRYPOINT_NAMES = frozenset(
    {
        "main",
        "_main",
        "applicationDidFinishLaunching",
    }
)


class MalimiteDB:
    """SQLite store matching Malimite ``SQLiteDBHandler`` tables (+ Meta)."""

    def __init__(self, path: PathLike) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(str(self.path))
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA journal_mode=WAL;")
        self._initialize()

    def _initialize(self) -> None:
        cur = self.conn.cursor()
        for stmt in SCHEMA_STATEMENTS:
            cur.execute(stmt)
        self.conn.commit()

    def close(self) -> None:
        self.conn.close()

    def __enter__(self) -> "MalimiteDB":
        return self

    def __exit__(self, *exc: Any) -> None:
        self.close()

    # --- inserts -----------------------------------------------------------------

    def insert_class(
        self,
        class_name: str,
        functions: Union[str, Sequence[str]],
        executable_name: str = "",
    ) -> None:
        if isinstance(functions, (list, tuple)):
            functions_json = json.dumps(list(functions))
        else:
            functions_json = str(functions)
        self.conn.execute(
            "INSERT OR REPLACE INTO Classes(ClassName, Functions, ExecutableName) VALUES(?,?,?)",
            (class_name, functions_json, executable_name),
        )
        self.conn.commit()

    def insert_function(
        self,
        function_name: str,
        parent_class: str,
        decompilation_code: str = "",
        executable_name: str = "",
    ) -> None:
        self.conn.execute(
            """
            INSERT INTO Functions(FunctionName, ParentClass, DecompilationCode, ExecutableName)
            VALUES(?,?,?,?)
            ON CONFLICT(FunctionName, ParentClass, ExecutableName)
            DO UPDATE SET DecompilationCode = excluded.DecompilationCode
            """,
            (function_name, parent_class, decompilation_code, executable_name),
        )
        self.conn.commit()

    def insert_macho_string(
        self,
        address: str,
        value: str,
        segment: str = "",
        label: str = "",
        executable_name: str = "",
    ) -> None:
        self.conn.execute(
            "INSERT INTO MachoStrings(address, value, segment, label, ExecutableName) VALUES(?,?,?,?,?)",
            (address, value, segment, label, executable_name),
        )
        self.conn.commit()

    def insert_resource_string(
        self,
        resource_id: str,
        value: str,
        type_: str = "unknown",
    ) -> None:
        self.conn.execute(
            "INSERT INTO ResourceStrings(resourceId, value, type) VALUES(?,?,?)",
            (resource_id, value, type_),
        )
        self.conn.commit()

    def insert_function_reference(
        self,
        source_function: str,
        source_class: str,
        target_function: str,
        target_class: str,
        line_number: int = 0,
        executable_name: str = "",
    ) -> None:
        self.conn.execute(
            """
            INSERT INTO FunctionReferences(
                sourceFunction, sourceClass, targetFunction, targetClass, lineNumber, ExecutableName
            )
            SELECT ?, ?, ?, ?, ?, ?
            WHERE NOT EXISTS (
                SELECT 1 FROM FunctionReferences
                WHERE sourceFunction = ? AND sourceClass = ?
                  AND targetFunction = ? AND targetClass = ?
                  AND lineNumber = ? AND ExecutableName = ?
            )
            """,
            (
                source_function,
                source_class,
                target_function,
                target_class,
                line_number,
                executable_name,
                source_function,
                source_class,
                target_function,
                target_class,
                line_number,
                executable_name,
            ),
        )
        self.conn.commit()

    def set_meta(self, key: str, value: str) -> None:
        self.conn.execute(
            "INSERT OR REPLACE INTO Meta(key, value) VALUES(?, ?)",
            (key, value),
        )
        self.conn.commit()

    def get_meta(self, key: str) -> Optional[str]:
        row = self.conn.execute(
            "SELECT value FROM Meta WHERE key = ?", (key,)
        ).fetchone()
        return None if row is None else row["value"]

    # --- queries -----------------------------------------------------------------

    def get_all_classes_and_functions(self) -> Dict[str, List[str]]:
        out: Dict[str, List[str]] = {}
        for row in self.conn.execute(
            "SELECT ClassName, Functions FROM Classes"
        ):
            try:
                fns = json.loads(row["Functions"] or "[]")
                if not isinstance(fns, list):
                    fns = []
            except json.JSONDecodeError:
                fns = []
            out[row["ClassName"]] = [str(x) for x in fns]
        return out

    def get_function_code(
        self,
        name: str,
        class_: str,
        executable_name: Optional[str] = None,
    ) -> Optional[str]:
        if executable_name is not None:
            row = self.conn.execute(
                """
                SELECT DecompilationCode FROM Functions
                WHERE FunctionName = ? AND ParentClass = ? AND ExecutableName = ?
                """,
                (name, class_, executable_name),
            ).fetchone()
        else:
            row = self.conn.execute(
                """
                SELECT DecompilationCode FROM Functions
                WHERE FunctionName = ? AND ParentClass = ?
                LIMIT 1
                """,
                (name, class_),
            ).fetchone()
        return None if row is None else row["DecompilationCode"]

    def get_resource_strings(self, limit: int = 100) -> List[Dict[str, Any]]:
        rows = self.conn.execute(
            "SELECT resourceId, value, type FROM ResourceStrings LIMIT ?",
            (limit,),
        ).fetchall()
        return [dict(r) for r in rows]

    def get_macho_strings(self, limit: int = 100) -> List[Dict[str, Any]]:
        rows = self.conn.execute(
            "SELECT address, value, segment, label, ExecutableName FROM MachoStrings LIMIT ?",
            (limit,),
        ).fetchall()
        return [dict(r) for r in rows]

    def get_function_references(self, fn: str) -> List[Dict[str, Any]]:
        rows = self.conn.execute(
            """
            SELECT 'FUNCTION' AS referenceType, sourceFunction, sourceClass,
                   targetFunction, targetClass, lineNumber, ExecutableName
            FROM FunctionReferences
            WHERE targetFunction = ? OR sourceFunction = ?
            """,
            (fn, fn),
        ).fetchall()
        return [dict(r) for r in rows]

    def search(self, query: str) -> List[Dict[str, str]]:
        term = f"%{query.lower()}%"
        results: List[Dict[str, str]] = []

        for row in self.conn.execute(
            """
            SELECT 'Function' AS type, FunctionName AS name,
                   ParentClass AS container, ExecutableName AS executable
            FROM Functions WHERE LOWER(FunctionName) LIKE ?
            """,
            (term,),
        ):
            results.append(
                {
                    "type": row["type"],
                    "name": row["name"],
                    "container": row["container"] or "",
                    "executable": row["executable"] or "",
                    "line": "",
                }
            )

        for row in self.conn.execute(
            """
            SELECT 'Variable' AS type, variableName AS name,
                   containingFunction || ' in ' || containingClass AS container,
                   ExecutableName AS executable, lineNumber
            FROM LocalVariableReferences WHERE LOWER(variableName) LIKE ?
            """,
            (term,),
        ):
            results.append(
                {
                    "type": row["type"],
                    "name": row["name"],
                    "container": row["container"] or "",
                    "executable": row["executable"] or "",
                    "line": str(row["lineNumber"] or ""),
                }
            )

        for row in self.conn.execute(
            """
            SELECT 'Class' AS type, ClassName AS name,
                   ExecutableName AS container, ExecutableName AS executable
            FROM Classes WHERE LOWER(ClassName) LIKE ?
            """,
            (term,),
        ):
            results.append(
                {
                    "type": row["type"],
                    "name": row["name"],
                    "container": row["container"] or "",
                    "executable": row["executable"] or "",
                    "line": "",
                }
            )

        return results

    def list_entrypoints(self) -> List[Dict[str, Any]]:
        meta = self.get_meta("entrypoints")
        if meta:
            try:
                data = json.loads(meta)
                if isinstance(data, list):
                    return data
                if isinstance(data, dict) and "entrypoints" in data:
                    return list(data["entrypoints"])
            except json.JSONDecodeError:
                pass

        placeholders = ",".join("?" for _ in ENTRYPOINT_NAMES)
        rows = self.conn.execute(
            f"""
            SELECT FunctionName, ParentClass, ExecutableName, DecompilationCode
            FROM Functions
            WHERE FunctionName IN ({placeholders})
            """,
            tuple(ENTRYPOINT_NAMES),
        ).fetchall()
        return [dict(r) for r in rows]

    # --- JSON import (DumpClassDataVibe) -----------------------------------------

    def import_class_json(self, path: PathLike) -> int:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        if not isinstance(data, list):
            raise ValueError("classes.json must be a JSON array")
        n = 0
        for item in data:
            class_name = item.get("ClassName") or item.get("className") or ""
            exe = item.get("ExecutableName") or item.get("executableFile") or ""
            functions = item.get("Functions") or item.get("functions") or []
            if isinstance(functions, str):
                try:
                    functions = json.loads(functions)
                except json.JSONDecodeError:
                    functions = [functions]
            self.insert_class(class_name, functions, exe)
            n += 1
        return n

    def import_functions_json(self, path: PathLike) -> int:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        if not isinstance(data, list):
            raise ValueError("functions.json must be a JSON array")
        n = 0
        for item in data:
            name = item.get("FunctionName") or item.get("functionName") or ""
            cls = item.get("ClassName") or item.get("ParentClass") or item.get("className") or ""
            exe = item.get("ExecutableName") or item.get("executableFile") or ""
            code = item.get("DecompiledCode") or item.get("DecompilationCode") or ""
            self.insert_function(name, cls, code, exe)
            n += 1
        return n

    def import_strings_json(self, path: PathLike) -> int:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        if not isinstance(data, list):
            raise ValueError("strings.json must be a JSON array")
        n = 0
        for item in data:
            self.insert_macho_string(
                address=item.get("address") or "",
                value=item.get("value") or "",
                segment=item.get("segment") or "",
                label=item.get("label") or "",
                executable_name=item.get("ExecutableName") or item.get("executableName") or "",
            )
            n += 1
        return n

    def import_refs_json(self, path: PathLike) -> int:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        if not isinstance(data, list):
            raise ValueError("refs.json must be a JSON array")
        n = 0
        for item in data:
            self.insert_function_reference(
                source_function=item.get("sourceFunction") or "",
                source_class=item.get("sourceClass") or "",
                target_function=item.get("targetFunction") or "",
                target_class=item.get("targetClass") or "",
                line_number=int(item.get("lineNumber") or 0),
                executable_name=item.get("ExecutableName") or "",
            )
            n += 1
        return n

    def stats(self) -> Dict[str, int]:
        tables = (
            "Classes",
            "Functions",
            "MachoStrings",
            "ResourceStrings",
            "FunctionReferences",
            "LocalVariableReferences",
            "TypeInformation",
            "Meta",
        )
        out: Dict[str, int] = {}
        for table in tables:
            row = self.conn.execute(f"SELECT COUNT(*) AS c FROM {table}").fetchone()
            out[table] = int(row["c"])
        return out
