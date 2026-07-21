import SwiftUI

/// Hierarchical node for stock-style Program / Symbol / Data Type / Project trees.
struct OutlineTreeNode: Identifiable, Hashable {
    let id: String
    var title: String
    var systemImage: String
    /// `nil` = leaf (no chevron). Non-nil = folder (chevron even when empty).
    var children: [OutlineTreeNode]?
    /// Opaque payload (address, path, type name) for selection handlers.
    var payload: String?

    var isFolder: Bool { children != nil }

    static func folder(
        id: String,
        title: String,
        systemImage: String = "folder.fill",
        children: [OutlineTreeNode] = []
    ) -> OutlineTreeNode {
        OutlineTreeNode(id: id, title: title, systemImage: systemImage, children: children, payload: nil)
    }

    static func leaf(
        id: String,
        title: String,
        systemImage: String = "doc",
        payload: String? = nil
    ) -> OutlineTreeNode {
        OutlineTreeNode(id: id, title: title, systemImage: systemImage, children: nil, payload: payload ?? title)
    }
}

/// Native macOS sidebar outline: disclosure chevrons, expand/collapse, and selection.
struct NativeOutlineTree: View {
    let roots: [OutlineTreeNode]
    @Binding var selection: String?
    var a11yId: String
    var emptyLabel: String = "No items"
    /// Optional drag payload for Agent composer drops (`@` mention or file attachment).
    var agentDrag: OutlineAgentDragSource? = nil
    var onSelect: ((OutlineTreeNode) -> Void)? = nil

    var body: some View {
        Group {
            if roots.isEmpty {
                List {
                    Label(emptyLabel, systemImage: "folder")
                        .foregroundStyle(Color.vibeSecondary)
                        .font(.caption)
                        .listRowBackground(Color.vibeContent)
                }
                .listStyle(.sidebar)
                .vibeThemedList()
            } else {
                // Hierarchical List API = native macOS disclosure chevrons + selection.
                List(
                    roots,
                    children: \.children,
                    selection: Binding(
                        get: { selection },
                        set: { newValue in
                            selection = newValue
                            if let id = newValue, let node = Self.find(id: id, in: roots) {
                                onSelect?(node)
                            }
                        }
                    )
                ) { node in
                    Label {
                        Text(node.title)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: node.systemImage)
                            .foregroundStyle(node.isFolder ? Color.vibeAccent : Color.vibeSecondary)
                    }
                    .help(node.payload ?? node.title)
                    .tag(node.id)
                    .accessibilityIdentifier(node.id)
                    .outlineAgentDraggable(agentDrag?.resolve(node))
                }
                .listStyle(.sidebar)
                .vibeThemedList()
            }
        }
        // Let parent concentric / provider shells own the plate — AppKit list chrome is square.
        .scrollContentBackground(.hidden)
        .background(Color.vibeContent)
        .environment(\.defaultMinListRowHeight, 20)
        .a11yCatalog(a11yId)
    }

    static func find(id: String, in nodes: [OutlineTreeNode]) -> OutlineTreeNode? {
        for node in nodes {
            if node.id == id { return node }
            if let kids = node.children, let hit = find(id: id, in: kids) {
                return hit
            }
        }
        return nil
    }
}

enum OutlineTreeBuilder {
    /// Program Trees: program root → segments / bundle binaries (expandable).
    static func programTree(
        programName: String,
        segments: [String],
        bundleRows: [String],
        fallbackNodes: [String]
    ) -> [OutlineTreeNode] {
        if !bundleRows.isEmpty {
            let leaves = bundleRows.map { row in
                let path = row.split(separator: "]").last
                    .map { String($0).trimmingCharacters(in: .whitespaces) } ?? row
                return OutlineTreeNode.leaf(
                    id: "ghidra.vibe.provider.program_tree.row.\(path)",
                    title: URL(fileURLWithPath: path).lastPathComponent,
                    systemImage: "doc",
                    payload: path
                )
            }
            let macos = OutlineTreeNode.folder(
                id: "ghidra.vibe.provider.program_tree.macos",
                title: "MacOS",
                systemImage: "folder.fill",
                children: leaves
            )
            let contents = OutlineTreeNode.folder(
                id: "ghidra.vibe.provider.program_tree.contents",
                title: "Contents",
                systemImage: "folder.fill",
                children: [macos]
            )
            return [
                OutlineTreeNode.folder(
                    id: "ghidra.vibe.provider.program_tree.bundle",
                    title: "App Bundle",
                    systemImage: "app.badge",
                    children: [contents]
                )
            ]
        }

        let cleanSegments = segments.filter {
            !$0.hasPrefix("(") && !$0.isEmpty
        }
        let segmentLeaves: [OutlineTreeNode] = {
            let source = cleanSegments.isEmpty
                ? fallbackNodes.filter { !$0.hasPrefix("(") && $0 != "(open a program)" }
                : cleanSegments
            return source.map { row in
                OutlineTreeNode.leaf(
                    id: "ghidra.vibe.provider.program_tree.seg.\(row)",
                    title: row,
                    systemImage: "rectangle.split.3x1",
                    payload: row
                )
            }
        }()

        let rootTitle = programName.isEmpty ? "Program" : programName
        let defaultTree = OutlineTreeNode.folder(
            id: "ghidra.vibe.provider.program_tree.default",
            title: "Program Tree",
            systemImage: "folder.fill",
            children: segmentLeaves
        )
        return [
            OutlineTreeNode.folder(
                id: "ghidra.vibe.provider.program_tree.root",
                title: rootTitle,
                systemImage: "internaldrive.fill",
                children: [defaultTree]
            )
        ]
    }

    /// Symbol Tree: Imports / Exports / Functions / Namespaces / Globals.
    static func symbolTree(
        functions: [(name: String, address: String)],
        tableRows: [String],
        namespaces: [String],
        filter: String
    ) -> [OutlineTreeNode] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ s: String) -> Bool {
            q.isEmpty || s.localizedCaseInsensitiveContains(q)
        }

        var imports: [OutlineTreeNode] = []
        var exports: [OutlineTreeNode] = []
        var globals: [OutlineTreeNode] = []
        for row in tableRows {
            let label: String
            let bucket: String
            if row.hasPrefix("[list_imports]") {
                bucket = "imports"
                label = String(row.dropFirst("[list_imports]".count)).trimmingCharacters(in: .whitespaces)
            } else if row.hasPrefix("[list_exports]") {
                bucket = "exports"
                label = String(row.dropFirst("[list_exports]".count)).trimmingCharacters(in: .whitespaces)
            } else if row.hasPrefix("[list_globals]") {
                bucket = "globals"
                label = String(row.dropFirst("[list_globals]".count)).trimmingCharacters(in: .whitespaces)
            } else if row.contains("\t") {
                let parts = row.split(separator: "\t", maxSplits: 1).map(String.init)
                bucket = "functions"
                label = parts.count == 2 ? parts[1] : row
            } else {
                continue
            }
            guard matches(label) else { continue }
            let node = OutlineTreeNode.leaf(
                id: "ghidra.vibe.provider.symbol_tree.\(bucket).\(label)",
                title: label,
                systemImage: bucket == "functions" ? "f.cursive" : "tag",
                payload: label
            )
            switch bucket {
            case "imports": imports.append(node)
            case "exports": exports.append(node)
            case "globals": globals.append(node)
            default: break
            }
        }

        let fnLeaves = functions
            .filter { matches($0.name) }
            .prefix(500)
            .map { fn in
                OutlineTreeNode.leaf(
                    id: "ghidra.vibe.provider.symbol_tree.fn.\(fn.address).\(fn.name)",
                    title: fn.name,
                    systemImage: "f.cursive",
                    payload: "\(fn.address)\t\(fn.name)"
                )
            }

        let nsLeaves = namespaces
            .filter { matches($0) && !$0.hasPrefix("[") }
            .prefix(200)
            .map { ns in
                OutlineTreeNode.leaf(
                    id: "ghidra.vibe.provider.symbol_tree.ns.\(ns)",
                    title: ns,
                    systemImage: "shippingbox",
                    payload: ns
                )
            }

        // Prefer table-derived functions when present; else MCP function list.
        let functionChildren: [OutlineTreeNode] = {
            let fromTable = tableRows.compactMap { row -> OutlineTreeNode? in
                guard !row.hasPrefix("["), row.contains("\t") else { return nil }
                let parts = row.split(separator: "\t", maxSplits: 1).map(String.init)
                let name = parts.count == 2 ? parts[1] : row
                let addr = parts.count == 2 ? parts[0] : ""
                guard matches(name) else { return nil }
                return OutlineTreeNode.leaf(
                    id: "ghidra.vibe.provider.symbol_tree.fn.\(addr).\(name)",
                    title: name,
                    systemImage: "f.cursive",
                    payload: row
                )
            }
            if !fromTable.isEmpty { return Array(fromTable.prefix(500)) }
            return Array(fnLeaves)
        }()

        return [
            OutlineTreeNode.folder(
                id: "ghidra.vibe.provider.symbol_tree.imports",
                title: "Imports",
                systemImage: "arrow.down.doc",
                children: Array(imports.prefix(300))
            ),
            OutlineTreeNode.folder(
                id: "ghidra.vibe.provider.symbol_tree.exports",
                title: "Exports",
                systemImage: "arrow.up.doc",
                children: Array(exports.prefix(300))
            ),
            OutlineTreeNode.folder(
                id: "ghidra.vibe.provider.symbol_tree.functions",
                title: "Functions",
                systemImage: "f.cursive",
                children: functionChildren
            ),
            OutlineTreeNode.folder(
                id: "ghidra.vibe.provider.symbol_tree.namespaces",
                title: "Namespaces",
                systemImage: "shippingbox.fill",
                children: Array(nsLeaves)
            ),
            OutlineTreeNode.folder(
                id: "ghidra.vibe.provider.symbol_tree.globals",
                title: "Labels",
                systemImage: "tag.fill",
                children: Array(globals.prefix(300))
            ),
        ]
    }

    /// Data Type Manager: archives as folders; path-like names nest under `/`.
    static func dataTypes(nodes: [String], filter: String) -> [OutlineTreeNode] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        let display: [(raw: String, name: String)] = nodes.map { raw in
            (raw, displayDataTypeName(raw))
        }.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }

        // Group path-like "Archive/Category/Type" under archive folders.
        var archives: [String: [OutlineTreeNode]] = [:]
        var flatLeaves: [OutlineTreeNode] = []
        for item in display {
            let parts = item.name.split(separator: "/").map(String.init)
            if parts.count >= 2 {
                let archive = parts[0]
                let leafTitle = parts.dropFirst().joined(separator: "/")
                var kids = archives[archive] ?? []
                kids.append(OutlineTreeNode.leaf(
                    id: "ghidra.vibe.provider.data_types.row.\(item.raw)",
                    title: leafTitle,
                    systemImage: "doc.text",
                    payload: item.raw
                ))
                archives[archive] = kids
            } else {
                flatLeaves.append(OutlineTreeNode.leaf(
                    id: "ghidra.vibe.provider.data_types.row.\(item.raw)",
                    title: item.name,
                    systemImage: item.name == "BuiltInTypes" ? "book.closed.fill" : "book.fill",
                    payload: item.raw
                ))
            }
        }

        if archives.isEmpty {
            return [
                OutlineTreeNode.folder(
                    id: "ghidra.vibe.provider.data_types.root",
                    title: "Data Types",
                    systemImage: "books.vertical.fill",
                    children: flatLeaves
                )
            ]
        }

        var folders = archives.keys.sorted().map { key in
            OutlineTreeNode.folder(
                id: "ghidra.vibe.provider.data_types.archive.\(key)",
                title: key,
                systemImage: key == "BuiltInTypes" ? "book.closed.fill" : "book.fill",
                children: archives[key] ?? []
            )
        }
        if !flatLeaves.isEmpty {
            folders.insert(
                OutlineTreeNode.folder(
                    id: "ghidra.vibe.provider.data_types.misc",
                    title: "Archives",
                    systemImage: "books.vertical.fill",
                    children: flatLeaves
                ),
                at: 0
            )
        }
        return folders
    }

    /// Active Project tree: project root → programs.
    static func projectTree(projectPath: String, programs: [String]) -> [OutlineTreeNode] {
        let title: String = {
            if projectPath.isEmpty { return "No Project" }
            return URL(fileURLWithPath: projectPath).deletingPathExtension().lastPathComponent
        }()
        let kids = programs.map { name in
            OutlineTreeNode.leaf(
                id: "ghidra.vibe.project.row.\(name)",
                title: name,
                systemImage: "doc",
                payload: name
            )
        }
        return [
            OutlineTreeNode.folder(
                id: "ghidra.vibe.project.root",
                title: title,
                systemImage: "folder.fill",
                children: kids
            )
        ]
    }

    private static func displayDataTypeName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "builtin", "builtintypes": return "BuiltInTypes"
        case "mac", "macos", "mac_osx": return "mac_osx"
        default: return raw
        }
    }
}
