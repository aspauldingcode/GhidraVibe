import Foundation
import SwiftUI

/// Local toolbar button from CodeBrowser.chrome.json / inventory.
struct ProviderToolbarSpec: Hashable, Identifiable {
    var id: String
    var label: String
    var hint: String
    var systemImage: String
    var behavior: String

    /// Control exists in stock chrome but is not implemented yet — not “MCP offline”.
    var isHonestDisabled: Bool { behavior == "disabled_honest" }
}

/// Inventory-driven provider chrome toolbars (stock 1:1 labels / hints).
enum ProviderChromeCatalog {
    private static let specsByTitle: [String: [ProviderToolbarSpec]] = load()

    static func toolbar(for kind: ProviderKind) -> [ProviderToolbarSpec] {
        specsByTitle[kind.title] ?? []
    }

    private static func load() -> [String: [ProviderToolbarSpec]] {
        guard let url = chromeFileURL(),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let local = root["providerLocalToolbars"] as? [String: [[String: Any]]]
        else {
            return [:]
        }
        var out: [String: [ProviderToolbarSpec]] = [:]
        for (title, rows) in local {
            out[title] = rows.compactMap { row in
                guard let id = row["id"] as? String,
                      let label = row["label"] as? String
                else { return nil }
                let hint = (row["hint"] as? String)
                    ?? A11yCatalog.hoverTip(for: id, fallback: label)
                let behavior = (row["behavior"] as? String) ?? "disabled_honest"
                return ProviderToolbarSpec(
                    id: id,
                    label: label,
                    hint: hint,
                    systemImage: symbol(for: id),
                    behavior: behavior
                )
            }
        }
        return out
    }

    private static func chromeFileURL() -> URL? {
        var candidates: [URL] = []
        if let main = Bundle.main.url(forResource: "CodeBrowser.chrome", withExtension: "json") {
            candidates.append(main)
        }
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("CodeBrowser.chrome.json"))
            candidates.append(res.appendingPathComponent("parity/CodeBrowser.chrome.json"))
        }
        if let dataDir = ProcessInfo.processInfo.environment["GHIDRA_VIBE_UI_DATA"], !dataDir.isEmpty {
            let base = URL(fileURLWithPath: dataDir)
            candidates.append(base.appendingPathComponent("CodeBrowser.chrome.json"))
            candidates.append(base.appendingPathComponent("parity/CodeBrowser.chrome.json"))
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("native-ui/parity/CodeBrowser.chrome.json"))
        for url in candidates where FileManager.default.isReadableFile(atPath: url.path) {
            return url.standardizedFileURL
        }
        return nil
    }

    private static func symbol(for id: String) -> String {
        let key = id.lowercased()
        if key.contains("refresh") || key.contains("snapshot") { return "arrow.clockwise" }
        if key.contains("settings") || key.contains("options") { return "gearshape" }
        if key.contains("filter") { return "doc.text.magnifyingglass" }
        if key.contains("clear") { return "trash" }
        if key.contains("lock") { return "lock.open" }
        if key.contains("copy") { return "doc.on.doc" }
        if key.contains("export") { return "square.and.arrow.up" }
        if key.contains("marker") || key.contains("bookmark") { return "bookmark" }
        if key.contains("create_folder") || key.contains("create_symbol") { return "folder.badge.plus" }
        if key.contains("create_fragment") { return "rectangle.stack.badge.plus" }
        if key.contains("create_tree") || key.contains("create_namespace") { return "doc.badge.plus" }
        if key.contains("create_class") || key.contains("create") { return "plus.square.on.square" }
        if key.contains("open_archive") { return "books.vertical" }
        if key.contains("back") || key.contains("previous") { return "chevron.left" }
        if key.contains("forward") || key.contains("next") { return "chevron.right" }
        if key.contains("camera") { return "camera" }
        if key.contains("goto") { return "arrow.right.circle" }
        return "wrench.and.screwdriver"
    }
}
