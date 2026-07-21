# macOS Liquid Glass (Tahoe 26 / Golden Gate 27)

GhidraVibe uses **official Apple Liquid Glass APIs**. Do not fake glass with `NSVisualEffectView`, custom backdrop filters, or pre-Tahoe blur hacks.

## Menubar (Tahoe)

Menu bar icons are **opt-in clarity**, not decoration on every row:

| Pattern | Use |
|---------|-----|
| `Button("…", systemImage:)` | File/Edit standards, Go To / nav, tool windows, Help |
| `Toggle("…", systemImage:)` | Sidebar chrome only (Modules / Agent) |
| `Toggle("Provider")` **no** symbol | Window → CodeBrowser modules — checkmark column aligns titles |

Never mix icon and non-icon rows inside the same module list (that was the Window-menu left-alignment bug). Every in-app keyboard shortcut must be declared with `.keyboardShortcut` on the matching menubar item so Tahoe draws it right-aligned.

## Requirements

| Item | Value |
|------|--------|
| OS | macOS Tahoe **26+** (continues on Golden Gate **27**) |
| Xcode | **26+** with matching macOS SDK |
| Arch | Apple silicon `arm64` native ([universal binary guide](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary)) |

## Canonical Apple docs

- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)
- [NSGlassEffectContainerView](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview)
- [NSBackgroundExtensionView](https://developer.apple.com/documentation/appkit/nsbackgroundextensionview)

## WWDC sessions

- WWDC25 [219 Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- WWDC25 [310 Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/)
- WWDC25 [323 Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
- WWDC26 [272 Use SwiftUI with AppKit and UIKit](https://developer.apple.com/videos/play/wwdc2026/272/)
- WWDC26 [289 Modernize your AppKit app](https://developer.apple.com/videos/play/wwdc2026/289/)

Sample: Apple **Landmarks** (“Building an app with Liquid Glass”).

## Implementation model (GhidraVibe)

Shared helpers live in `macos/GhidraVibe/Sources/GhidraVibe/LiquidGlass.swift`
(`LiquidGlass.Bar`, `GlassToolbarButton`, `.vibeGlassChip()`, `.vibeGlassBarBackground()`)
and `VibeChrome.swift` (spacing tokens + `ConcentricRectangle` / `containerShape` for
nested corner concentricity without moving stock control layout).

1. **Automatic (preferred):** `NavigationStack` + standard `.toolbar`, `Settings`, `NavigationSplitView` (Help) → system Liquid Glass on the navigation layer.
2. **All GhidraVibe windows (Tahoe unified chrome):** Every titled window uses `.windowToolbarStyle(.unified)` + AppKit `fullSizeContentView` / `toolbarStyle = .unified` / transparent titlebar (**larger Tahoe system corner radius**). Applied via `WindowChrome.applyMain` / `vibeUnifiedWindowChrome()` and `WindowChromeWatchdog` (main, floating providers, Settings). **Window titles are stock 1:1** (`WindowChrome.stockWindowTitle`): Project Window, CodeBrowser (or program name), Debugger, Emulator, Version Tracking — never the app bundle name as the tool label. **Splash is a separate `Window` scene** (`ghidra.vibe.splash`, borderless plate); Project Window is a different scene (`ghidra.vibe.main`, launch-suppressed until splash finishes) — never morph one NSWindow from loading → Front End. **Tool Chest is a section inside Project Window**, not its own window. Stock actions for those tools live in SwiftUI `.toolbar` via `UnifiedToolbarButton` / `UnifiedMnemonicButton` (no `.buttonStyle(.glass)` — NSToolbar supplies the glass pill). Shared slot map: `UnifiedToolbars.swift`. AX ids unchanged.

### Narrow windows (toolbar overflow)

Dense stock toolbars (especially CodeBrowser I/D/U/L/F/V/B) can clip when the window is resized smaller. On **macOS 26 / Xcode 26 SDK**, SwiftUI does **not** yet ship WWDC26 overflow APIs (`visibilityPriority`, `ToolbarOverflowMenu`).

| SDK | What to do |
|-----|------------|
| **macOS 26 (current)** | Keep related controls in `ToolbarItemGroup` glass pills. Put a trailing **More…** (`ellipsis.circle`) at `.primaryAction` that **mirrors every stock toolbar action** plus secondary chrome. Prefer a sensible window `minWidth` so primary clusters fit at default sizes. |
| **macOS 27+ SDK** | Adopt Apple’s pattern: `.visibilityPriority(.high/.automatic/.low)` on toolbar content (low overflows first), `ToolbarOverflowMenu { }` for always-in-chevron actions, and optionally `ToolbarItem(placement: .topBarPinnedTrailing)` for never-hidden trailing controls (Share / More / Agent). |

Do **not** drop stock actions from the More mirror just because they also appear on-glass — the menu is the narrow-window safety net until system overflow priority is available.
3. **Custom glass (in-content navigation chrome only):**
   - SwiftUI: `.glassEffect()`, `.buttonStyle(.glass)` / `.glassProminent`, `GlassEffectContainer`
   - In-content: Entropy/Overview header, status/MCP chip, Tool Chest icon wells, Project action row
4. **Bottom status / task monitor:** Shared `StatusBar` in `ContentRootView` (Project Window, CodeBrowser, stock tools). Use `.vibeStatusBarInset()` + concentric glass (`vibeGlassBarBackground`, floor `Radius.bar`) or opaque `.vibeStatusTaskPlate()` so corners nest under `Radius.shell` — never a square wash behind a rounded plate.
5. **Content layer:** Decompiler / listing / provider bodies stay **opaque** (no glass over monospaced panes).
6. **Rules:** Glass on navigation only; never glass-on-glass; do not redesign Linux GTK for this; test Reduce Transparency / Reduce Motion.

### SwiftUI (custom chip)

```swift
GlassEffectContainer(spacing: 8) {
    Text("MCP status")
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: .capsule)
}
```

### AppKit (custom glass)

```swift
let glass = NSGlassEffectView()
glass.contentView = label
let container = NSGlassEffectContainerView()
container.contentView = glass
```

## Forbidden

- `NSVisualEffectView` as sidebar/toolbar “frost” standing in for Liquid Glass  
  (Apple’s AppKit Tahoe guidance: remove legacy sidebar visual-effect materials — they block real glass)
- Hand-rolled `CIFilter` / `CABackdropLayer` “glass”
- Painting Swing with translucency and calling it Liquid Glass

## No Swing UI

Stock Swing CodeBrowser is **not shipped**. Native GhidraVibe *is* CodeBrowser.
Do not embed JAWT/Swing inside Liquid Glass views — the product never launches
`GhidraRun` / `DockingWindowManager`.
