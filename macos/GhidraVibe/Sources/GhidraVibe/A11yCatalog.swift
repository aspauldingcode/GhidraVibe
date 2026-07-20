import Foundation
import SwiftUI

struct A11yEntry: Codable, Hashable {
    var id: String
    var label: String
    var hint: String
    var traits: [String]
}

enum A11yCatalog {
    static let shared: [String: A11yEntry] = load()

    /// Resolve catalog.json without `Bundle.module` (that traps when the .app
    /// was packaged with only the Mach-O and no SPM resource bundle).
    static func catalogFileURL() -> URL? {
        var candidates: [URL] = []

        if let main = Bundle.main.url(forResource: "catalog", withExtension: "json") {
            candidates.append(main)
        }
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("catalog.json"))
            candidates.append(res.appendingPathComponent("GhidraVibe_GhidraVibe.bundle/Contents/Resources/catalog.json"))
            candidates.append(res.appendingPathComponent("GhidraVibe_GhidraVibe.bundle/catalog.json"))
        }

        let exe = Bundle.main.executableURL?.deletingLastPathComponent()
        if let exe {
            candidates.append(exe.appendingPathComponent("catalog.json"))
            candidates.append(exe.appendingPathComponent("../Resources/catalog.json"))
            // SwiftPM debug/release layout next to the binary
            candidates.append(exe.appendingPathComponent("GhidraVibe_GhidraVibe.bundle/Contents/Resources/catalog.json"))
            candidates.append(exe.appendingPathComponent("GhidraVibe_GhidraVibe.bundle/catalog.json"))
        }

        if let dataDir = ProcessInfo.processInfo.environment["GHIDRA_VIBE_UI_DATA"], !dataDir.isEmpty {
            candidates.append(URL(fileURLWithPath: dataDir).appendingPathComponent("catalog.json"))
            candidates.append(URL(fileURLWithPath: dataDir).appendingPathComponent("a11y/catalog.json"))
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("native-ui/a11y/catalog.json"))
        candidates.append(cwd.appendingPathComponent("macos/GhidraVibe/Sources/GhidraVibe/Resources/catalog.json"))

        for url in candidates {
            let resolved = url.standardizedFileURL
            if FileManager.default.isReadableFile(atPath: resolved.path) {
                return resolved
            }
        }
        return nil
    }

    private static func load() -> [String: A11yEntry] {
        guard let url = catalogFileURL(),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(CatalogRoot.self, from: data)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: root.entries.map { ($0.id, $0) })
    }

    private struct CatalogRoot: Codable {
        var entries: [A11yEntry]
    }

    static func entry(_ id: String) -> A11yEntry {
        shared[id] ?? A11yEntry(id: id, label: id, hint: id, traits: [])
    }

    /// Prefer catalog hint for hover tooltips; never return empty.
    static func hoverTip(for id: String, fallback: String? = nil) -> String {
        let e = entry(id)
        let h = e.hint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !h.isEmpty, h != id { return h }
        let l = e.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !l.isEmpty, l != id { return l }
        let f = (fallback ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return f.isEmpty ? id : f
    }

    static func catalogJSONString() -> String? {
        guard let url = catalogFileURL(),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension View {
    /// Bind stable id + label + hint (+ button trait) from the shared catalog.
    /// Always sets a non-empty hover tooltip (`.help`) from hint, else label.
    func a11yCatalog(_ id: String) -> some View {
        let e = A11yCatalog.entry(id)
        let tip = A11yCatalog.hoverTip(for: id)
        return self
            .accessibilityIdentifier(e.id)
            .accessibilityLabel(e.label)
            .accessibilityHint(tip)
            .help(tip)
            .modifier(A11yTraitModifier(traits: e.traits))
    }

    func a11yContainerCatalog(_ id: String) -> some View {
        let e = A11yCatalog.entry(id)
        return self
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(e.id)
            .accessibilityLabel(e.label)
    }

    /// Hover tooltip when a control is not wired through `a11yCatalog`.
    func hoverHelp(_ text: String) -> some View {
        let tip = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return self.help(tip.isEmpty ? "Action" : tip)
    }
}

private struct A11yTraitModifier: ViewModifier {
    let traits: [String]
    func body(content: Content) -> some View {
        if traits.contains("button") {
            content.accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}
