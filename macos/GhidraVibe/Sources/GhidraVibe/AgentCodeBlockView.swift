import AppKit
import SwiftUI
import TintedThemingSwift

/// Labeled, syntax-highlighted fenced code block (Whisperer-style).
/// Top titlebar uses the same continuous corner radius as the outer plate;
/// wide lines scroll with a native horizontal ScrollView + green indicator thumb.
struct AgentCodeBlockView: View {
    @Environment(\.vibeTheme) private var themes
    let language: String
    let code: String

    /// Whisperer-like plate / titlebar radius (matches chat nest chrome).
    private static let cornerRadius: CGFloat = VibeChrome.Radius.nestMin

    @State private var scrollMetrics = CodeBlockScrollMetrics()

    var body: some View {
        let t = themes.theme
        let label = language.trimmingCharacters(in: .whitespacesAndNewlines)
        let highlighted = AgentSyntaxHighlighter.highlight(
            code: code,
            language: label.isEmpty ? nil : label,
            theme: t,
            fontSize: 12
        )
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label.isEmpty ? "Code" : label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.vibeSecondary)
                    .textCase(.uppercase)
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(t.vibeAccent)
                }
                .buttonStyle(.plain)
                .help("Copy code")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Top corners follow the plate radius (square titlebar was painting over them).
                UnevenRoundedRectangle(
                    topLeadingRadius: Self.cornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: Self.cornerRadius,
                    style: .continuous
                )
                .fill(t.vibeSelection)
            }

            ZStack(alignment: .bottom) {
                // Native horizontal scroll — green bar is only the Whisperer-style indicator.
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(highlighted)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .padding(.bottom, scrollMetrics.needsHorizontalIndicator ? 10 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onScrollGeometryChange(for: CodeBlockScrollMetrics.self) { geo in
                    CodeBlockScrollMetrics(
                        offsetX: geo.contentOffset.x,
                        contentWidth: geo.contentSize.width,
                        viewportWidth: geo.containerSize.width
                    )
                } action: { _, new in
                    scrollMetrics = new
                }

                if scrollMetrics.needsHorizontalIndicator {
                    WhispererHorizontalScrollIndicator(
                        metrics: scrollMetrics,
                        tint: t.vibeSuccess
                    )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                    .allowsHitTesting(false)
                }
            }
        }
        .background(t.vibeContentAlt)
        .clipShape(shape)
        .a11yCatalog("ghidra.vibe.agent.codeblock")
    }
}

private struct CodeBlockScrollMetrics: Equatable {
    var offsetX: CGFloat = 0
    var contentWidth: CGFloat = 0
    var viewportWidth: CGFloat = 0

    var needsHorizontalIndicator: Bool {
        contentWidth > viewportWidth + 1
    }

    /// Thumb width as a fraction of the track (viewport / content).
    var thumbFraction: CGFloat {
        guard contentWidth > 0 else { return 1 }
        return min(1, max(0.12, viewportWidth / contentWidth))
    }

    /// Thumb leading inset as a fraction of remaining track travel.
    var thumbTravelFraction: CGFloat {
        let travel = contentWidth - viewportWidth
        guard travel > 1 else { return 0 }
        return min(1, max(0, offsetX / travel))
    }
}

/// Thin green capsule track thumb — Whisperer-style indicator (not a second scroll surface).
private struct WhispererHorizontalScrollIndicator: View {
    var metrics: CodeBlockScrollMetrics
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let trackW = max(geo.size.width, 1)
            let thumbW = max(28, trackW * metrics.thumbFraction)
            let maxX = max(0, trackW - thumbW)
            let x = maxX * metrics.thumbTravelFraction
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(height: 3)
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.92))
                    .frame(width: thumbW, height: 3)
                    .offset(x: x)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
