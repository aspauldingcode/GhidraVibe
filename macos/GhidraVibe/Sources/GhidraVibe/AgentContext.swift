import Foundation

/// Attachment staged in the Agent composer (iMessage-style paperclip).
struct AgentAttachment: Identifiable, Hashable, Sendable {
    var id = UUID()
    var url: URL
    var displayName: String
    var byteCount: Int
    /// Inlined text for the LLM (empty for non-text / oversized).
    var textPreview: String
    var isText: Bool

    var chipLabel: String {
        if byteCount < 1024 { return "\(displayName) (\(byteCount) B)" }
        return "\(displayName) (\(byteCount / 1024) KB)"
    }
}

/// Rough token accounting + Cursor-like auto-renew (summarize) thresholds.
enum AgentContextMeter {
    /// Fraction of the window that triggers auto-summarize before the next send.
    static let autoRenewThreshold: Double = 0.75
    /// Keep this many recent transcript turns after a renew (rest live in the rolling summary).
    static let keepRecentMessages = 8
    /// Max live turns sent to the LLM each turn (plus rolling summary).
    static let maxHistoryMessages = 24

    /// Heuristic context window by model id (chars≈4 chars/token).
    static func windowTokens(forModel model: String) -> Int {
        let m = model.lowercased()
        if m.contains("1m") || m.contains("1000000") { return 1_000_000 }
        if m.contains("200k") || m.contains("200000") { return 200_000 }
        if m.contains("128k") || m.contains("128000") { return 128_000 }
        if m.contains("100k") { return 100_000 }
        if m.contains("64k") || m.contains("65536") { return 64_000 }
        if m.contains("32k") || m.contains("32768") { return 32_000 }
        if m.contains("16k") { return 16_000 }
        if m.contains("8k") || m.contains("8192") { return 8_192 }
        // Common local defaults
        if m.contains(":70b") || m.contains("70b") { return 32_000 }
        if m.contains(":32b") || m.contains("32b") { return 32_000 }
        if m.contains(":14b") || m.contains("14b") || m.contains(":13b") { return 16_000 }
        if m.contains(":7b") || m.contains("7b") || m.contains(":8b") { return 16_000 }
        if m.contains(":3b") || m.contains("3b") || m.contains(":4b") { return 8_192 }
        if m.contains("gpt-4") || m.contains("o1") || m.contains("o3") { return 128_000 }
        if m.contains("claude") { return 200_000 }
        if m.contains("gemini") { return 128_000 }
        return 16_000
    }

    /// ~4 characters per token (OpenAI-style heuristic).
    static func estimateTokens(_ text: String) -> Int {
        max(1, (text.utf8.count + 3) / 4)
    }

    static func estimateMessages(_ messages: [LocalAIChatMessage]) -> Int {
        messages.reduce(0) { partial, msg in
            var n = partial
            if let c = msg.content { n += estimateTokens(c) }
            if let calls = msg.toolCalls {
                for call in calls {
                    n += estimateTokens(call.name) + estimateTokens(call.argumentsJSON) + 8
                }
            }
            n += 4 // role overhead
            return n
        }
    }

    static func usageFraction(used: Int, window: Int) -> Double {
        guard window > 0 else { return 0 }
        return min(1, Double(used) / Double(window))
    }
}
