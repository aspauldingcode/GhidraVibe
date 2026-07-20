import AppKit

/// Bare `nix run` / store Mach-O launches are not LaunchServices-activated.
/// Force a normal Dock app + key window so the UI is focusable.
@MainActor
final class AppActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before windows appear — otherwise we can land as .accessory / unfocused.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        bringToFront()
        // One more beat after SwiftUI creates the WindowGroup.
        DispatchQueue.main.async { [weak self] in
            self?.bringToFront()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        for win in NSApp.windows where win.isVisible || win.isMiniaturized {
            win.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for win in NSApp.windows {
                win.makeKeyAndOrderFront(nil)
            }
        }
        bringToFront()
        return true
    }

    private func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        for win in NSApp.windows {
            if win.isMiniaturized {
                win.deminiaturize(nil)
            }
            win.makeKeyAndOrderFront(nil)
        }
    }
}
