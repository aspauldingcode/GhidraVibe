import SwiftUI
import TintedThemingSwift

/// Cursor-style @mention capsule.
struct AgentMentionChip: View {
    @Environment(\.vibeTheme) private var themes
    let label: String
    var systemImage: String = "at"
    var compact: Bool = false
    var action: (() -> Void)?

    var body: some View {
        let t = themes.theme
        let content = HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            Text(label)
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(t.vibeAccent)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 3)
        .background(
            Capsule(style: .continuous)
                .fill(t.vibeAccent.opacity(0.14))
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(t.vibeAccent.opacity(0.45), lineWidth: 1)
        }

        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .a11yCatalog("ghidra.vibe.agent.mention_chip")
    }

    static func symbol(for token: String) -> String {
        if token.hasPrefix("@Functions") { return "function" }
        if token.hasPrefix("@Providers") { return "rectangle.split.3x1" }
        if token.hasPrefix("@Classes") { return "square.grid.3x3" }
        if token.hasPrefix("@PastChats") { return "bubble.left.and.bubble.right" }
        if token.hasPrefix("@Docs") { return "book" }
        if token == "@Selection" { return "scope" }
        if token == "@Program" { return "doc.text" }
        return "at"
    }
}
