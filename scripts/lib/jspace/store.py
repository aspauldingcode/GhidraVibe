"""SQLite JSpace store: FTS5 lexical + float32 vector blobs."""
from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path

from .embed import DIM, cosine, hashing_embed, pack_f32, unpack_f32


class JSpaceStore:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(self.path))
        self.db.row_factory = sqlite3.Row
        self._init()

    def _init(self) -> None:
        self.db.executescript(
            """
            CREATE TABLE IF NOT EXISTS chunks (
              id TEXT PRIMARY KEY,
              kind TEXT NOT NULL,
              program TEXT,
              name TEXT,
              address TEXT,
              text TEXT NOT NULL,
              meta TEXT,
              emb BLOB NOT NULL,
              updated REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_chunks_kind ON chunks(kind);
            CREATE INDEX IF NOT EXISTS idx_chunks_addr ON chunks(address);
            CREATE INDEX IF NOT EXISTS idx_chunks_name ON chunks(name);
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
              id UNINDEXED, name, text, kind UNINDEXED, program UNINDEXED
            );
            CREATE TABLE IF NOT EXISTS meta_kv (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
            """
        )
        self.db.commit()

    def close(self) -> None:
        self.db.close()

    def stats(self) -> dict:
        n = self.db.execute("SELECT COUNT(*) AS c FROM chunks").fetchone()["c"]
        kinds = {
            r["kind"]: r["c"]
            for r in self.db.execute(
                "SELECT kind, COUNT(*) AS c FROM chunks GROUP BY kind"
            )
        }
        return {"path": str(self.path), "chunks": n, "kinds": kinds, "dim": DIM}

    def upsert(
        self,
        *,
        chunk_id: str,
        kind: str,
        text: str,
        name: str = "",
        address: str = "",
        program: str = "",
        meta: dict | None = None,
    ) -> None:
        emb = pack_f32(hashing_embed(f"{name}\n{text}"))
        now = time.time()
        meta_s = json.dumps(meta or {})
        self.db.execute(
            """
            INSERT INTO chunks(id, kind, program, name, address, text, meta, emb, updated)
            VALUES(?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
              kind=excluded.kind, program=excluded.program, name=excluded.name,
              address=excluded.address, text=excluded.text, meta=excluded.meta,
              emb=excluded.emb, updated=excluded.updated
            """,
            (chunk_id, kind, program, name, address, text, meta_s, emb, now),
        )
        # Keep FTS in sync (delete+insert)
        self.db.execute("DELETE FROM chunks_fts WHERE id = ?", (chunk_id,))
        self.db.execute(
            "INSERT INTO chunks_fts(id, name, text, kind, program) VALUES(?,?,?,?,?)",
            (chunk_id, name, text, kind, program),
        )
        self.db.commit()

    def hybrid_search(
        self, query: str, *, top_k: int = 8, kind: str | None = None
    ) -> list[dict]:
        q_emb = hashing_embed(query)
        # Lexical candidates
        fts_q = " ".join(t for t in query.replace('"', " ").split() if t)
        lexical: list[sqlite3.Row] = []
        if fts_q:
            try:
                sql = """
                  SELECT c.* FROM chunks_fts f
                  JOIN chunks c ON c.id = f.id
                  WHERE chunks_fts MATCH ?
                """
                args: list = [fts_q]
                if kind:
                    sql += " AND c.kind = ?"
                    args.append(kind)
                sql += " LIMIT ?"
                args.append(top_k * 6)
                lexical = list(self.db.execute(sql, args))
            except sqlite3.OperationalError:
                lexical = []

        # Vector over a wider pool (or all if small)
        pool_sql = "SELECT * FROM chunks"
        pool_args: list = []
        if kind:
            pool_sql += " WHERE kind = ?"
            pool_args.append(kind)
        pool_sql += " ORDER BY updated DESC LIMIT ?"
        pool_args.append(max(400, top_k * 40))
        pool = list(self.db.execute(pool_sql, pool_args))

        scored: dict[str, dict] = {}
        for row in lexical:
            d = dict(row)
            d["score"] = 0.55
            d["via"] = "fts"
            scored[d["id"]] = d
        for row in pool:
            d = dict(row)
            emb = unpack_f32(d["emb"])
            vscore = cosine(q_emb, emb)
            if d["id"] in scored:
                scored[d["id"]]["score"] = 0.45 * scored[d["id"]]["score"] + 0.55 * (
                    0.5 + 0.5 * vscore
                )
                scored[d["id"]]["via"] = "hybrid"
            else:
                d["score"] = 0.5 + 0.5 * vscore
                d["via"] = "vec"
                scored[d["id"]] = d

        hits = sorted(scored.values(), key=lambda x: x["score"], reverse=True)[:top_k]
        for h in hits:
            h.pop("emb", None)
            try:
                h["meta"] = json.loads(h.get("meta") or "{}")
            except json.JSONDecodeError:
                h["meta"] = {}
        return hits
