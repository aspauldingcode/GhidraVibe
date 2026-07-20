import AppKit
import SwiftUI

/// Floating undocked provider window (stock DockingWindowManager float stand-in).
struct FloatingProviderRoot: View {
    @Environment(AppModel.self) private var model
    let kind: ProviderKind

    var body: some View {
        VStack(spacing: 0) {
            ProviderView(kind: kind)
            Divider()
            HStack {
                Button("Dock Back") {
                    model.reattachProvider(kind)
                }
                .buttonStyle(.glass)
                .a11yCatalog("ghidra.vibe.dock.float.reattach")
                .help("Reattach \(kind.title) to its home dock region")
                Spacer()
                Button("Close") {
                    model.closeProvider(kind)
                }
                .buttonStyle(.borderless)
                .a11yCatalog("ghidra.vibe.dock.float.close")
            }
            .padding(8)
        }
        .frame(minWidth: 360, minHeight: 280)
        .navigationTitle(kind.title)
    }
}

/// Opens / closes SwiftUI WindowGroup scenes for floating providers.
@MainActor
enum FloatingProviderRouter {
    static func open(_ kind: ProviderKind, openWindow: OpenWindowAction) {
        openWindow(id: "ghidra.vibe.floating.provider", value: kind.rawValue)
    }
}
