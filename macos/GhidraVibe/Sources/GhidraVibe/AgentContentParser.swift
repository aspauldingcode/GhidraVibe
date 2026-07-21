import Foundation

enum AgentContentPart: Hashable, Sendable {
    case text(String)
    case code(language: String, code: String)
    case mention(token: String, label: String)
    case diagram(language: String, source: String)
    case cfgSnapshot(String)
}

enum AgentContentParser {
    struct Fence {
        var language: String
        var code: String
    }

    /// Split markdown into text / code / diagram / mention-aware runs for bubble rendering.
    static func parts(from text: String) -> [AgentContentPart] {
        var result: [AgentContentPart] = []
        let ns = text as NSString
        let pattern = #"```([^\n`]*)\n([\s\S]*?)```"#
        guard let re = try? NSRegularExpression(pattern: pattern) else {
            return splitMentions(in: text)
        }
        var cursor = 0
        let full = NSRange(location: 0, length: ns.length)
        re.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match else { return }
            let before = NSRange(location: cursor, length: max(0, match.range.location - cursor))
            if before.length > 0 {
                result.append(contentsOf: splitMentions(in: ns.substring(with: before)))
            }
            let lang = ns.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let code = ns.substring(with: match.range(at: 2))
            if lang == "dot" || lang == "graphviz" || lang == "mermaid" {
                result.append(.diagram(language: lang.isEmpty ? "dot" : lang, source: code))
            } else if lang == "cfg" {
                result.append(.cfgSnapshot(code))
            } else if lang == "plan" {
                // Plan fences stay as readable code; AgentPlan.parse handles structure.
                result.append(.code(language: "plan", code: code))
            } else {
                result.append(.code(language: lang, code: code))
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result.append(contentsOf: splitMentions(in: ns.substring(from: cursor)))
        }
        if result.isEmpty {
            return splitMentions(in: text)
        }
        return result
    }

    static func firstFence(in text: String, languages: Set<String>) -> Fence? {
        let ns = text as NSString
        let pattern = #"```([^\n`]*)\n([\s\S]*?)```"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let full = NSRange(location: 0, length: ns.length)
        for match in re.matches(in: text, options: [], range: full) {
            let lang = ns.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if languages.contains(lang) {
                return Fence(language: lang, code: ns.substring(with: match.range(at: 2)))
            }
        }
        return nil
    }

    static func splitMentions(in text: String) -> [AgentContentPart] {
        guard !text.isEmpty else { return [] }
        var result: [AgentContentPart] = []
        let ns = text as NSString
        let pattern = #"(@(?:Functions|Providers|Classes|PastChats|Docs):[^\s@]+|@(?:Selection|Program)\b)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else {
            return [.text(text)]
        }
        var cursor = 0
        let full = NSRange(location: 0, length: ns.length)
        re.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match else { return }
            let before = NSRange(location: cursor, length: max(0, match.range.location - cursor))
            if before.length > 0 {
                result.append(.text(ns.substring(with: before)))
            }
            let token = ns.substring(with: match.range)
            result.append(.mention(token: token, label: chipLabel(for: token)))
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result.append(.text(ns.substring(from: cursor)))
        }
        return result.isEmpty ? [.text(text)] : result
    }

    static func chipLabel(for token: String) -> String {
        if token == "@Program" { return "Program" }
        if token == "@Selection" { return "Selection" }
        if token.hasPrefix("@"), let colon = token.firstIndex(of: ":") {
            let cat = String(token[token.index(after: token.startIndex)..<colon])
            let val = String(token[token.index(after: colon)...])
            if cat == "PastChats", val.hasPrefix("Session:") {
                return "Chat"
            }
            return val
        }
        return token
    }
}
