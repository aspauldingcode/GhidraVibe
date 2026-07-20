import SwiftUI

/// Official Liquid Glass adoption helpers (macOS Tahoe 26+).
/// See docs/macos-liquid-glass.md — glass on navigation chrome only; never on listing/decompiler.
enum LiquidGlass {
    /// Groups sibling glass controls so they morph/blend (Apple `GlassEffectContainer`).
    struct Bar<Content: View>: View {
        var spacing: CGFloat = 8
        @ViewBuilder var content: () -> Content

        var body: some View {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        }
    }
}

extension View {
    /// Interactive glass chip for status / MCP pills (not for monospaced content panes).
    func vibeGlassChip() -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular.interactive(), in: .capsule)
    }

    /// Soft glass plate behind a navigation strip (toolbar / status).
    func vibeGlassBarBackground() -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

/// Icon toolbar control using system `.glass` button style.
/// Hover tip comes from a11y catalog hint when present, else `label`.
struct GlassToolbarButton: View {
    let id: String
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        let tip = A11yCatalog.hoverTip(for: id, fallback: label)
        let e = A11yCatalog.entry(id)
        return Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.glass)
        .help(tip)
        .accessibilityIdentifier(id)
        .accessibilityLabel(e.label == id ? label : e.label)
        .accessibilityHint(tip)
        .accessibilityAddTraits(.isButton)
        .labelStyle(.iconOnly)
    }
}

/// Glass letter mnemonic (Listing I/D/U/L/F/V/B) — Liquid Glass text button.
struct GlassMnemonicButton: View {
    let id: String
    let letter: String
    let label: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        let tip = A11yCatalog.hoverTip(for: id, fallback: label)
        return Button(action: action) {
            Text(letter)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(minWidth: 18, minHeight: 18)
        }
        .buttonStyle(.glass)
        .disabled(!enabled)
        .help(tip)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
        .accessibilityHint(tip)
        .accessibilityAddTraits(.isButton)
    }
}

/// Selected tab → `.glassProminent`; idle → `.glass`.
struct GlassTabStyle: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}
