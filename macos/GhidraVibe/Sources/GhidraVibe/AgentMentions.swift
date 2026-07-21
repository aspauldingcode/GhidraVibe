import Foundation

/// Cursor-style `@` mentions for the Agent composer — RE-scoped categories.
enum AgentMentionCategory: String, CaseIterable, Identifiable, Hashable {
    case functions
    case providers
    case program
    case classes
    case pastChats
    case docs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .functions: "Functions"
        case .providers: "Providers"
        case .program: "Program & Selection"
        case .classes: "Classes"
        case .pastChats: "Past Chats"
        case .docs: "Docs"
        }
    }

    var systemImage: String {
        switch self {
        case .functions: "function"
        case .providers: "rectangle.split.3x1"
        case .program: "doc.text"
        case .classes: "square.grid.3x3"
        case .pastChats: "bubble.left.and.bubble.right"
        case .docs: "book"
        }
    }

    var subtitle: String {
        switch self {
        case .functions: "Symbols from the open program"
        case .providers: "CodeBrowser panes / Modules"
        case .program: "Current program, project, selection"
        case .classes: "ObjC / Swift class names"
        case .pastChats: "This chat + recent project sessions"
        case .docs: "GhidraVibe RE playbook topics"
        }
    }

    /// Whether this row drills into a searchable list (vs one-shot items at root).
    var hasChildren: Bool {
        switch self {
        case .functions, .providers, .classes, .pastChats, .docs: true
        case .program: true
        }
    }
}

struct AgentMentionItem: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    /// Inserted into the composer, e.g. `@Functions:entry`.
    var token: String
}

enum AgentMentions {
    /// Token pattern: `@Functions:entry`, `@Providers:decompiler`, `@Selection`, …
    nonisolated static let tokenRegex = try! NSRegularExpression(
        pattern: #"@([A-Za-z]+):([^\s@]+)|@(Selection|Program)\b"#,
        options: []
    )

    static func rootItems() -> [AgentMentionItem] {
        AgentMentionCategory.allCases.map { cat in
            AgentMentionItem(
                id: "cat.\(cat.rawValue)",
                title: cat.title,
                subtitle: cat.subtitle,
                systemImage: cat.systemImage,
                token: "" // category drill — not inserted
            )
        }
    }

    @MainActor
    static func items(
        category: AgentMentionCategory,
        query: String,
        model: AppModel
    ) -> [AgentMentionItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: ([AgentMentionItem]) -> [AgentMentionItem] = { rows in
            guard !q.isEmpty else { return Array(rows.prefix(40)) }
            return rows.filter {
                $0.title.lowercased().contains(q)
                    || $0.subtitle.lowercased().contains(q)
                    || $0.token.lowercased().contains(q)
            }.prefix(40).map { $0 }
        }

        switch category {
        case .functions:
            let rows = model.functions.map { fn in
                AgentMentionItem(
                    id: "fn.\(fn.id)",
                    title: fn.name,
                    subtitle: fn.address.isEmpty ? "function" : fn.address,
                    systemImage: "function",
                    token: "@Functions:\(sanitizeToken(fn.name))"
                )
            }
            return filtered(rows)

        case .providers:
            let kinds: [ProviderKind] = [
                .listing, .decompiler, .functions, .functionGraph, .strings,
                .symbolTree, .dataTypes, .console, .memoryMap, .bytes,
                .dsc, .appleBundle, .swiftClasses, .rag, .mcp, .agent,
            ]
            let rows = kinds.map { kind in
                AgentMentionItem(
                    id: "prov.\(kind.rawValue)",
                    title: kind.title,
                    subtitle: "Open \(kind.title) provider",
                    systemImage: "rectangle.split.3x1",
                    token: "@Providers:\(kind.rawValue)"
                )
            }
            return filtered(rows)

        case .program:
            var rows: [AgentMentionItem] = []
            let prog = model.currentProgramName.isEmpty ? "(no program)" : model.currentProgramName
            rows.append(AgentMentionItem(
                id: "program.current",
                title: prog,
                subtitle: model.projectPath.isEmpty ? "Current program" : model.projectPath,
                systemImage: "doc.text",
                token: "@Program"
            ))
            if let sel = model.selectedFunction {
                rows.append(AgentMentionItem(
                    id: "selection.fn",
                    title: sel.name,
                    subtitle: "Selection · \(sel.address)",
                    systemImage: "scope",
                    token: "@Selection"
                ))
            } else {
                rows.append(AgentMentionItem(
                    id: "selection.none",
                    title: "Selection",
                    subtitle: "No function selected",
                    systemImage: "scope",
                    token: "@Selection"
                ))
            }
            if !model.projectPath.isEmpty {
                rows.append(AgentMentionItem(
                    id: "project.path",
                    title: URL(fileURLWithPath: model.projectPath).lastPathComponent,
                    subtitle: "Project · \(model.projectPath)",
                    systemImage: "folder",
                    token: "@Program"
                ))
            }
            return filtered(rows)

        case .classes:
            let objc = model.objcClassRows.prefix(80).map { name in
                AgentMentionItem(
                    id: "objc.\(name)",
                    title: name,
                    subtitle: "ObjC class",
                    systemImage: "c.circle",
                    token: "@Classes:\(sanitizeToken(name))"
                )
            }
            let swift = model.swiftClassRows
                .filter { !$0.hasPrefix("(") }
                .prefix(80)
                .map { name in
                    AgentMentionItem(
                        id: "swift.\(name)",
                        title: name,
                        subtitle: "Swift type",
                        systemImage: "s.circle",
                        token: "@Classes:\(sanitizeToken(name))"
                    )
                }
            return filtered(Array(objc) + Array(swift))

        case .pastChats:
            var rows: [AgentMentionItem] = []
            // Recent saved sessions (this project first, then other recent projects).
            let sessions = model.agentHistoryThisProject + model.agentHistoryRecent.filter { meta in
                !model.agentHistoryThisProject.contains(where: { $0.id == meta.id })
            }
            for meta in sessions.prefix(16) {
                let open = meta.id == model.agentSessionId ? " · open" : ""
                rows.append(AgentMentionItem(
                    id: "session.\(meta.id.uuidString)",
                    title: "\(meta.title)\(open)",
                    subtitle: "\(meta.projectDisplayName) · \(meta.preview)",
                    systemImage: "clock.arrow.circlepath",
                    token: "@PastChats:Session:\(meta.id.uuidString)"
                ))
            }
            // Live transcript turns in the current conversation.
            let turns = model.agentMessages.enumerated().compactMap { idx, msg -> AgentMentionItem? in
                let preview = msg.text
                    .split(separator: "\n", maxSplits: 1)
                    .first
                    .map(String.init) ?? msg.text
                let clipped = String(preview.prefix(72))
                guard !clipped.isEmpty else { return nil }
                return AgentMentionItem(
                    id: "chat.\(msg.id.uuidString)",
                    title: "\(msg.role == .user ? "You" : "Agent") · #\(idx + 1)",
                    subtitle: clipped,
                    systemImage: msg.role == .user ? "person" : "sparkles",
                    token: "@PastChats:\(idx + 1)"
                )
            }.reversed()
            rows.append(contentsOf: turns)
            return filtered(rows)

        case .docs:
            let topics: [(String, String, String)] = [
                ("re-playbook", "Full RE playbook", "Import → analyze → decompile → rename"),
                ("jspace", "JSpace / RAG", "Index + discover before deep tool use"),
                ("dsc", "dyld shared cache", "Open DSC / import frameworks"),
                ("apple", "Apple / ObjC / Swift", "Malimite-style Apple RE"),
                ("mcp", "MCP / GuiControl", "Ports 8089 / 8091 / 8092"),
                ("ui", "UI navigation", "Modules, Agent, CodeBrowser toolbar"),
                ("auton", "Autonomous RE", "Budgeted rename/comment playbook"),
            ]
            let rows = topics.map { id, title, sub in
                AgentMentionItem(
                    id: "docs.\(id)",
                    title: title,
                    subtitle: sub,
                    systemImage: "book",
                    token: "@Docs:\(id)"
                )
            }
            return filtered(rows)
        }
    }

    /// Expand `@…` tokens in user text into an LLM context appendix (display text unchanged).
    @MainActor
    static func expandContext(in text: String, model: AppModel) -> String {
        let ns = text as NSString
        let matches = tokenRegex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return "" }

        var blocks: [String] = []
        var seen = Set<String>()
        for match in matches {
            let token = ns.substring(with: match.range)
            guard seen.insert(token).inserted else { continue }
            if let block = contextBlock(for: token, model: model) {
                blocks.append(block)
            }
        }
        guard !blocks.isEmpty else { return "" }
        return "## Mentions\n" + blocks.joined(separator: "\n\n")
    }

    @MainActor
    static func contextBlock(for token: String, model: AppModel) -> String? {
        if token == "@Selection" {
            if let sel = model.selectedFunction {
                let decomp = String(model.decompiledText.prefix(2000))
                return """
                ### Selection
                function=\(sel.name) address=\(sel.address)
                decompile_preview:
                \(decomp.isEmpty ? "(empty — decompile first)" : decomp)
                """
            }
            return "### Selection\n(no function selected)"
        }
        if token == "@Program" {
            return """
            ### Program
            name=\(model.currentProgramName.isEmpty ? "(none)" : model.currentProgramName)
            project=\(model.projectPath.isEmpty ? "(none)" : model.projectPath)
            functions=\(model.functions.count)
            """
        }

        guard token.hasPrefix("@"),
              let colon = token.firstIndex(of: ":")
        else { return nil }
        let cat = String(token[token.index(after: token.startIndex) ..< colon])
        let value = String(token[token.index(after: colon)...])

        switch cat {
        case "Functions":
            let fn = model.functions.first {
                sanitizeToken($0.name) == value || $0.name == value
            }
            if let fn {
                return "### Function \(fn.name)\naddress=\(fn.address)\n(select + decompile for body)"
            }
            return "### Function \(value)\n(not in current function list — fetch_functions may help)"

        case "Providers":
            let title = ProviderKind(rawValue: value)?.title ?? value
            return "### Provider\nOpen / focus: \(title) (`\(value)`). Prefer gui_navigate / gui_action."

        case "Classes":
            return "### Class \(value)\nUse classes providers / decompile methods on this type."

        case "PastChats":
            if value.hasPrefix("Session:") {
                let raw = String(value.dropFirst("Session:".count))
                guard let id = UUID(uuidString: raw),
                      let session = AgentChatStore.loadSession(id)
                else {
                    return "### Past session\n(not found: \(raw))"
                }
                let turns = (session.archivedMessages + session.messages)
                    .suffix(8)
                    .map { "\($0.role): \(String($0.text.prefix(400)))" }
                    .joined(separator: "\n\n")
                return """
                ### Past session — \(session.title)
                project=\(session.projectPath.isEmpty ? "(none)" : session.projectPath)
                program=\(session.programName.isEmpty ? "(none)" : session.programName)
                updated=\(session.updatedAt.formatted())

                \(session.summary.isEmpty ? "" : "Summary:\n\(String(session.summary.prefix(1200)))\n")
                Recent turns:
                \(turns.isEmpty ? "(empty)" : String(turns.prefix(3500)))
                """
            }
            guard let idx = Int(value), idx >= 1, idx <= model.agentMessages.count else {
                return "### Past chat #\(value)\n(not found)"
            }
            let msg = model.agentMessages[idx - 1]
            return """
            ### Past chat #\(idx) (\(msg.role.rawValue))
            \(String(msg.text.prefix(1500)))
            """

        case "Docs":
            return docsBlock(id: value)

        default:
            return "### Mention \(token)"
        }
    }

    private static func docsBlock(id: String) -> String {
        switch id {
        case "re-playbook":
            return """
            ### Docs · Full RE playbook
            1) Project + import 2) auto_analyze 3) orient (entry/strings/imports) \
            4) rag_index 5) discover 6) decompile + xrefs 7) rename/comment \
            8) Apple/DSC if needed 9) autonomous_re to scale 10) verify
            """
        case "jspace":
            return "### Docs · JSpace\nIndex with rag_index; discovery packs orient before tools. Re-index after renames."
        case "dsc":
            return "### Docs · DSC\nOpen dyld cache → import framework image → analyze → classes/symbols → decompile."
        case "apple":
            return "### Docs · Apple RE\nObjC/Swift naming, Malimite app-bundle path, SwiftUI is ABI+witnesses (no separate decompiler)."
        case "mcp":
            return "### Docs · MCP\nAnalysis :8089 · GuiControl :8091 · Vibe/RAG :8092. In-app Agent already wraps these as tools."
        case "ui":
            return "### Docs · UI\nModules sidebar (left) toggles providers; Agent (right) is this chat; CodeBrowser toolbar has listing mnemonics."
        case "auton":
            return "### Docs · Autonomous RE\nBudgeted playbook over interesting functions — renames + comments; review pending edits."
        default:
            return "### Docs · \(id)"
        }
    }

    nonisolated static func sanitizeToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let mapped = trimmed.map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "." || ch == "-" || ch == ":" {
                return ch
            }
            return "_"
        }
        let s = String(mapped)
        return s.isEmpty ? "item" : s
    }

    /// Locate an active `@query` at `utf16Offset` (usually caret) for picker filtering.
    nonisolated static func activeMention(in text: String, utf16Offset: Int) -> (replaceStart: Int, query: String)? {
        let ns = text as NSString
        let caret = max(0, min(utf16Offset, ns.length))
        guard caret > 0 else { return nil }
        // Walk left for `@` that starts a mention (whitespace or start before it).
        var i = caret - 1
        while i >= 0 {
            let unit = ns.substring(with: NSRange(location: i, length: 1))
            if unit == "@" {
                let boundaryOK: Bool
                if i == 0 {
                    boundaryOK = true
                } else {
                    let prev = ns.substring(with: NSRange(location: i - 1, length: 1))
                    boundaryOK = prev.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
                }
                guard boundaryOK else { return nil }
                let queryRange = NSRange(location: i + 1, length: caret - (i + 1))
                let query = ns.substring(with: queryRange)
                if query.contains(" ") { return nil }
                return (i, query)
            }
            if unit.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                return nil
            }
            i -= 1
        }
        return nil
    }
}
