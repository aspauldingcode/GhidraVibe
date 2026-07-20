import Darwin
import Foundation

/// Embeds HotSpot in this process and starts GhidraMCPHeadlessServer in-JVM.
/// Default GUI path — not a sidecar Process. True headless CLI uses
/// `ghidra-vibe-mcp-headless` separately.
enum InProcessEngineHost {
    private static let lock = NSLock()
    // Guarded by `lock` (dlopen / JVM start is process-global).
    nonisolated(unsafe) private static var started = false
    nonisolated(unsafe) private static var libHandle: UnsafeMutableRawPointer?

    typealias StartFn = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32

    typealias FreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
    typealias RunningFn = @convention(c) () -> Int32
    typealias CallFn = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32

    struct StartResult {
        var ok: Bool
        var message: String
        var json: [String: Any] = [:]
    }

    static var isAvailable: Bool {
        VibeRuntime.bootstrap()
        return resolveLibPath() != nil && resolveClasspath() != nil
    }

    static var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard started, let handle = libHandle else { return false }
        guard let sym = dlsym(handle, "ghidra_vibe_engine_running") else { return false }
        let running = unsafeBitCast(sym, to: RunningFn.self)
        return running() != 0
    }

    /// Embed JVM + start in-process engine API (same port the UI already uses).
    static func start(
        port: Int,
        project: String?,
        program: String?,
        xmx: String? = nil
    ) -> StartResult {
        lock.lock()
        defer { lock.unlock() }
        if started {
            return StartResult(ok: true, message: "already started")
        }

        VibeRuntime.bootstrap()
        guard let javaHome = resolveJavaHome() else {
            return StartResult(ok: false, message: "JAVA_HOME required (JDK with libjvm/libjli)")
        }
        guard let install = VibeRuntime.get("GHIDRA_INSTALL_DIR"), !install.isEmpty else {
            return StartResult(ok: false, message: "GHIDRA_INSTALL_DIR required")
        }
        guard let classpath = resolveClasspath() else {
            return StartResult(ok: false, message: "engine classpath missing (GHIDRA_VIBE_ENGINE_CP)")
        }
        guard let libPath = resolveLibPath() else {
            return StartResult(ok: false, message: "libghidravibe_engine missing (GHIDRA_VIBE_ENGINE_LIB)")
        }

        guard let handle = dlopen(libPath, RTLD_NOW | RTLD_LOCAL) else {
            let err = String(cString: dlerror())
            return StartResult(ok: false, message: "dlopen engine: \(err)")
        }
        libHandle = handle
        guard let startSym = dlsym(handle, "ghidra_vibe_engine_start"),
              let freeSym = dlsym(handle, "ghidra_vibe_engine_free")
        else {
            return StartResult(ok: false, message: "engine symbols missing")
        }
        let startFn = unsafeBitCast(startSym, to: StartFn.self)
        let freeFn = unsafeBitCast(freeSym, to: FreeFn.self)

        // Build JSON by hand so paths stay `/Users/...` (not `\/Users\/...`).
        // Escaped solidus breaks HeadlessProgramProvider (treats path as relative).
        var parts: [String] = [
            "\"port\":\(port)",
            "\"bind\":\"127.0.0.1\"",
        ]
        if let project, !project.isEmpty {
            parts.append("\"project\":\(Self.jsonString(project))")
        }
        if let program, !program.isEmpty {
            let p = program.hasPrefix("/") ? program : "/\(program)"
            parts.append("\"program\":\(Self.jsonString(p))")
        }
        let argsJson = "{\(parts.joined(separator: ","))}"

        let mem = xmx
            ?? VibeRuntime.get("GHIDRA_VIBE_MAXMEM")
            ?? VibeRuntime.get("MAXMEM")
            ?? "4G"

        var outPtr: UnsafeMutablePointer<CChar>?
        let rc = javaHome.withCString { jh in
            classpath.withCString { cp in
                install.withCString { inst in
                    argsJson.withCString { aj in
                        mem.withCString { mx in
                            startFn(jh, cp, inst, aj, mx, &outPtr)
                        }
                    }
                }
            }
        }
        let text: String
        if let outPtr {
            text = String(cString: outPtr)
            freeFn(outPtr)
        } else {
            text = "{\"ok\":false,\"error\":\"no response (rc=\(rc))\"}"
        }

        if let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
            let ok = (obj["ok"] as? Bool) ?? false
            let msg = (obj["message"] as? String)
                ?? (obj["error"] as? String)
                ?? text
            if ok {
                started = true
            }
            return StartResult(ok: ok, message: msg, json: obj)
        }
        let ok = rc == 0 && text.contains("\"ok\":true")
        if ok { started = true }
        return StartResult(ok: ok, message: text)
    }

    /// Direct JNI call into InProcessEngine (open project/program without flaky HTTP params).
    static func call(_ method: String, args: [String: Any] = [:]) -> StartResult {
        lock.lock()
        defer { lock.unlock() }
        guard started, let handle = libHandle else {
            return StartResult(ok: false, message: "engine not started")
        }
        guard let callSym = dlsym(handle, "ghidra_vibe_engine_call"),
              let freeSym = dlsym(handle, "ghidra_vibe_engine_free")
        else {
            return StartResult(ok: false, message: "engine call symbols missing")
        }
        let callFn = unsafeBitCast(callSym, to: CallFn.self)
        let freeFn = unsafeBitCast(freeSym, to: FreeFn.self)
        let argsJson = Self.jsonObject(args)
        var outPtr: UnsafeMutablePointer<CChar>?
        let rc = method.withCString { m in
            argsJson.withCString { a in
                callFn(m, a, &outPtr)
            }
        }
        let text: String
        if let outPtr {
            text = String(cString: outPtr)
            freeFn(outPtr)
        } else {
            text = "{\"ok\":false,\"error\":\"no response (rc=\(rc))\"}"
        }
        if let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
            let ok = (obj["ok"] as? Bool) ?? false
            let msg = (obj["message"] as? String) ?? (obj["error"] as? String) ?? text
            return StartResult(ok: ok, message: msg, json: obj)
        }
        return StartResult(ok: rc == 0, message: text)
    }

    private static func jsonString(_ s: String) -> String {
        var out = "\""
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(ch) // keep `/` unescaped
            }
        }
        return out + "\""
    }

    private static func jsonObject(_ args: [String: Any]) -> String {
        var parts: [String] = []
        for (k, v) in args {
            let key = jsonString(k)
            if let s = v as? String {
                parts.append("\(key):\(jsonString(s))")
            } else if let i = v as? Int {
                parts.append("\(key):\(i)")
            } else if let b = v as? Bool {
                parts.append("\(key):\(b ? "true" : "false")")
            } else {
                parts.append("\(key):\(jsonString(String(describing: v)))")
            }
        }
        return "{\(parts.joined(separator: ","))}"
    }

    /// Prefer a JDK root that actually contains HotSpot (`libjli` / `libjvm`).
    private static func resolveJavaHome() -> String? {
        let raw = VibeRuntime.get("JAVA_HOME") ?? ""
        var candidates: [String] = []
        if !raw.isEmpty {
            candidates.append(raw)
            // Broken inheritance sometimes appends /lib/openjdk to the Zulu root.
            if raw.hasSuffix("/lib/openjdk") {
                candidates.append(String(raw.dropLast("/lib/openjdk".count)))
            }
            candidates.append(raw + "/lib/openjdk")
            candidates.append((raw as NSString).deletingLastPathComponent)
        }
        let fm = FileManager.default
        for home in candidates where !home.isEmpty {
            let jli = home + "/lib/libjli.dylib"
            let jvm = home + "/lib/server/libjvm.dylib"
            let jvmSo = home + "/lib/server/libjvm.so"
            if fm.isReadableFile(atPath: jli)
                || fm.isReadableFile(atPath: jvm)
                || fm.isReadableFile(atPath: jvmSo)
            {
                return home
            }
        }
        return nil
    }

    private static func resolveLibPath() -> String? {
        let home = VibeRuntime.get("GHIDRA_VIBE_ENGINE_HOME") ?? ""
        let candidates = [
            VibeRuntime.get("GHIDRA_VIBE_ENGINE_LIB") ?? "",
            home + "/lib/libghidravibe_engine.dylib",
            home + "/lib/libghidravibe_engine.so",
        ]
        return candidates.first {
            !$0.isEmpty && FileManager.default.isReadableFile(atPath: $0)
        }
    }

    private static func resolveClasspath() -> String? {
        if let cp = VibeRuntime.get("GHIDRA_VIBE_ENGINE_CP"), !cp.isEmpty {
            return cp
        }
        let home = VibeRuntime.get("GHIDRA_VIBE_ENGINE_HOME") ?? ""
        let fileCandidates = [
            VibeRuntime.get("GHIDRA_VIBE_ENGINE_CLASSPATH_FILE") ?? "",
            home + "/share/ghidra-vibe/engine/classpath.txt",
        ]
        for path in fileCandidates where !path.isEmpty {
            if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
                if !line.isEmpty { return line.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        return nil
    }
}
