import AppKit
import SwiftUI

/// Floating undocked provider window (stock DockingWindowManager float stand-in).
/// Uses Tahoe unified titlebar chrome; dock/close live in the native toolbar.
struct FloatingProviderRoot: View {
    @Environment(AppModel.self) private var model
    let kind: ProviderKind

    var body: some View {
        NavigationStack {
            ProviderView(kind: kind)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .vibeProviderShell(radius: VibeChrome.Radius.panel)
                .navigationTitle(kind.title)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        UnifiedToolbarButton(
                            id: "ghidra.vibe.dock.float.reattach",
                            systemImage: "rectangle.split.2x1",
                            label: "Dock Back"
                        ) {
                            model.reattachProvider(kind)
                        }
                        UnifiedToolbarButton(
                            id: "ghidra.vibe.dock.float.close",
                            systemImage: "xmark",
                            label: "Close"
                        ) {
                            model.closeProvider(kind)
                        }
                    }
                }
        }
        .frame(minWidth: 360, minHeight: 280)
        .vibeUnifiedWindowChrome(restoreSize: NSSize(width: 520, height: 420))
    }
}

/// Opens / closes SwiftUI WindowGroup scenes for floating providers.
@MainActor
enum FloatingProviderRouter {
    static func open(_ kind: ProviderKind, openWindow: OpenWindowAction) {
        openWindow(id: "ghidra.vibe.floating.provider", value: kind.rawValue)
    }
}
