import AppKit
import SwiftUI
import TintedThemingSwift

/// Global Ghidra Theme for the entire GhidraVibe GUI (Settings → Appearance / ⌘,).
/// Backed by Base16 palettes from TintedThemingSwift.
/// Default Light / Default Dark use Apple platform chrome (system backgrounds + accent).
@Observable
final class ThemeStore: @unchecked Sendable {
    static let shared = ThemeStore()
    /// User-facing preference key (Ghidra Theme name).
    static let defaultsKey = "ghidra.vibe.theme.ghidra"
    /// Legacy key from Agent-era theming — still read for migration.
    static let legacyDefaultsKey = "ghidra.vibe.theme.base16"
    /// When true, Default Light/Dark tracks macOS appearance automatically.
    static let followSystemKey = "ghidra.vibe.theme.followSystem"

    var theme: Base16Theme = .defaultMatchingSystemAppearance()
    var availableThemes: [Base16Theme] = []
    var loading = false
    var loadError: String = ""
    /// Bumps when the active theme changes so shell views can observe redraws.
    var revision: UInt64 = 0
    /// Follow macOS light/dark with Default Light / Default Dark.
    var followSystemAppearance: Bool = true

    /// Display name of the active Ghidra Theme.
    var ghidraThemeName: String { theme.name }

    private var appearanceObserver: NSObjectProtocol?

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey)
            ?? UserDefaults.standard.string(forKey: Self.legacyDefaultsKey)
        let followFlag = UserDefaults.standard.object(forKey: Self.followSystemKey) as? Bool

        if let name = saved, !name.isEmpty,
           let cached = TintedThemesLoader.shared.getCachedThemes().first(where: {
               $0.name.caseInsensitiveCompare(name) == .orderedSame
           })
        {
            theme = cached
            // Explicit non-default theme → stop following system unless user opted in.
            followSystemAppearance = followFlag ?? cached.isDefaultPlatformTheme
        } else if let name = saved, name == "Default Dark" || name == "Default Light" {
            theme = name == "Default Light" ? .defaultLight : .defaultDark
            followSystemAppearance = followFlag ?? true
            if followSystemAppearance {
                theme = .defaultMatchingSystemAppearance()
            }
        } else {
            // Fresh install: Apple platform default matching system appearance.
            theme = .defaultMatchingSystemAppearance()
            followSystemAppearance = followFlag ?? true
        }
        availableThemes = TintedThemesLoader.shared.getCachedThemes()
        if availableThemes.isEmpty {
            availableThemes = [.defaultDark, .defaultLight]
        }
        applyToApp()
        startAppearanceObserver()
    }

    deinit {
        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
    }

    @MainActor
    func select(_ theme: Base16Theme) {
        if theme.isDefaultPlatformTheme {
            // Default Light/Dark = Apple platform chrome; keep matching the system.
            followSystemAppearance = true
            self.theme = .defaultMatchingSystemAppearance()
        } else {
            followSystemAppearance = false
            self.theme = theme
        }
        UserDefaults.standard.set(followSystemAppearance, forKey: Self.followSystemKey)
        UserDefaults.standard.set(self.theme.name, forKey: Self.defaultsKey)
        UserDefaults.standard.set(self.theme.name, forKey: Self.legacyDefaultsKey)
        revision &+= 1
        applyToApp()
    }

    @MainActor
    func select(named name: String) {
        if let t = availableThemes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            select(t)
        } else if name.caseInsensitiveCompare("Default Dark") == .orderedSame {
            select(.defaultDark)
        } else if name.caseInsensitiveCompare("Default Light") == .orderedSame {
            select(.defaultLight)
        }
    }

    @MainActor
    func setFollowSystemAppearance(_ follow: Bool) {
        followSystemAppearance = follow
        UserDefaults.standard.set(follow, forKey: Self.followSystemKey)
        if follow {
            let matched = Base16Theme.defaultMatchingSystemAppearance()
            theme = matched
            UserDefaults.standard.set(matched.name, forKey: Self.defaultsKey)
            UserDefaults.standard.set(matched.name, forKey: Self.legacyDefaultsKey)
            revision &+= 1
            applyToApp()
        }
    }

    @MainActor
    func refreshThemes() async {
        loading = true
        loadError = ""
        defer { loading = false }
        do {
            let themes = try await TintedThemesLoader.shared.loadAllBase16Themes()
            // Ensure Apple platform defaults stay at the top of the picker.
            var sorted = themes.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            sorted.removeAll { $0.isDefaultPlatformTheme }
            availableThemes = [.defaultLight, .defaultDark] + sorted
            if followSystemAppearance {
                theme = .defaultMatchingSystemAppearance()
                applyToApp()
            } else if let name = UserDefaults.standard.string(forKey: Self.defaultsKey)
                ?? UserDefaults.standard.string(forKey: Self.legacyDefaultsKey),
               let match = availableThemes.first(where: {
                   $0.name.caseInsensitiveCompare(name) == .orderedSame
               })
            {
                theme = match
                applyToApp()
            }
        } catch {
            loadError = error.localizedDescription
            if availableThemes.isEmpty {
                availableThemes = [.defaultLight, .defaultDark]
            }
        }
    }

    /// Push light/dark + accent into AppKit so the whole GUI follows Ghidra Theme.
    func applyToApp() {
        let apply: () -> Void = { [theme, followSystemAppearance] in
            if theme.usesApplePlatformChrome, followSystemAppearance {
                // Stock macOS: let AppKit resolve button/window chrome from the system appearance.
                NSApp.appearance = nil
            } else {
                let appearanceName: NSAppearance.Name = theme.isLight ? .aqua : .darkAqua
                NSApp.appearance = NSAppearance(named: appearanceName)
            }
            for window in NSApp.windows {
                window.appearance = NSApp.appearance
                // Platform defaults use live windowBackgroundColor; custom themes use palette hex.
                window.backgroundColor = theme.usesApplePlatformChrome
                    ? .windowBackgroundColor
                    : theme.nsContent
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func startAppearanceObserver() {
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.followSystemAppearance else { return }
            let matched = Base16Theme.defaultMatchingSystemAppearance()
            guard matched.name != self.theme.name || matched.variant != self.theme.variant else {
                self.applyToApp()
                self.revision &+= 1
                return
            }
            self.theme = matched
            UserDefaults.standard.set(matched.name, forKey: Self.defaultsKey)
            self.revision &+= 1
            self.applyToApp()
        }
    }
}

// MARK: - Environment

private struct ThemeStoreKey: EnvironmentKey {
    static let defaultValue: ThemeStore = ThemeStore.shared
}

extension EnvironmentValues {
    var vibeTheme: ThemeStore {
        get { self[ThemeStoreKey.self] }
        set { self[ThemeStoreKey.self] = newValue }
    }
}

extension View {
    func vibeThemed(_ store: ThemeStore = .shared) -> some View {
        environment(\.vibeTheme, store)
    }

    /// Apply the active Ghidra Theme to a window root (color scheme, tint, fill, default fg).
    func vibeGlobalTheme(_ store: ThemeStore = .shared) -> some View {
        modifier(VibeGlobalThemeModifier(store: store))
    }

    /// Opaque themed document pane (Listing, Console, trees, editors).
    func vibeDocumentPane() -> some View {
        self
            .foregroundStyle(Color.vibeForeground)
            .scrollContentBackground(.hidden)
            .background(Color.vibeContent)
            .focusEffectDisabled()
    }

    /// Themed list / outline (hide system list fill + blue focus rings).
    func vibeThemedList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .listRowBackground(Color.vibeContent)
            .foregroundStyle(Color.vibeForeground)
            .background(Color.vibeContent)
            .focusEffectDisabled()
    }

    /// Themed TextEditor / form field surface.
    func vibeThemedEditor() -> some View {
        self
            .scrollContentBackground(.hidden)
            .foregroundStyle(Color.vibeForeground)
            .background(Color.vibeContent)
            .focusEffectDisabled()
    }
}

private struct VibeGlobalThemeModifier: ViewModifier {
    @Bindable var store: ThemeStore

    func body(content: Content) -> some View {
        let t = store.theme
        // Apple platform chrome: do NOT set environment `.tint(Color.accentColor)`.
        // That painted system-blue borders on every `.bordered` button/list focus ring.
        // Custom Base16 themes still tint from base0D. Focus rings stay off either way.
        let themed = Group {
            if t.usesApplePlatformChrome {
                content
                    .environment(\.vibeTheme, store)
                    .foregroundStyle(t.vibeForeground)
                    .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
            } else {
                content
                    .environment(\.vibeTheme, store)
                    .tint(t.vibeAccent)
                    .foregroundStyle(t.vibeForeground)
                    .background(t.vibeContent.ignoresSafeArea())
            }
        }
        .focusEffectDisabled()
        .id("ghidra-theme-\(store.revision)-\(t.name)-\(store.followSystemAppearance)")
        .onAppear { store.applyToApp() }
        .onChange(of: store.revision) { _, _ in
            store.applyToApp()
        }
        // Platform defaults: do not override color scheme — stock buttons/backgrounds follow macOS.
        if t.usesApplePlatformChrome, store.followSystemAppearance {
            themed.preferredColorScheme(nil)
        } else {
            themed.preferredColorScheme(t.isLight ? .light : .dark)
        }
    }
}

/// Static Color accessors so `.foregroundStyle(Color.vibeSecondary)` tracks `ThemeStore`.
extension Color {
    static var vibeForeground: Color { ThemeStore.shared.theme.vibeForeground }
    static var vibeSecondary: Color { ThemeStore.shared.theme.vibeSecondary }
    static var vibeMuted: Color { ThemeStore.shared.theme.vibeMuted }
    /// Accent fill/label color. For Apple platform chrome this is still the system accent
    /// (used sparingly on primary CTAs) — never applied as a global control tint.
    static var vibeAccent: Color {
        let t = ThemeStore.shared.theme
        return t.usesApplePlatformChrome ? Color.accentColor : t.vibeAccent
    }
    static var vibeContent: Color {
        let t = ThemeStore.shared.theme
        return t.usesApplePlatformChrome
            ? Color(nsColor: .windowBackgroundColor)
            : t.vibeContent
    }
    static var vibeContentAlt: Color {
        let t = ThemeStore.shared.theme
        return t.usesApplePlatformChrome
            ? Color(nsColor: .controlBackgroundColor)
            : t.vibeContentAlt
    }
    static var vibeControl: Color {
        let t = ThemeStore.shared.theme
        return t.usesApplePlatformChrome
            ? Color(nsColor: .controlBackgroundColor)
            : t.vibeControl
    }
    static var vibeSelection: Color { ThemeStore.shared.theme.vibeSelection }
    static var vibeSeparator: Color {
        let t = ThemeStore.shared.theme
        return t.usesApplePlatformChrome
            ? Color(nsColor: .separatorColor)
            : t.vibeSeparator
    }
    static var vibeWarning: Color { ThemeStore.shared.theme.vibeWarning }
    static var vibeError: Color { ThemeStore.shared.theme.vibeError }
    static var vibeSuccess: Color { ThemeStore.shared.theme.vibeSuccess }
    static var vibeWindow: Color { vibeContent }
    /// Contrasting label on accent-filled controls.
    static var vibeOnAccent: Color {
        ThemeStore.shared.theme.isLight
            ? Color(nsColor: .alternateSelectedControlTextColor)
            : Color(nsColor: .alternateSelectedControlTextColor)
    }
}

// MARK: - Convenience colors

extension Base16Theme {
    var vibeContent: Color { swiftUIBase00Color }
    var vibeContentAlt: Color { swiftUIBase01Color }
    var vibeSelection: Color { swiftUIBase02Color }
    var vibeMuted: Color { swiftUIBase03Color }
    var vibeSecondary: Color { swiftUIBase04Color }
    var vibeForeground: Color { swiftUIBase05Color }
    var vibeAccent: Color { swiftUIBase0DColor }
    var vibeSuccess: Color { swiftUIBase0BColor }
    var vibeWarning: Color { swiftUIBase0AColor }
    var vibeError: Color { swiftUIBase08Color }
    var vibeKeyword: Color { swiftUIBase0EColor }
    var vibeSeparator: Color { swiftUIBase02Color.opacity(0.85) }
    var vibeWindow: Color { swiftUIBase00Color }
    var vibeControl: Color { swiftUIBase01Color }

    var nsContent: NSColor { nsBase00Color }
    var nsContentAlt: NSColor { nsBase01Color }
    var nsForeground: NSColor { nsBase05Color }
    var nsAccent: NSColor { nsBase0DColor }
    var nsSeparator: NSColor { nsBase02Color.withAlphaComponent(0.85) }
}
