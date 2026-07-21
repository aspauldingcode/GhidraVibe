import SwiftUI
import Textual
import TintedThemingSwift

/// Rich agent message body: Textual markdown + mention chips + code/diagram parts.
/// Intrinsic width (hugs content) so chat bubbles can trim the opposite edge.
struct AgentMarkdownView: View {
    @Environment(\.vibeTheme) private var themes
    @Environment(AppModel.self) private var model
    let text: String
    var isUser: Bool = false
    /// Soft wrap cap — must match `AgentBubble` max width.
    var maxContentWidth: CGFloat = 420

    var body: some View {
        let t = themes.theme
        let parts = AgentContentParser.parts(from: text)
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .text(let s):
                    if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        markdownBlock(s, theme: t)
                    }
                case .mention(let token, let label):
                    AgentMentionChip(
                        label: label,
                        systemImage: AgentMentionChip.symbol(for: token)
                    ) {
                        handleMentionTap(token)
                    }
                case .code(let language, let code):
                    AgentCodeBlockView(language: language, code: code)
                        .frame(maxWidth: maxContentWidth, alignment: .leading)
                case .diagram(let language, let source):
                    AgentDiagramView(language: language, source: source)
                        .frame(maxWidth: maxContentWidth, alignment: .leading)
                case .cfgSnapshot(let raw):
                    AgentCFGEmbedView(raw: raw)
                        .frame(maxWidth: maxContentWidth, alignment: .leading)
                }
            }
        }
        // Cap wrap width but do NOT expand to infinity — that kills opposite-edge trim.
        .frame(maxWidth: maxContentWidth, alignment: isUser ? .trailing : .leading)
    }

    @ViewBuilder
    private func markdownBlock(_ s: String, theme: Base16Theme) -> some View {
        let inline = InlineStyle()
            .code(
                .monospaced,
                .fontScale(0.95),
                .backgroundColor(theme.swiftUIBase02Color.opacity(0.45)),
                .foregroundColor(theme.swiftUIBase05Color)
            )
            .emphasis(.italic)
            .strong(.bold)
            .link(.foregroundColor(theme.swiftUILinkColor))

        StructuredText(markdown: s)
            .font(.body)
            .foregroundStyle(theme.vibeForeground)
            .tint(theme.vibeAccent)
            .textual.inlineStyle(inline)
            .textual.headingStyle(AgentHeadingStyle())
            .textual.listItemStyle(.default(markerSpacing: .fontScaled(0.35)))
            .multilineTextAlignment(isUser ? .trailing : .leading)
            // Textual's selection overlay (not SwiftUI `.textSelection`) — enables drag-select,
            // context Copy/Share, and ⌘C via the first-responder `copy:` action.
            .textual.textSelection(.enabled)
            // Hug short lines; wrap when the bubble's max width is proposed.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: maxContentWidth, alignment: isUser ? .trailing : .leading)
    }

    private func handleMentionTap(_ token: String) {
        if token.hasPrefix("@Providers:"),
           let kind = ProviderKind(rawValue: String(token.dropFirst("@Providers:".count)))
        {
            model.showProvider(kind)
        } else if token.hasPrefix("@Functions:") {
            let name = String(token.dropFirst("@Functions:".count))
            model.selectFunction(name: name, address: nil, id: nil)
            model.decompileSelected()
        }
    }
}

struct AgentHeadingStyle: StructuredText.HeadingStyle {
    private static let scales: [CGFloat] = [1.35, 1.22, 1.12, 1.05, 1.0, 1.0]

    func makeBody(configuration: Configuration) -> some View {
        let level = min(max(configuration.headingLevel, 1), 6)
        configuration.label
            .textual.fontScale(Self.scales[level - 1])
            .textual.blockSpacing(.fontScaled(top: 0.7, bottom: 0.3))
            .fontWeight(.semibold)
    }
}

/// Compact read-only CFG snapshot (live graph when available, else fence text).
struct AgentCFGEmbedView: View {
    @Environment(\.vibeTheme) private var themes
    @Environment(AppModel.self) private var model
    let raw: String

    var body: some View {
        let t = themes.theme
        let graph = model.functionGraphModel
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CFG")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.vibeSecondary)
                if !graph.function.isEmpty {
                    Text(graph.function)
                        .font(.caption2)
                        .foregroundStyle(t.vibeMuted)
                        .lineLimit(1)
                }
                Spacer()
                Button("Open Graph") {
                    model.showProvider(.functionGraph)
                    model.refreshFunctionGraph()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            if !graph.nodes.isEmpty {
                FunctionGraphCanvas(
                    model: graph,
                    selectedId: nil,
                    onSelectAddress: { addr in
                        model.selectFunction(name: nil, address: addr, id: nil)
                    }
                )
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Text(
                    raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "No graph loaded — select a function and Refresh Graph, or retry."
                        : String(raw.prefix(400))
                )
                .font(.caption.monospaced())
                .foregroundStyle(t.vibeForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Retry load") {
                    model.refreshFunctionGraph()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(t.vibeContentAlt)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(t.vibeSelection, lineWidth: 1)
        }
        .a11yCatalog("ghidra.vibe.agent.cfg_embed")
    }
}
