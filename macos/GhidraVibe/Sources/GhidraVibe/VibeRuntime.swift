import Foundation

/// Resolves Ghidra / in-process engine / helper paths when launched outside `nix run`
/// (Finder double-click, bare `open`, packaged `~/Applications/GhidraVibe.app`).
///
/// `ProcessInfo.environment` is a launch-time snapshot — discoveries are applied via
/// `setenv` and cached so later reads see them.
enum VibeRuntime {
    private static let lock = NSLock()
    // Guarded by `lock`.
    nonisolated(unsafe) private static var extras: [String: String] = [:]
    nonisolated(unsafe) private static var didBootstrap = false

    /// Call once before AppModel / engine start. Safe to invoke repeatedly.
    static func bootstrap() {
        lock.lock()
        if didBootstrap {
            lock.unlock()
            return
        }
        didBootstrap = true
        lock.unlock()

        loadEnvFile(Bundle.main.resourcePath.map { $0 + "/runtime.env" })
        loadEnvFile(NSHomeDirectory() + "/Library/Application Support/GhidraVibe/runtime.env")

        // Reject packaged/inherited JAVA_HOME that lacks HotSpot (common Zulu store-root mistake).
        if let java = get("JAVA_HOME"), !isUsableJavaHome(java) {
            lock.lock()
            extras.removeValue(forKey: "JAVA_HOME")
            lock.unlock()
            unsetenv("JAVA_HOME")
        }
        if get("JAVA_HOME") == nil, let java = discoverJavaHome() {
            set("JAVA_HOME", java)
        }
        if get("GHIDRA_INSTALL_DIR") == nil, let install = discoverGhidraInstall() {
            set("GHIDRA_INSTALL_DIR", install)
            let root = ((install as NSString).deletingLastPathComponent as NSString)
                .deletingLastPathComponent
            let lib = root + "/share/ghidra-vibe/lib"
            if get("GHIDRA_VIBE_LIB") == nil,
               FileManager.default.isReadableFile(atPath: lib + "/detect-maxmem.sh")
            {
                set("GHIDRA_VIBE_LIB", lib)
            }
            if get("GHIDRA_VIBE_SCRIPT_PATH") == nil {
                let scripts = root + "/share/ghidra-vibe/ghidra_scripts"
                if FileManager.default.fileExists(atPath: scripts) {
                    set("GHIDRA_VIBE_SCRIPT_PATH", scripts)
                }
            }
        }
        if get("GHIDRA_VIBE_ENGINE_HOME") == nil, let home = discoverEngineHome() {
            set("GHIDRA_VIBE_ENGINE_HOME", home)
        }
        if let home = get("GHIDRA_VIBE_ENGINE_HOME") {
            let dylib = home + "/lib/libghidravibe_engine.dylib"
            let so = home + "/lib/libghidravibe_engine.so"
            let cp = home + "/share/ghidra-vibe/engine/classpath.txt"
            if get("GHIDRA_VIBE_ENGINE_LIB") == nil {
                if FileManager.default.isReadableFile(atPath: dylib) {
                    set("GHIDRA_VIBE_ENGINE_LIB", dylib)
                } else if FileManager.default.isReadableFile(atPath: so) {
                    set("GHIDRA_VIBE_ENGINE_LIB", so)
                }
            }
            if get("GHIDRA_VIBE_ENGINE_CLASSPATH_FILE") == nil,
               FileManager.default.isReadableFile(atPath: cp)
            {
                set("GHIDRA_VIBE_ENGINE_CLASSPATH_FILE", cp)
            }
        }
        if get("GHIDRA_VIBE_MCP_HEADLESS") == nil, let headless = discoverMcpHeadless() {
            set("GHIDRA_VIBE_MCP_HEADLESS", headless)
        }
        if get("GHIDRA_VIBE_ENGINE") == nil {
            set("GHIDRA_VIBE_ENGINE", "inprocess")
        }
    }

    static func get(_ key: String) -> String? {
        if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty {
            return v
        }
        lock.lock()
        let cached = extras[key]
        lock.unlock()
        if let cached, !cached.isEmpty { return cached }
        if let c = getenv(key) {
            let s = String(cString: c)
            return s.isEmpty ? nil : s
        }
        return nil
    }

    @discardableResult
    static func set(_ key: String, _ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        lock.lock()
        extras[key] = value
        lock.unlock()
        setenv(key, value, 0) // do not clobber an existing process env
        return true
    }

    // MARK: - discovery

    private static func loadEnvFile(_ path: String?) {
        guard let path, let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var val = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                val = String(val.dropFirst().dropLast())
            }
            if get(key) == nil {
                set(key, val)
            }
        }
    }

    private static func discoverJavaHome() -> String? {
        let fm = FileManager.default
        if let out = runCapture("/usr/libexec/java_home", ["-v", "21"])
            ?? runCapture("/usr/libexec/java_home", [])
        {
            let home = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if isUsableJavaHome(home) { return home }
        }
        // Prefer a Zulu/Temurin under /nix/store when present.
        for home in newestNixDirs(matching: #"zulu.*jdk|temurin.*jdk|openjdk"#) {
            for cand in [
                home + "/Library/Java/JavaVirtualMachines/zulu-21.jdk/Contents/Home",
                home + "/lib/openjdk",
                home,
            ] where isUsableJavaHome(cand) {
                return cand
            }
        }
        _ = fm
        return nil
    }

    private static func isUsableJavaHome(_ home: String) -> Bool {
        let fm = FileManager.default
        return fm.isReadableFile(atPath: home + "/lib/libjli.dylib")
            || fm.isReadableFile(atPath: home + "/lib/server/libjvm.dylib")
            || fm.isReadableFile(atPath: home + "/lib/server/libjvm.so")
    }

    private static func discoverGhidraInstall() -> String? {
        let fm = FileManager.default
        if let res = Bundle.main.resourcePath {
            let bundled = res + "/ghidra"
            if fm.fileExists(atPath: bundled + "/Ghidra") { return bundled }
        }
        // Prefer +native builds (GhidraVibe packaging).
        for root in newestNixDirs(matching: #"ghidra-vibe-.*\+native-"#) {
            let install = root + "/lib/ghidra"
            if fm.fileExists(atPath: install + "/Ghidra") { return install }
        }
        for root in newestNixDirs(matching: #"ghidra-vibe-"#) {
            let install = root + "/lib/ghidra"
            if fm.fileExists(atPath: install + "/Ghidra") { return install }
        }
        let repo = discoverRepoRoot()
        for rel in ["result/lib/ghidra", "result-ghidra/lib/ghidra"] {
            let install = repo + "/" + rel
            if fm.fileExists(atPath: install + "/Ghidra") { return install }
        }
        return nil
    }

    private static func discoverEngineHome() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let res = Bundle.main.resourcePath {
            candidates.append(res + "/engine")
        }
        candidates.append("/tmp/ghidra-vibe-engine-cfg-local")
        candidates.append(contentsOf: newestNixDirs(matching: #"ghidra-vibe-engine-"#))
        let repo = discoverRepoRoot()
        candidates.append(repo + "/result-engine")
        candidates.append(repo + "/result")
        for home in candidates {
            let dylib = home + "/lib/libghidravibe_engine.dylib"
            let so = home + "/lib/libghidravibe_engine.so"
            let cp = home + "/share/ghidra-vibe/engine/classpath.txt"
            if (fm.isReadableFile(atPath: dylib) || fm.isReadableFile(atPath: so)),
               fm.isReadableFile(atPath: cp)
            {
                return home
            }
        }
        return nil
    }

    private static func discoverMcpHeadless() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let res = Bundle.main.resourcePath {
            candidates.append(res + "/bin/ghidra-vibe-mcp-headless")
            candidates.append(res + "/Helpers/ghidra-vibe-mcp-headless")
        }
        let repo = discoverRepoRoot()
        candidates.append(repo + "/scripts/ghidra-vibe-mcp-headless")
        for root in newestNixDirs(matching: #"ghidra-vibe-mcp-headless$"#) {
            candidates.append(root + "/bin/ghidra-vibe-mcp-headless")
        }
        if let which = runCapture("/usr/bin/which", ["ghidra-vibe-mcp-headless"]) {
            candidates.append(which.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return candidates.first {
            !$0.isEmpty && fm.isExecutableFile(atPath: $0)
        }
    }

    /// Walk up from the .app (or CWD) looking for this repo's scripts/ tree.
    private static func discoverRepoRoot() -> String {
        let fm = FileManager.default
        var starts: [String] = [
            FileManager.default.currentDirectoryPath,
            Bundle.main.bundlePath,
            (Bundle.main.bundlePath as NSString).deletingLastPathComponent,
            NSHomeDirectory() + "/GhidraMCP_Vibe_RSE",
            NSHomeDirectory() + "/src/GhidraMCP_Vibe_RSE",
        ]
        // ~/Applications/GhidraVibe.app → often developed from ~/GhidraMCP_Vibe_RSE
        if let home = ProcessInfo.processInfo.environment["HOME"] ?? Optional(NSHomeDirectory()) {
            starts.append(home + "/GhidraMCP_Vibe_RSE")
        }
        for start in starts {
            var url = URL(fileURLWithPath: start)
            for _ in 0 ..< 8 {
                let marker = url.appendingPathComponent("scripts/ghidra-vibe-mcp-headless").path
                if fm.isExecutableFile(atPath: marker) {
                    return url.path
                }
                let parent = url.deletingLastPathComponent()
                if parent.path == url.path { break }
                url = parent
            }
        }
        return FileManager.default.currentDirectoryPath
    }

    /// Newest matching directories under /nix/store (mtime sort). Pattern is unanchored regex.
    private static func newestNixDirs(matching pattern: String) -> [String] {
        let store = "/nix/store"
        guard FileManager.default.fileExists(atPath: store) else { return [] }
        // `ls -dt` is faster and already mtime-sorted vs enumerating the whole store in Swift.
        let shell =
            "ls -dt \(store)/* 2>/dev/null | /usr/bin/grep -E '\(pattern)' | /usr/bin/head -n 12"
        guard let out = runCapture("/bin/zsh", ["-c", shell]) else { return [] }
        return out
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }
    }

    private static func runCapture(_ launchPath: String, _ arguments: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
