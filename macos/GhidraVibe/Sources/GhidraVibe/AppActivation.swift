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
        WindowChromeWatchdog.start()
        bringToFront()
        DispatchQueue.main.async { [weak self] in
            self?.bringToFront()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        bringToFront()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Prefer reopening Project Window, not inventing a second splash.
            for win in NSApp.windows where !WindowChrome.isSplashWindow(win) {
                win.makeKeyAndOrderFront(nil)
            }
        }
        bringToFront()
        return true
    }

    private func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        // While splash is up, key only that plate — do not promote a half-ready main window.
        // After startup advances, never re-front a leftover splash (dismiss can race).
        if WindowChrome.splashActive,
           let splash = NSApp.windows.first(where: { WindowChrome.isSplashWindow($0) && $0.isVisible })
        {
            if splash.isMiniaturized { splash.deminiaturize(nil) }
            splash.makeKeyAndOrderFront(nil)
            return
        }
        for win in NSApp.windows {
            if WindowChrome.isSplashWindow(win) { continue }
            if win.isMiniaturized {
                win.deminiaturize(nil)
            }
            win.makeKeyAndOrderFront(nil)
        }
    }
}
