import SwiftUI
import TintedThemingSwift

/// Fuzzy picker for the global Ghidra Theme (Settings → Appearance / ⌘,).
struct Base16ThemePicker: View {
    @Environment(\.vibeTheme) private var themes
    @State private var filter = ""

    private var filtered: [Base16Theme] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = themes.availableThemes
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.lowercased().contains(q)
                || $0.author.lowercased().contains(q)
                || $0.variant.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Filter themes…", text: $filter)
                    .textFieldStyle(.roundedBorder)
                if themes.loading {
                    ProgressView().controlSize(.small)
                }
                Button("Reload") {
                    Task { await themes.refreshThemes() }
                }
                .controlSize(.small)
            }
            if !themes.loadError.isEmpty {
                Text(themes.loadError)
                    .font(.caption2)
                    .foregroundStyle(themes.theme.vibeError)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filtered, id: \.name) { theme in
                        Button {
                            themes.select(theme)
                        } label: {
                            HStack(spacing: 8) {
                                themeSwatch(theme)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(theme.name)
                                        .font(.callout.weight(themes.theme.name == theme.name ? .semibold : .regular))
                                        .foregroundStyle(themes.theme.vibeForeground)
                                    Text("\(theme.author) · \(theme.variant)")
                                        .font(.caption2)
                                        .foregroundStyle(themes.theme.vibeSecondary)
                                }
                                Spacer(minLength: 0)
                                if themes.theme.name == theme.name {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(themes.theme.vibeAccent)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 180)
        }
        .a11yCatalog("ghidra.vibe.agent.theme_picker")
        .task {
            if themes.availableThemes.count <= 2 {
                await themes.refreshThemes()
            }
        }
    }

    private func themeSwatch(_ theme: Base16Theme) -> some View {
        HStack(spacing: 1) {
            ForEach([theme.base08, theme.base0B, theme.base0D, theme.base0E], id: \.self) { hex in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(hex: hex))
                    .frame(width: 8, height: 18)
            }
        }
        .padding(2)
        .background(theme.swiftUIBase00Color)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(theme.swiftUIBase02Color, lineWidth: 1)
        }
    }
}
