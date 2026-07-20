use crate::playbook::PLAYBOOK;
use crate::store::JSpaceStore;
use anyhow::{Context, Result};
use serde_json::{json, Value};
use std::env;

fn mcp_url() -> String {
    env::var("GHIDRA_MCP_URL")
        .or_else(|_| env::var("GHIDRA_MCP_SERVER"))
        .unwrap_or_else(|_| "http://127.0.0.1:8089".into())
        .trim_end_matches('/')
        .to_string()
}

fn mcp_get(path: &str, params: &[(&str, &str)], timeout_secs: u64) -> Result<String> {
    let base = mcp_url();
    let mut url = format!("{base}{path}");
    if !params.is_empty() {
        let enc: Vec<String> = params
            .iter()
            .map(|(k, v)| format!("{}={}", urlencoding_lite(k), urlencoding_lite(v)))
            .collect();
        url.push('?');
        url.push_str(&enc.join("&"));
    }
    let agent = ureq::AgentBuilder::new()
        .timeout(std::time::Duration::from_secs(timeout_secs))
        .build();
    let resp = agent
        .get(&url)
        .call()
        .with_context(|| format!("MCP unreachable at {base}"))?;
    Ok(resp.into_string()?)
}

fn urlencoding_lite(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char)
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

fn parse_methods(text: &str) -> Vec<(String, String)> {
    let mut rows = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('{') || line.starts_with('[') {
            continue;
        }
        if let Some((name, rest)) = line
            .split_once(" at ")
            .or_else(|| line.split_once(" @ "))
        {
            let addr = rest.split_whitespace().next().unwrap_or("").to_string();
            rows.push((name.trim().to_string(), addr));
        } else if line.contains('\t') {
            let parts: Vec<_> = line.split('\t').map(str::trim).filter(|p| !p.is_empty()).collect();
            if parts.len() >= 2 {
                rows.push((parts[0].to_string(), parts[1].to_string()));
            }
        } else {
            let name = line.split_whitespace().next().unwrap_or(line).to_string();
            rows.push((name, String::new()));
        }
    }
    rows
}

fn decompile_one(name: &str, addr: &str) -> String {
    // bethington GhidraMCP headless uses /decompile_function; GUI bridge also accepts /decompile.
    if !addr.is_empty() {
        if let Ok(s) = mcp_get("/decompile_function", &[("address", addr)], 90) {
            if !s.is_empty() && !s.to_lowercase().contains("\"error\"") {
                return s;
            }
        }
    }
    mcp_get("/decompile_function", &[("name", name)], 90)
        .or_else(|_| mcp_get("/decompile", &[("name", name)], 90))
        .unwrap_or_default()
}

pub fn index_playbook_only(store: &JSpaceStore) -> Result<Value> {
    for (key, text) in PLAYBOOK {
        store.upsert(
            &format!("playbook:{key}"),
            "playbook",
            text,
            key,
            "",
            "",
            json!({"source": "jspace-playbook"}),
        )?;
    }
    Ok(json!({
        "ok": true,
        "playbook": PLAYBOOK.len(),
        "stats": store.stats()?,
    }))
}

pub fn index_from_mcp(
    store: &JSpaceStore,
    program: &str,
    limit: usize,
    decompile_top: usize,
) -> Result<Value> {
    // Prefer list_functions ("name at addr") so decompiles can use addresses.
    let methods_raw = mcp_get(
        "/list_functions",
        &[("offset", "0"), ("limit", &limit.to_string())],
        60,
    )
    .or_else(|_| {
        mcp_get(
            "/list_methods",
            &[("offset", "0"), ("limit", &limit.to_string())],
            60,
        )
    })
    .or_else(|_| mcp_get("/methods", &[], 60))?;
    let methods = parse_methods(&methods_raw);
    let methods: Vec<_> = methods.into_iter().take(limit).collect();
    let mut n_fn = 0usize;
    let mut n_dec = 0usize;
    for (i, (name, addr)) in methods.iter().enumerate() {
        let body = format!("Function {name} at {addr}");
        let id = format!("fn:{}", if addr.is_empty() { name.as_str() } else { addr });
        store.upsert(
            &id,
            "function",
            &body,
            name,
            addr,
            program,
            json!({"source": "list_methods"}),
        )?;
        n_fn += 1;
        if i < decompile_top {
            let dec = decompile_one(name, addr);
            let head = dec.to_lowercase();
            let head = &head[..head.len().min(40)];
            if !dec.is_empty() && !head.contains("error") && !head.contains("404") {
                let did = format!("dec:{}", if addr.is_empty() { name.as_str() } else { addr });
                let text: String = dec.chars().take(8000).collect();
                store.upsert(
                    &did,
                    "decompile",
                    &text,
                    name,
                    addr,
                    program,
                    json!({"source": "decompile_function"}),
                )?;
                n_dec += 1;
            }
        }
    }

    let mut n_str = 0usize;
    let raw = mcp_get("/list_strings", &[("offset", "0"), ("limit", "500")], 60)
        .or_else(|_| mcp_get("/strings", &[], 60))
        .or_else(|_| mcp_get("/listStrings", &[], 60))
        .unwrap_or_default();
    for (j, line) in raw.lines().take(500).enumerate() {
        let s = line.trim();
        if s.len() < 4 {
            continue;
        }
        let hash = {
            use blake2::{Blake2b, Digest};
            let mut h = Blake2b::<blake2::digest::consts::U8>::new();
            h.update(s.as_bytes());
            hex::encode(h.finalize())
        };
        let name: String = s.chars().take(80).collect();
        let text: String = s.chars().take(2000).collect();
        store.upsert(
            &format!("str:{j}:{hash}"),
            "string",
            &text,
            &name,
            "",
            program,
            json!({"source": "strings"}),
        )?;
        n_str += 1;
    }

    for (key, text) in PLAYBOOK {
        store.upsert(
            &format!("playbook:{key}"),
            "playbook",
            text,
            key,
            "",
            "",
            json!({"source": "jspace-playbook"}),
        )?;
    }

    Ok(json!({
        "ok": true,
        "functions": n_fn,
        "decompiles": n_dec,
        "strings": n_str,
        "playbook": PLAYBOOK.len(),
        "stats": store.stats()?,
    }))
}
