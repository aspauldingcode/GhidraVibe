import SwiftUI

/// Navigation chrome helpers. Content panes stay opaque Base16 fills (never glass).
/// Glass materials do not track Ghidra Theme palettes — status/tool strips use themed plates.
enum LiquidGlass {
    /// Groups sibling controls (Apple `GlassEffectContainer` spacing).
    struct Bar<Content: View>: View {
        var spacing: CGFloat = VibeChrome.Space.md
        @ViewBuilder var content: () -> Content

        var body: some View {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        }
    }
}

extension View {
    /// Themed chip for status / MCP pills (Base16 control fill — not system glass).
    func vibeGlassChip() -> some View {
        self
            .foregroundStyle(Color.vibeForeground)
            .padding(.horizontal, VibeChrome.Space.lg)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.vibeControl)
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.vibeSeparator, lineWidth: 1)
            }
    }

    /// Themed plate behind a navigation / status strip (tracks Ghidra Theme).
    func vibeGlassBarBackground() -> some View {
        self
            .foregroundStyle(Color.vibeForeground)
            .padding(.horizontal, VibeChrome.Space.lg)
            .padding(.vertical, VibeChrome.Space.sm)
            .background {
                VibeChrome.concentric(minimum: VibeChrome.Radius.bar)
                    .fill(Color.vibeControl)
            }
            .overlay {
                VibeChrome.concentric(minimum: VibeChrome.Radius.bar)
                    .stroke(Color.vibeSeparator.opacity(0.7), lineWidth: 1)
            }
    }
}

/// Icon toolbar control — bordered themed button (in-content strips).
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
                .foregroundStyle(Color.vibeForeground)
        }
        .buttonStyle(.bordered)
        .tint(Color.vibeAccent)
        .help(tip)
        .accessibilityIdentifier(id)
        .accessibilityLabel(e.label == id ? label : e.label)
        .accessibilityHint(tip)
        .accessibilityAddTraits(.isButton)
        .labelStyle(.iconOnly)
    }
}

/// System unified toolbar control — no in-content plate (NSToolbar supplies chrome on Tahoe).
/// Use inside `.toolbar { }` only; in-content strips keep `GlassToolbarButton`.
struct UnifiedToolbarButton: View {
    let id: String
    let systemImage: String
    let label: String
    var helpTip: String? = nil
    let action: () -> Void

    var body: some View {
        let tip = helpTip ?? A11yCatalog.hoverTip(for: id, fallback: label)
        let e = A11yCatalog.entry(id)
        let title = e.label == id ? label : e.label
        return Button(action: action) {
            Image(systemName: systemImage)
        }
        .help(tip)
        .accessibilityIdentifier(id)
        .accessibilityLabel(title)
        .accessibilityHint(tip)
        .accessibilityAddTraits(.isButton)
    }
}

/// Listing mnemonic (I/D/U/L/F/V/B) — themed bordered text button (in-content).
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
                .foregroundStyle(Color.vibeForeground)
                .frame(minWidth: 18, minHeight: 18)
        }
        .buttonStyle(.bordered)
        .tint(Color.vibeAccent)
        .disabled(!enabled)
        .help(tip)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
        .accessibilityHint(tip)
        .accessibilityAddTraits(.isButton)
    }
}

/// Listing mnemonic (I/D/U/L/F/V/B) for the unified toolbar.
struct UnifiedMnemonicButton: View {
    let id: String
    let letter: String
    let label: String
    var enabled: Bool = true
    let action: () -> Void

    private var systemImage: String {
        "\(letter.lowercased()).circle"
    }

    var body: some View {
        let tip = A11yCatalog.hoverTip(for: id, fallback: "\(letter) — \(label)")
        UnifiedToolbarButton(
            id: id,
            systemImage: systemImage,
            label: label,
            helpTip: tip
        ) {
            guard enabled else { return }
            action()
        }
        .disabled(!enabled)
    }
}

/// Selected tab → prominent tinted; idle → bordered.
struct GlassTabStyle: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent).tint(Color.vibeAccent)
        } else {
            content.buttonStyle(.bordered).tint(Color.vibeAccent)
        }
    }
}
