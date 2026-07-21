import AppKit
import Foundation

/// User-owned local model registry. **No weights ship in the app or Nix store.**
/// Drop `.gguf` / `.ccp` (llama.cpp) into the dedicated Models folder.
enum AgentLocalModels {
    static let directoryName = "models"
    static let manifestName = "models.json"
    /// Accepted drop extensions (llama.cpp GGUF; `.ccp` accepted as alias).
    static let weightExtensions: Set<String> = ["gguf", "ccp"]

    struct Entry: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var displayName: String
        var relativePath: String
        var addedAt: Date

        var absoluteURL: URL {
            AgentLocalModels.modelsDirectory.appendingPathComponent(relativePath)
        }
    }

    struct Manifest: Codable, Sendable {
        var models: [Entry]
    }

    /// `~/Library/Application Support/GhidraVibe/models` — override with `GHIDRA_VIBE_AI_MODELS_DIR`.
    static var modelsDirectory: URL {
        if let env = ProcessInfo.processInfo.environment["GHIDRA_VIBE_AI_MODELS_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty
        {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("GhidraVibe", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static var manifestURL: URL {
        modelsDirectory.appendingPathComponent(manifestName)
    }

    @discardableResult
    static func ensureDirectory() throws -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: modelsDirectory.path) {
            try fm.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        }
        let readme = modelsDirectory.appendingPathComponent("README.txt")
        if !fm.fileExists(atPath: readme.path) {
            let text = """
            GhidraVibe local models (user-owned — never bundled with the app).

            Drop .gguf (or .ccp) files here, or use Drag & Drop on the Agent Setup panel.
            Serve with llama-server, e.g.:
              llama-server -m ./your-model.gguf --port 8080

            Nix: programs.ghidra-vibe.agent.modelsDir / agent.ollama.ensureModels
            """
            try text.write(to: readme, atomically: true, encoding: .utf8)
        }
        return modelsDirectory
    }

    static func loadManifest() -> Manifest {
        guard let data = try? Data(contentsOf: manifestURL),
              let m = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return Manifest(models: []) }
        return m
    }

    static func saveManifest(_ manifest: Manifest) throws {
        try ensureDirectory()
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    static func listEntries() -> [Entry] {
        let m = loadManifest()
        let fm = FileManager.default
        var byId = Dictionary(uniqueKeysWithValues: m.models.map { ($0.id, $0) })
        if let files = try? fm.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil) {
            for url in files where weightExtensions.contains(url.pathExtension.lowercased()) {
                let name = url.lastPathComponent
                if byId.values.contains(where: { $0.relativePath == name }) { continue }
                byId[name] = Entry(
                    id: name,
                    displayName: url.deletingPathExtension().lastPathComponent,
                    relativePath: name,
                    addedAt: Date()
                )
            }
        }
        return byId.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    @discardableResult
    static func importWeight(from source: URL, copy: Bool = true) throws -> Entry {
        try ensureDirectory()
        let ext = source.pathExtension.lowercased()
        guard weightExtensions.contains(ext) else {
            throw AgentLocalModelsError.unsupportedExtension(ext)
        }
        let destName = source.lastPathComponent
        let dest = modelsDirectory.appendingPathComponent(destName)
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        if copy {
            try fm.copyItem(at: source, to: dest)
        } else {
            try fm.moveItem(at: source, to: dest)
        }
        var manifest = loadManifest()
        let entry = Entry(
            id: destName,
            displayName: source.deletingPathExtension().lastPathComponent,
            relativePath: destName,
            addedAt: Date()
        )
        manifest.models.removeAll { $0.id == entry.id || $0.relativePath == entry.relativePath }
        manifest.models.append(entry)
        try saveManifest(manifest)
        return entry
    }

    static func openInFinder() {
        try? ensureDirectory()
        NSWorkspace.shared.open(modelsDirectory)
    }
}

enum AgentLocalModelsError: Error, LocalizedError {
    case unsupportedExtension(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedExtension(let e):
            return "Unsupported model file .\(e) — drop .gguf (llama.cpp) or .ccp"
        }
    }
}
