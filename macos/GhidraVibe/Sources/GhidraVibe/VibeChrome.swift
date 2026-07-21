import AppKit
import SwiftUI
import TintedThemingSwift

/// Shared spacing + concentric corner radii for GhidraVibe chrome.
///
/// Concentricity follows Apple’s Liquid Glass guidance: nested surfaces share a
/// common corner center with their container (`outerRadius − padding`). Use
/// `ConcentricRectangle` + `containerShape` so insets adapt automatically.
///
/// These modifiers only change radius/padding tokens — they do not relocate
/// toolbar buttons or alter stock provider layout.
enum VibeChrome {
    /// Spacing ladder — dense chrome tokens + Apple HIG window/sheet margins (pt).
    /// HIG values follow macOS content margins (20 pt L/R/B) and related-control gaps;
    /// Tahoe/Golden Gate add concentricity on top, not different point sizes.
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 16
        /// HIG: related controls in a group (label→field, checkbox→list).
        static let related: CGFloat = 8
        /// HIG: unrelated control groups / section break.
        static let section: CGFloat = 16
        /// HIG: standard window/sheet content margin (left / right / bottom).
        static let margin: CGFloat = 20
        /// HIG: top content inset below titlebar / sheet header (no tabs).
        static let marginTop: CGFloat = 14
        /// HIG: comfortable gap above a primary content list/table.
        static let listInset: CGFloat = 12
    }

    enum Radius {
        /// Dock / tool shell — matches Tahoe’s larger window corner concentricity.
        static let shell: CGFloat = 22
        /// Provider panes, sheets, task monitor plates.
        static let panel: CGFloat = 16
        /// Liquid Glass toolbar / status plates (in-content; system toolbar uses NSToolbar glass).
        /// Also the concentric floor for bottom status / task-monitor nesting under `shell`.
        static let bar: CGFloat = 18
        /// Tool Chest icon wells.
        static let well: CGFloat = 14
        /// Nested cards / chat bubbles when concentric would resolve to 0.
        static let nestMin: CGFloat = 10
        /// Dense dock drop highlights / banners.
        static let dock: CGFloat = 10
        /// Provider chrome floor (still rounded, stock-dense).
        static let providerMin: CGFloat = 8
    }

    /// Modular provider surfaces — driven by the global Ghidra Theme (`ThemeStore`).
    enum ProviderSurface {
        private static var theme: Base16Theme { ThemeStore.shared.theme }

        /// Opaque document / list pane (Listing, trees, decompiler body).
        static var content: Color { theme.vibeContent }
        /// Title / tab strip lift over content.
        static var titleBar: Color { theme.vibeContentAlt }
        /// Extra wash so the title label doesn’t sit on the same flat fill as the body.
        static var titleBarWash: Color { theme.vibeForeground.opacity(0.06) }
        /// Selected / dragging title wash.
        static var titleBarActiveWash: Color { theme.vibeAccent.opacity(0.16) }
        /// Window / shell fill.
        static var window: Color { theme.vibeWindow }
        /// Controls / wells.
        static var control: Color { theme.vibeControl }
        /// Hairline separators.
        static var separator: Color { theme.vibeSeparator }
        /// Accent for selection / focus.
        static var accent: Color { theme.vibeAccent }
        /// Primary label color.
        static var foreground: Color { theme.vibeForeground }
        /// Secondary label color.
        static var secondary: Color { theme.vibeSecondary }
        /// Warning / busy chrome.
        static var warning: Color { theme.vibeWarning }
        /// Error chrome.
        static var error: Color { theme.vibeError }

        // AppKit mirrors for NSView canvases (graph, window chrome, highlighters).
        static var nsWindow: NSColor { theme.nsContent }
        static var nsContent: NSColor { theme.nsContent }
        static var nsControl: NSColor { theme.nsContentAlt }
        static var nsForeground: NSColor { theme.nsForeground }
        static var nsSecondary: NSColor { theme.nsBase04Color }
        static var nsSeparator: NSColor { theme.nsSeparator }
        static var nsAccent: NSColor { theme.nsAccent }
        static var nsSuccess: NSColor { theme.nsBase0BColor }
        static var nsWarning: NSColor { theme.nsBase0AColor }
        static var nsError: NSColor { theme.nsBase08Color }
        static var nsKeyword: NSColor { theme.nsBase0EColor }
        static var nsString: NSColor { theme.nsBase0BColor }
        static var nsNumber: NSColor { theme.nsBase09Color }
        static var nsComment: NSColor { theme.nsBase03Color }
    }

    /// Manual concentric nest: `max(0, outer − padding)`.
    static func nested(outer: CGFloat, padding: CGFloat) -> CGFloat {
        max(0, outer - padding)
    }

    /// Uniform concentric shape with a floor so far-from-edge corners stay soft.
    static func concentric(minimum: CGFloat = Radius.nestMin) -> ConcentricRectangle {
        ConcentricRectangle(
            corners: .concentric(minimum: .fixed(minimum)),
            isUniform: true
        )
    }

    static func rounded(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

extension View {
    /// Publish a rounded container so descendants resolve `ConcentricRectangle`.
    func vibeContainer(radius: CGFloat = VibeChrome.Radius.panel) -> some View {
        containerShape(.rect(cornerRadius: radius))
    }

    /// Clip to a concentric rectangle (inherits nearest `vibeContainer` / system shape).
    func vibeConcentricClip(minimum: CGFloat = VibeChrome.Radius.nestMin) -> some View {
        clipShape(VibeChrome.concentric(minimum: minimum))
    }

    /// Fill behind content with a concentric plate.
    func vibeConcentricFill<S: ShapeStyle>(
        _ style: S,
        minimum: CGFloat = VibeChrome.Radius.nestMin
    ) -> some View {
        background {
            VibeChrome.concentric(minimum: minimum).fill(style)
        }
    }

    /// Provider / pane shell: continuous outer radius + container shape for nested chrome.
    /// No extra padding — preserves stock control positions.
    func vibeProviderShell(radius: CGFloat = VibeChrome.Radius.panel) -> some View {
        self
            .background(VibeChrome.ProviderSurface.content, ignoresSafeAreaEdges: [])
            .clipShape(VibeChrome.rounded(radius))
            .containerShape(.rect(cornerRadius: radius))
    }

    /// Glass / material plate that nests concentrically inside the nearest container.
    func vibeConcentricGlassPlate(
        paddingH: CGFloat = VibeChrome.Space.lg,
        paddingV: CGFloat = VibeChrome.Space.sm,
        minimum: CGFloat = VibeChrome.Radius.bar
    ) -> some View {
        self
            .padding(.horizontal, paddingH)
            .padding(.vertical, paddingV)
            .glassEffect(.regular, in: VibeChrome.concentric(minimum: minimum))
    }

    /// Bottom status / task-monitor inset under the tool shell (Tahoe window corners).
    /// Publishes a concentric container so nested chips stay aligned with the plate.
    func vibeStatusBarInset() -> some View {
        self
            .padding(.horizontal, VibeChrome.Space.md)
            .padding(.vertical, VibeChrome.Space.sm)
            .vibeContainer(radius: VibeChrome.Radius.shell)
    }

    /// Opaque concentric status plate (task monitor) — not Liquid Glass.
    func vibeStatusTaskPlate(
        fill: Color = VibeChrome.ProviderSurface.window,
        wash: Color = VibeChrome.ProviderSurface.warning.opacity(0.14),
        stroke: Color = VibeChrome.ProviderSurface.warning.opacity(0.75),
        minimum: CGFloat = VibeChrome.Radius.bar
    ) -> some View {
        let shape = VibeChrome.concentric(minimum: minimum)
        return self
            .background { shape.fill(fill) }
            .background { shape.fill(wash) }
            .overlay { shape.stroke(stroke, lineWidth: 2) }
            .clipShape(shape)
            // Publish a rounded container for nested chips (ConcentricRectangle is not InsettableShape).
            .containerShape(.rect(cornerRadius: minimum))
    }

    /// Stroke a concentric highlight (dock drop targets).
    func vibeConcentricStroke(
        _ color: Color,
        lineWidth: CGFloat = 2,
        minimum: CGFloat = VibeChrome.Radius.providerMin
    ) -> some View {
        overlay {
            VibeChrome.concentric(minimum: minimum)
                .stroke(color, lineWidth: lineWidth)
        }
    }
}
