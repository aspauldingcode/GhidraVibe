use crate::embed::expand_re_query;
use crate::store::JSpaceStore;
use anyhow::Result;
use serde_json::Value;

const DISCOVERY_PREAMBLE: &str = "\
# RE discovery context (JSpace)
You are investigating a binary with Ghidra. Use the retrieved cards below as
working memory before calling MCP tools. Prefer evidence (addresses, names,
strings) over speculation. When unsure, decompile / list xrefs via Ghidra MCP.
";

pub fn search(
    store: &JSpaceStore,
    query: &str,
    top_k: usize,
    kind: Option<&str>,
) -> Result<Vec<Value>> {
    let expanded = expand_re_query(query);
    store.hybrid_search(&expanded, top_k, kind)
}

fn format_card(hit: &Value, idx: usize) -> String {
    let name = hit["name"].as_str().unwrap_or("(unnamed)");
    let addr = hit["address"].as_str().unwrap_or("");
    let kind = hit["kind"].as_str().unwrap_or("chunk");
    let score = hit["score"].as_f64().unwrap_or(0.0);
    let via = hit["via"].as_str().unwrap_or("");
    let text = hit["text"].as_str().unwrap_or("");
    let text: String = text.chars().take(1200).collect();
    format!(
        "### [{idx}] {kind} `{name}` @ {addr} (score={score:.3} via={via})\n{text}\n"
    )
}

pub fn discovery_context(
    store: &JSpaceStore,
    query: &str,
    top_k: usize,
    current_function: Option<&str>,
    current_decompile: Option<&str>,
) -> Result<String> {
    let mut parts = vec![
        DISCOVERY_PREAMBLE.to_string(),
        format!("## Question\n{query}\n"),
    ];
    if let Some(fn_name) = current_function {
        parts.push(format!("## Current selection\nFunction: `{fn_name}`\n"));
        if let Some(dec) = current_decompile {
            let slice: String = dec.chars().take(2000).collect();
            parts.push(format!("```c\n{slice}\n```\n"));
        }
    }
    let hits = search(store, query, top_k, None)?;
    parts.push("## Retrieved RE cards\n".into());
    if hits.is_empty() {
        parts.push(
            "_JSpace empty — run `ghidra-vibe-jspace index` after MCP is up._\n".into(),
        );
    } else {
        for (i, h) in hits.iter().enumerate() {
            parts.push(format_card(h, i + 1));
        }
    }
    parts.push(
        "## Suggested next MCP moves\n\
         - `methods` / select a card name\n\
         - `decompile` the top hit\n\
         - `xrefs` / `get_xrefs_to` for callers\n\
         - for Swift: confirm Demangler Swift + Type Metadata ran\n\
         - rename once the role is clear\n"
            .into(),
    );
    Ok(parts.join("\n"))
}
