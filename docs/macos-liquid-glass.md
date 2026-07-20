# macOS Liquid Glass (Tahoe 26 / Golden Gate 27)

GhidraVibe uses **official Apple Liquid Glass APIs**. Do not fake glass with `NSVisualEffectView`, custom backdrop filters, or pre-Tahoe blur hacks.

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
(`LiquidGlass.Bar`, `GlassToolbarButton`, `.vibeGlassChip()`, `.vibeGlassBarBackground()`).

1. **Automatic (preferred):** `NavigationStack` + standard `.toolbar`, `Settings`, `NavigationSplitView` (Help) → system Liquid Glass on the navigation layer.
2. **Custom glass (navigation chrome):**
   - SwiftUI: `.glassEffect()`, `.buttonStyle(.glass)` / `.glassProminent`, `GlassEffectContainer`
   - Toolbars: Project Window VC bar, CodeBrowser tool strip, status/MCP chip, Tool Chest icons
3. **Content layer:** Decompiler / listing / provider bodies stay **opaque** (no glass over monospaced panes).
4. **Rules:** Glass on navigation only; never glass-on-glass; test Reduce Transparency / Reduce Motion.

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
