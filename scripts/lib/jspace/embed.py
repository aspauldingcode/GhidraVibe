"""Local embeddings + RE query expansion (no cloud, no heavy ML deps by default)."""
from __future__ import annotations

import hashlib
import math
import re
from collections import Counter

DIM = 384

# Intent lexicon → boost tokens so retrieval matches how reverse engineers think.
RE_INTENTS: dict[str, list[str]] = {
    "crypto": [
        "aes", "sha", "hmac", "rsa", "cccrypt", "commoncrypto", "encrypt", "decrypt",
        "keychain", "seckey", "random", "nonce", "iv",
    ],
    "objc": [
        "objc_msgsend", "nsobject", "selector", "imp", "class_get", "swift", "retain",
        "release", "autorelease", "nsstring",
    ],
    "dyld": [
        "dyld", "shared cache", "dlopen", "dlsym", "image", "mach-o", "lc_load",
        "interpose", "stub",
    ],
    "auth": [
        "password", "token", "oauth", "login", "session", "credential", "biometric",
        "lah", "secaccess", "entitlement",
    ],
    "network": [
        "socket", "connect", "http", "cfnetwork", "nsurlsession", "tls", "ssl",
        "websocket", "dns",
    ],
    "ipc": [
        "xpc", "mach_msg", "distributed", "notification", "cfmessage", "mig",
    ],
    "ui": [
        "nsview", "nswindow", "appkit", "skylight", "cgwindow", "hit test", "event",
        "runloop", "display",
    ],
    "persist": [
        "sqlite", "plist", "nsuserdefaults", "file", "write", "fopen", "coredata",
    ],
}


def tokenize(text: str) -> list[str]:
    text = text.lower()
    # Keep hex addresses and objc-ish tokens
    parts = re.findall(r"[a-z_][a-z0-9_]*|0x[0-9a-f]+|@[a-zA-Z_][\w:]*", text)
    return [p for p in parts if len(p) > 1]


def expand_re_query(query: str) -> str:
    """Expand a natural-language RE question with intent synonyms (JSpace boost)."""
    q = query.strip()
    ql = q.lower()
    extra: list[str] = []
    for intent, words in RE_INTENTS.items():
        if intent in ql or any(w in ql for w in words[:4]):
            extra.extend(words[:8])
            extra.append(intent)
    # Heuristic verbs → investigation facets
    if any(v in ql for v in ("how", "what", "where", "trace", "find", "similar")):
        extra.extend(["xref", "caller", "callee", "string", "symbol"])
    if "decompile" in ql or "pseudocode" in ql:
        extra.extend(["function", "listing", "prototype"])
    if extra:
        return q + " " + " ".join(dict.fromkeys(extra))
    return q


def hashing_embed(text: str, dim: int = DIM) -> list[float]:
    """Feature-hashing bag-of-words embedding (deterministic, local, fast)."""
    vec = [0.0] * dim
    toks = tokenize(text)
    if not toks:
        return vec
    counts = Counter(toks)
    for tok, c in counts.items():
        h = hashlib.blake2b(tok.encode(), digest_size=8).digest()
        idx = int.from_bytes(h[:4], "little") % dim
        sign = 1.0 if h[4] & 1 == 0 else -1.0
        # Mild IDF-ish: rarer longer tokens weigh more
        weight = sign * (1.0 + math.log1p(c)) * min(3.0, 0.5 + len(tok) / 12.0)
        vec[idx] += weight
    # L2 normalize
    norm = math.sqrt(sum(v * v for v in vec)) or 1.0
    return [v / norm for v in vec]


def cosine(a: list[float], b: list[float]) -> float:
    return sum(x * y for x, y in zip(a, b, strict=True))


def pack_f32(vec: list[float]) -> bytes:
    import struct

    return struct.pack(f"{len(vec)}f", *vec)


def unpack_f32(blob: bytes, dim: int = DIM) -> list[float]:
    import struct

    n = len(blob) // 4
    if n != dim:
        dim = n
    return list(struct.unpack(f"{dim}f", blob[: dim * 4]))
