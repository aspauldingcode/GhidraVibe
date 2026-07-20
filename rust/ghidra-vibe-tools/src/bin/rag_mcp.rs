//! MCP stdio bridge: JSpace RE RAG tools (Rust — replaces bridge_mcp_rag.py).
use anyhow::Result;
use ghidra_vibe_tools::index_mcp::{index_from_mcp, index_playbook_only};
use ghidra_vibe_tools::retrieve::{discovery_context, search};
use ghidra_vibe_tools::JSpaceStore;
use serde_json::{json, Value};
use std::io::{BufRead, Write};
use std::path::PathBuf;

fn db_path() -> PathBuf {
    if let Ok(p) = std::env::var("GHIDRA_VIBE_JSPACE_DB") {
        return PathBuf::from(p);
    }
    dirs_next_cache()
}

fn dirs_next_cache() -> PathBuf {
    if let Ok(home) = std::env::var("HOME") {
        return PathBuf::from(home)
            .join(".cache")
            .join("ghidra-vibe")
            .join("jspace.sqlite");
    }
    PathBuf::from("/tmp/ghidra-vibe-jspace.sqlite")
}

fn store() -> Result<JSpaceStore> {
    JSpaceStore::open(db_path())
}

fn tools() -> Value {
    json!([
        {
            "name": "rag_stats",
            "description": "JSpace index stats (chunk counts by kind)",
            "inputSchema": { "type": "object", "properties": {} }
        },
        {
            "name": "rag_index",
            "description": "Index live Ghidra MCP analysis into JSpace",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "limit": { "type": "integer", "default": 200 },
                    "decompile_top": { "type": "integer", "default": 40 },
                    "playbook_only": { "type": "boolean", "default": false }
                }
            }
        },
        {
            "name": "rag_search",
            "description": "Hybrid FTS+vector search over JSpace RE cards",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "query": { "type": "string" },
                    "top_k": { "type": "integer", "default": 8 },
                    "kind": { "type": "string" }
                },
                "required": ["query"]
            }
        },
        {
            "name": "rag_discover",
            "description": "Build an RE discovery context pack. Call BEFORE answering RE questions.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "query": { "type": "string" },
                    "top_k": { "type": "integer", "default": 8 },
                    "function": { "type": "string" },
                    "decompile": { "type": "string" }
                },
                "required": ["query"]
            }
        }
    ])
}

fn handle(name: &str, args: &Value) -> Result<Value> {
    let st = store()?;
    Ok(match name {
        "rag_stats" => st.stats()?,
        "rag_index" => {
            if args
                .get("playbook_only")
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
            {
                index_playbook_only(&st)?
            } else {
                index_from_mcp(
                    &st,
                    "",
                    args.get("limit").and_then(|v| v.as_u64()).unwrap_or(200) as usize,
                    args.get("decompile_top")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(40) as usize,
                )?
            }
        }
        "rag_search" => json!({
            "ok": true,
            "hits": search(
                &st,
                args["query"].as_str().unwrap_or(""),
                args.get("top_k").and_then(|v| v.as_u64()).unwrap_or(8) as usize,
                args.get("kind").and_then(|v| v.as_str()),
            )?
        }),
        "rag_discover" => json!({
            "ok": true,
            "discovery": discovery_context(
                &st,
                args["query"].as_str().unwrap_or(""),
                args.get("top_k").and_then(|v| v.as_u64()).unwrap_or(8) as usize,
                args.get("function").and_then(|v| v.as_str()),
                args.get("decompile").and_then(|v| v.as_str()),
            )?
        }),
        other => json!({"error": format!("unknown tool: {other}")}),
    })
}

fn respond(id: &Value, result: Value) {
    let msg = json!({
        "jsonrpc": "2.0",
        "id": id,
        "result": result
    });
    let mut stdout = std::io::stdout().lock();
    let _ = writeln!(stdout, "{msg}");
    let _ = stdout.flush();
}

fn respond_err(id: &Value, message: &str) {
    let msg = json!({
        "jsonrpc": "2.0",
        "id": id,
        "error": { "code": -32000, "message": message }
    });
    let mut stdout = std::io::stdout().lock();
    let _ = writeln!(stdout, "{msg}");
    let _ = stdout.flush();
}

fn main() -> Result<()> {
    let stdin = std::io::stdin();
    for line in stdin.lock().lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        let msg: Value = match serde_json::from_str(&line) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let method = msg.get("method").and_then(|m| m.as_str()).unwrap_or("");
        let id = msg.get("id").cloned().unwrap_or(Value::Null);
        match method {
            "initialize" => respond(
                &id,
                json!({
                    "protocolVersion": "2024-11-05",
                    "capabilities": { "tools": {} },
                    "serverInfo": { "name": "ghidra-vibe-rag", "version": "0.2.0" }
                }),
            ),
            "notifications/initialized" | "initialized" => {}
            "tools/list" => respond(&id, json!({ "tools": tools() })),
            "tools/call" => {
                let params = msg.get("params").cloned().unwrap_or(json!({}));
                let name = params.get("name").and_then(|n| n.as_str()).unwrap_or("");
                let args = params.get("arguments").cloned().unwrap_or(json!({}));
                match handle(name, &args) {
                    Ok(result) => respond(
                        &id,
                        json!({
                            "content": [{
                                "type": "text",
                                "text": serde_json::to_string_pretty(&result).unwrap_or_default()
                            }]
                        }),
                    ),
                    Err(e) => respond_err(&id, &e.to_string()),
                }
            }
            "ping" => {
                respond(&id, json!({}));
            }
            _ => {
                if !id.is_null() {
                    respond_err(&id, &format!("unsupported method: {method}"));
                }
            }
        }
    }
    Ok(())
}
