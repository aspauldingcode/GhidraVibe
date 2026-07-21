import AppKit
import SwiftUI

/// Detached Agent chat window — traffic-light close / Cmd-W reattaches to the trailing sidebar.
/// No duplicate Dock Back / Full Screen / Close toolbar (macOS chrome already owns those).
struct FloatingAgentRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        AgentChatView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 420, minHeight: 520)
            .a11yContainerCatalog("ghidra.vibe.agent.window")
            .vibeUnifiedWindowChrome(
                restoreSize: NSSize(width: 560, height: 720),
                windowTitle: "Agent"
            )
            .background(AgentWindowCloseMonitor {
                guard !FloatingAgentRouter.suppressCloseReattach else { return }
                if model.dockLayout.agentDetached {
                    model.reattachAgentChat(showSidebar: true)
                }
            })
    }
}

/// Observes the host NSWindow's close so traffic lights reattach Agent to the sidebar.
/// Uses `willCloseNotification` so we never replace SwiftUI's window delegate.
private struct AgentWindowCloseMonitor: NSViewRepresentable {
    var onWillClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window, onWillClose: onWillClose)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onWillClose = onWillClose
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window, onWillClose: onWillClose)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        var onWillClose: (() -> Void)?
        private weak var window: NSWindow?

        func attach(to window: NSWindow?, onWillClose: @escaping () -> Void) {
            self.onWillClose = onWillClose
            guard let window, self.window !== window else { return }
            if let old = self.window {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.willCloseNotification,
                    object: old
                )
            }
            self.window = window
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(noteWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: window
            )
        }

        @objc func noteWillClose(_ note: Notification) {
            Task { @MainActor in
                onWillClose?()
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

@MainActor
enum FloatingAgentRouter {
    static let windowID = "ghidra.vibe.agent.chat"
    /// Set while culling leaked duplicates so close does not flip dock attach state.
    static var suppressCloseReattach = false

    static func isAgentWindow(_ win: NSWindow) -> Bool {
        if win.identifier?.rawValue.contains("agent.chat") == true { return true }
        return win.title == "Agent"
    }

    static func agentWindows() -> [NSWindow] {
        NSApp.windows.filter(isAgentWindow)
    }

    /// Cull extras; focus the survivor. Returns true when a window already exists.
    @discardableResult
    static func focusExisting() -> Bool {
        let existing = agentWindows()
        guard let keep = existing.first else { return false }
        if existing.count > 1 {
            suppressCloseReattach = true
            for extra in existing.dropFirst() {
                extra.close()
            }
            suppressCloseReattach = false
        }
        keep.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// At most one Agent window — never call `openWindow` when one already exists.
    static func open(openWindow: OpenWindowAction) {
        if focusExisting() { return }
        openWindow(id: windowID)
    }

    static func dismiss(dismissWindow: DismissWindowAction) {
        suppressCloseReattach = true
        for win in agentWindows() {
            win.close()
        }
        // Always ask SwiftUI to dismiss the singular Window scene too — AppKit
        // close alone can leave the scene alive after fast detach/reattach cycles.
        dismissWindow(id: windowID)
        suppressCloseReattach = false
    }

    static func focus() {
        _ = focusExisting()
    }
}
