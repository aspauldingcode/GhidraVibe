/// Offline RE playbook cards (always available without MCP).
pub const PLAYBOOK: &[(&str, &str)] = &[
    (
        "triage",
        "RE triage loop: (1) list interesting strings/imports (2) locate xrefs \
         (3) decompile callers (4) rename with role (5) follow data flow to sinks \
         (crypto/network/file). Prefer small confirmed facts.",
    ),
    (
        "objc",
        "ObjC/Swift: find objc_msgSend stubs, recover selectors from __objc_methname, \
         map class clusters, watch retain/release imbalance, check Swift demangler names.",
    ),
    (
        "swift",
        "Swift/SwiftUI RE: enable Demangler Swift + Swift Type Metadata Analyzer; \
         walk __swift5_types / __swift5_proto / __swift5_protos; demangle $s/_$s symbols \
         via swift demangle; recover View protocol witnesses and opaque type descriptors. \
         SwiftUI is not a separate decompiler — treat as Swift ABI + ObjC interop edges.",
    ),
    (
        "dyld",
        "DSC workflow: open on-device dyld_shared_cache → DSC Index → load one framework \
         (AppKit/SkyLight/…) via DyldCacheFileSystem with Apple local symbols. Do not ipsw-extract.",
    ),
    (
        "crypto",
        "Crypto hunt: CommonCrypto/CCCrypt, SecKey, AES/SHA constants, key material in \
         stack buffers, wrap/unwrap APIs, compare to known KDF patterns.",
    ),
    (
        "auth",
        "Auth path: password/token strings → validators → Keychain/LAContext → entitlement \
         checks → network login. Note bypass candidates near strcmp/memcmp.",
    ),
    (
        "ui-skylight",
        "Windowing: AppKit → SkyLight/WindowServer. Track CGS/SLS symbols, event taps, \
         display geometry, and security-sensitive screen capture APIs.",
    ),
];
