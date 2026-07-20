use crate::embed::{cosine, hashing_embed, pack_f32, unpack_f32, DIM};
use anyhow::{Context, Result};
use rusqlite::{params, Connection};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub struct JSpaceStore {
    pub path: PathBuf,
    db: Connection,
}

impl JSpaceStore {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref().to_path_buf();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let db = Connection::open(&path).with_context(|| format!("open {}", path.display()))?;
        let store = Self { path, db };
        store.init()?;
        Ok(store)
    }

    fn init(&self) -> Result<()> {
        self.db.execute_batch(
            r#"
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
            "#,
        )?;
        Ok(())
    }

    pub fn stats(&self) -> Result<Value> {
        let n: i64 = self
            .db
            .query_row("SELECT COUNT(*) FROM chunks", [], |r| r.get(0))?;
        let mut kinds = serde_json::Map::new();
        let mut stmt = self
            .db
            .prepare("SELECT kind, COUNT(*) FROM chunks GROUP BY kind")?;
        let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))?;
        for row in rows {
            let (k, c) = row?;
            kinds.insert(k, json!(c));
        }
        Ok(json!({
            "path": self.path.to_string_lossy(),
            "chunks": n,
            "kinds": kinds,
            "dim": DIM,
        }))
    }

    pub fn upsert(
        &self,
        chunk_id: &str,
        kind: &str,
        text: &str,
        name: &str,
        address: &str,
        program: &str,
        meta: Value,
    ) -> Result<()> {
        let emb = pack_f32(&hashing_embed(&format!("{name}\n{text}")));
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs_f64();
        let meta_s = meta.to_string();
        self.db.execute(
            r#"
            INSERT INTO chunks(id, kind, program, name, address, text, meta, emb, updated)
            VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)
            ON CONFLICT(id) DO UPDATE SET
              kind=excluded.kind, program=excluded.program, name=excluded.name,
              address=excluded.address, text=excluded.text, meta=excluded.meta,
              emb=excluded.emb, updated=excluded.updated
            "#,
            params![
                chunk_id, kind, program, name, address, text, meta_s, emb, now
            ],
        )?;
        self.db
            .execute("DELETE FROM chunks_fts WHERE id = ?", params![chunk_id])?;
        self.db.execute(
            "INSERT INTO chunks_fts(id, name, text, kind, program) VALUES(?,?,?,?,?)",
            params![chunk_id, name, text, kind, program],
        )?;
        Ok(())
    }

    pub fn hybrid_search(
        &self,
        query: &str,
        top_k: usize,
        kind: Option<&str>,
    ) -> Result<Vec<Value>> {
        let q_emb = hashing_embed(query);
        let fts_q: String = query
            .replace('"', " ")
            .split_whitespace()
            .filter(|t| !t.is_empty())
            .collect::<Vec<_>>()
            .join(" ");

        let mut scored: HashMap<String, Value> = HashMap::new();

        if !fts_q.is_empty() {
            let lim = (top_k * 6) as i64;
            let rows: Result<Vec<Value>, rusqlite::Error> = if let Some(k) = kind {
                let mut stmt = self.db.prepare(
                    r#"
                  SELECT c.id, c.kind, c.program, c.name, c.address, c.text, c.meta, c.updated
                  FROM chunks_fts f
                  JOIN chunks c ON c.id = f.id
                  WHERE chunks_fts MATCH ?1 AND c.kind = ?2
                  LIMIT ?3
                "#,
                )?;
                let mapped = stmt.query_map(params![fts_q, k, lim], map_chunk_row)?;
                mapped.collect()
            } else {
                let mut stmt = self.db.prepare(
                    r#"
                  SELECT c.id, c.kind, c.program, c.name, c.address, c.text, c.meta, c.updated
                  FROM chunks_fts f
                  JOIN chunks c ON c.id = f.id
                  WHERE chunks_fts MATCH ?1
                  LIMIT ?2
                "#,
                )?;
                let mapped = stmt.query_map(params![fts_q, lim], map_chunk_row)?;
                mapped.collect()
            };
            if let Ok(rows) = rows {
                for mut d in rows {
                    let id = d["id"].as_str().unwrap_or("").to_string();
                    d["score"] = json!(0.55);
                    d["via"] = json!("fts");
                    scored.insert(id, d);
                }
            }
        }

        let pool_lim = (top_k * 40).max(400) as i64;
        let pool: Vec<(Value, Vec<u8>)> = if let Some(k) = kind {
            let mut stmt = self.db.prepare(
                "SELECT id, kind, program, name, address, text, meta, emb, updated FROM chunks WHERE kind = ?1 ORDER BY updated DESC LIMIT ?2",
            )?;
            let mapped = stmt.query_map(params![k, pool_lim], map_chunk_row_with_emb)?;
            mapped.collect::<Result<Vec<_>, _>>()?
        } else {
            let mut stmt = self.db.prepare(
                "SELECT id, kind, program, name, address, text, meta, emb, updated FROM chunks ORDER BY updated DESC LIMIT ?1",
            )?;
            let mapped = stmt.query_map(params![pool_lim], map_chunk_row_with_emb)?;
            mapped.collect::<Result<Vec<_>, _>>()?
        };

        for (mut d, emb_blob) in pool {
            let id = d["id"].as_str().unwrap_or("").to_string();
            let emb = unpack_f32(&emb_blob);
            let vscore = cosine(&q_emb, &emb);
            if let Some(existing) = scored.get_mut(&id) {
                let prev = existing["score"].as_f64().unwrap_or(0.0) as f32;
                let blended = 0.45 * prev + 0.55 * (0.5 + 0.5 * vscore);
                existing["score"] = json!(blended);
                existing["via"] = json!("hybrid");
            } else {
                d["score"] = json!(0.5 + 0.5 * vscore);
                d["via"] = json!("vec");
                scored.insert(id, d);
            }
        }

        let mut hits: Vec<Value> = scored.into_values().collect();
        hits.sort_by(|a, b| {
            b["score"]
                .as_f64()
                .unwrap_or(0.0)
                .partial_cmp(&a["score"].as_f64().unwrap_or(0.0))
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        hits.truncate(top_k);
        for h in &mut hits {
            if let Some(meta_s) = h.get("meta").and_then(|m| m.as_str()) {
                h["meta"] = serde_json::from_str(meta_s).unwrap_or_else(|_| json!({}));
            }
        }
        Ok(hits)
    }
}

fn map_chunk_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<Value> {
    Ok(json!({
        "id": r.get::<_, String>(0)?,
        "kind": r.get::<_, String>(1)?,
        "program": r.get::<_, String>(2)?,
        "name": r.get::<_, String>(3)?,
        "address": r.get::<_, String>(4)?,
        "text": r.get::<_, String>(5)?,
        "meta": r.get::<_, String>(6)?,
        "updated": r.get::<_, f64>(7)?,
    }))
}

fn map_chunk_row_with_emb(r: &rusqlite::Row<'_>) -> rusqlite::Result<(Value, Vec<u8>)> {
    let emb: Vec<u8> = r.get(7)?;
    let v = json!({
        "id": r.get::<_, String>(0)?,
        "kind": r.get::<_, String>(1)?,
        "program": r.get::<_, String>(2)?,
        "name": r.get::<_, String>(3)?,
        "address": r.get::<_, String>(4)?,
        "text": r.get::<_, String>(5)?,
        "meta": r.get::<_, String>(6)?,
        "updated": r.get::<_, f64>(8)?,
    });
    Ok((v, emb))
}
