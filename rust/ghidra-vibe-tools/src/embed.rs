use blake2::{Blake2b, Digest};
use std::collections::HashMap;

pub const DIM: usize = 384;

/// Intent lexicon → boost tokens so retrieval matches how reverse engineers think.
const RE_INTENTS: &[(&str, &[&str])] = &[
    (
        "crypto",
        &[
            "aes", "sha", "hmac", "rsa", "cccrypt", "commoncrypto", "encrypt", "decrypt",
            "keychain", "seckey", "random", "nonce", "iv",
        ],
    ),
    (
        "objc",
        &[
            "objc_msgsend", "nsobject", "selector", "imp", "class_get", "swift", "retain",
            "release", "autorelease", "nsstring",
        ],
    ),
    (
        "swift",
        &[
            "swiftui", "view", "protocol", "metadata", "demangle", "$s", "_$s", "witness",
            "conformance", "opaque", "actor", "async",
        ],
    ),
    (
        "dyld",
        &[
            "dyld", "shared cache", "dlopen", "dlsym", "image", "mach-o", "lc_load",
            "interpose", "stub",
        ],
    ),
    (
        "auth",
        &[
            "password", "token", "oauth", "login", "session", "credential", "biometric",
            "lah", "secaccess", "entitlement",
        ],
    ),
    (
        "network",
        &[
            "socket", "connect", "http", "cfnetwork", "nsurlsession", "tls", "ssl",
            "websocket", "dns",
        ],
    ),
    (
        "ipc",
        &["xpc", "mach_msg", "distributed", "notification", "cfmessage", "mig"],
    ),
    (
        "ui",
        &[
            "nsview", "nswindow", "appkit", "skylight", "cgwindow", "hit test", "event",
            "runloop", "display",
        ],
    ),
    (
        "persist",
        &["sqlite", "plist", "nsuserdefaults", "file", "write", "fopen", "coredata"],
    ),
];

pub fn tokenize(text: &str) -> Vec<String> {
    let lower = text.to_lowercase();
    let mut out = Vec::new();
    let mut cur = String::new();
    let push = |cur: &mut String, out: &mut Vec<String>| {
        if cur.len() > 1 {
            out.push(std::mem::take(cur));
        } else {
            cur.clear();
        }
    };
    let bytes = lower.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        // hex address
        if bytes[i] == b'0'
            && i + 1 < bytes.len()
            && bytes[i + 1] == b'x'
        {
            push(&mut cur, &mut out);
            let mut j = i + 2;
            while j < bytes.len() && bytes[j].is_ascii_hexdigit() {
                j += 1;
            }
            if j > i + 2 {
                out.push(lower[i..j].to_string());
            }
            i = j;
            continue;
        }
        // objc selector-ish @name
        if bytes[i] == b'@' && i + 1 < bytes.len() && (bytes[i + 1].is_ascii_alphabetic() || bytes[i + 1] == b'_') {
            push(&mut cur, &mut out);
            let mut j = i + 1;
            while j < bytes.len()
                && (bytes[j].is_ascii_alphanumeric() || bytes[j] == b'_' || bytes[j] == b':')
            {
                j += 1;
            }
            out.push(lower[i..j].to_string());
            i = j;
            continue;
        }
        let c = bytes[i] as char;
        if c.is_ascii_alphanumeric() || c == '_' {
            cur.push(c);
        } else {
            push(&mut cur, &mut out);
        }
        i += 1;
    }
    push(&mut cur, &mut out);
    out
}

pub fn expand_re_query(query: &str) -> String {
    let q = query.trim();
    let ql = q.to_lowercase();
    let mut extra: Vec<&str> = Vec::new();
    for (intent, words) in RE_INTENTS {
        let hit_intent = ql.contains(intent);
        let hit_word = words.iter().take(4).any(|w| ql.contains(w));
        if hit_intent || hit_word {
            extra.extend(words.iter().copied().take(8));
            extra.push(intent);
        }
    }
    if ["how", "what", "where", "trace", "find", "similar"]
        .iter()
        .any(|v| ql.contains(v))
    {
        extra.extend(["xref", "caller", "callee", "string", "symbol"]);
    }
    if ql.contains("decompile") || ql.contains("pseudocode") {
        extra.extend(["function", "listing", "prototype"]);
    }
    if ql.contains("swiftui") || ql.contains("swift") {
        extra.extend(["demangle", "metadata", "protocol", "view"]);
    }
    if extra.is_empty() {
        return q.to_string();
    }
    let mut seen = std::collections::HashSet::new();
    let mut uniq = Vec::new();
    for w in extra {
        if seen.insert(w) {
            uniq.push(w);
        }
    }
    format!("{q} {}", uniq.join(" "))
}

pub fn hashing_embed(text: &str) -> Vec<f32> {
    let mut vec = vec![0.0f32; DIM];
    let toks = tokenize(text);
    if toks.is_empty() {
        return vec;
    }
    let mut counts: HashMap<&str, usize> = HashMap::new();
    for t in &toks {
        *counts.entry(t.as_str()).or_default() += 1;
    }
    for (tok, c) in counts {
        let mut hasher = Blake2b::<blake2::digest::consts::U8>::new();
        hasher.update(tok.as_bytes());
        let h = hasher.finalize();
        let idx = u32::from_le_bytes([h[0], h[1], h[2], h[3]]) as usize % DIM;
        let sign = if h[4] & 1 == 0 { 1.0f32 } else { -1.0f32 };
        let weight = sign
            * (1.0 + (c as f32).ln_1p())
            * (3.0f32).min(0.5 + tok.len() as f32 / 12.0);
        vec[idx] += weight;
    }
    let norm = vec.iter().map(|v| v * v).sum::<f32>().sqrt().max(1e-12);
    for v in &mut vec {
        *v /= norm;
    }
    vec
}

pub fn cosine(a: &[f32], b: &[f32]) -> f32 {
    a.iter().zip(b.iter()).map(|(x, y)| x * y).sum()
}

pub fn pack_f32(vec: &[f32]) -> Vec<u8> {
    let mut out = Vec::with_capacity(vec.len() * 4);
    for v in vec {
        out.extend_from_slice(&v.to_le_bytes());
    }
    out
}

pub fn unpack_f32(blob: &[u8]) -> Vec<f32> {
    blob.chunks_exact(4)
        .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]))
        .collect()
}
