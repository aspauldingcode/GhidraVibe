import AppKit
import SwiftUI

/// Stock Ghidra splash is an undecorated `JWindow` in its **own** NSWindow.
/// Project Window / tools live in a separate Tahoe unified window — never morph the splash plate.
enum WindowChrome {
    /// Stock-ish splash plate — tall enough for wrapped Apache license under the logo.
    static let splashSize = NSSize(width: 520, height: 420)
    /// Comfortable Front End / Project Window after splash (CodeBrowser grows later).
    static let frontEndSize = NSSize(width: 1000, height: 700)
    static let codeBrowserSize = NSSize(width: 1637, height: 931)

    static let splashWindowID = "ghidra.vibe.splash"
    static let mainWindowID = "ghidra.vibe.main"

    /// While true, activation may key the splash plate. Cleared as soon as startup advances.
    @MainActor
    static var splashActive = true

    /// Stock Ghidra tool window titles (FrontEnd / Tool Chest tools) — not the app bundle name.
    static func stockWindowTitle(toolMode: ToolMode, programName: String = "") -> String {
        switch toolMode {
        case .splash:
            return ""
        case .projectWindow:
            return "Project Window"
        case .codeBrowser:
            let name = programName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "CodeBrowser" : name
        case .debugger:
            return "Debugger"
        case .emulator:
            return "Emulator"
        case .versionTrackingTool:
            return "Version Tracking"
        case .workspacePicker:
            return "Select Project"
        case .welcomeHelp:
            return "Ghidra Help"
        }
    }

    @MainActor
    static func isSplashWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.borderless) && !window.styleMask.contains(.titled)
    }

    /// Hide/close every splash plate. Safe to call more than once.
    @MainActor
    static func closeSplashWindows() {
        splashActive = false
        for win in NSApp.windows where isSplashWindow(win) {
            win.orderOut(nil)
            win.close()
        }
    }

    static func applySplash(_ window: NSWindow) {
        window.styleMask = [.borderless]
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.isOpaque = true
        window.backgroundColor = ThemeStore.shared.theme.nsContent
        window.appearance = NSApp.appearance
        window.setContentSize(splashSize)
        window.minSize = splashSize
        window.maxSize = splashSize
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()
        window.level = .normal
        window.collectionBehavior = [.fullScreenAuxiliary]
    }

    /// Tahoe 26+: unified titlebar + toolbar (Liquid Glass), larger system corner radius.
    /// Only for Project Window / tools — never call this on the splash window.
    @MainActor
    static func applyMain(_ window: NSWindow, size: NSSize? = nil, title: String? = nil) {
        if isSplashWindow(window), title == nil, size == nil {
            // Defensive: never convert an active splash plate via watchdog.
            return
        }
        var mask = window.styleMask
        mask.remove(.borderless)
        mask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.styleMask = mask
        applyUnifiedToolbarTitlebar(window)
        window.isMovableByWindowBackground = false
        window.hasShadow = true
        window.isOpaque = true
        window.backgroundColor = ThemeStore.shared.theme.nsContent
        window.appearance = NSApp.appearance
        // Match SwiftUI CodeBrowser floor — dock columns compress below the old 1100pt habit.
        window.minSize = NSSize(width: 780, height: 520)
        window.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        if let title {
            window.title = title
        }
        if let size {
            let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            var f = window.frame
            f.size = frame.size
            if let screen = window.screen ?? NSScreen.main {
                f.origin.x = screen.visibleFrame.midX - f.width / 2
                f.origin.y = screen.visibleFrame.midY - f.height / 2
            }
            window.setFrame(f, display: true, animate: false)
        }
    }

    /// Shared Tahoe chrome bits for main, floating, Settings, and any auxiliary titled window.
    @MainActor
    static func applyUnifiedToolbarTitlebar(_ window: NSWindow) {
        var mask = window.styleMask
        if isSplashWindow(window) {
            return
        }
        mask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        mask.remove(.borderless)
        window.styleMask = mask
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
    }

    @MainActor
    static func applyUnifiedToAllWindows() {
        for window in NSApp.windows {
            applyUnifiedIfNeeded(window)
        }
    }

    @MainActor
    static func applyUnifiedIfNeeded(_ window: NSWindow) {
        if isSplashWindow(window) { return }
        guard window.styleMask.contains(.titled) else { return }
        applyUnifiedToolbarTitlebar(window)
    }
}

/// Splash scene only — keeps this NSWindow as a stock undecorated plate forever.
struct SplashWindowChromeHost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        WindowChrome.applySplash(window)
    }
}

/// Project Window / tool scene — Tahoe unified chrome; never splash morph.
struct WindowChromeHost: NSViewRepresentable {
    var restoreSize: NSSize
    var windowTitle: String

    final class Coordinator {
        var didApplyInitialSize = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { apply(to: view.window, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window, coordinator: context.coordinator) }
    }

    private func apply(to window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        // Never touch the splash window from the main scene host.
        if WindowChrome.isSplashWindow(window) { return }
        let needsSize = !coordinator.didApplyInitialSize
            || window.frame.width < 600
            || window.frame.height < 400
        WindowChrome.applyMain(
            window,
            size: needsSize ? restoreSize : nil,
            title: windowTitle
        )
        if window.title != windowTitle {
            window.title = windowTitle
        }
        coordinator.didApplyInitialSize = true
    }
}

/// Tahoe unified chrome for Project Window / tools / floats / Settings.
struct VibeUnifiedWindowChrome: ViewModifier {
    var restoreSize: NSSize = WindowChrome.frontEndSize
    var windowTitle: String = "Project Window"
    var shellRadius: CGFloat = VibeChrome.Radius.shell

    func body(content: Content) -> some View {
        content
            .vibeContainer(radius: shellRadius)
            .background(
                WindowChromeHost(restoreSize: restoreSize, windowTitle: windowTitle)
            )
    }
}

extension View {
    func vibeUnifiedWindowChrome(
        restoreSize: NSSize = WindowChrome.frontEndSize,
        windowTitle: String = "Project Window"
    ) -> some View {
        modifier(
            VibeUnifiedWindowChrome(restoreSize: restoreSize, windowTitle: windowTitle)
        )
    }

    func vibeSplashWindowChrome() -> some View {
        background(SplashWindowChromeHost())
    }
}

/// Keeps every titled GhidraVibe `NSWindow` on Tahoe unified chrome (Settings, floats, late-created).
@MainActor
enum WindowChromeWatchdog {
    private static var observations: [NSObjectProtocol] = []
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        let handler: (Notification) -> Void = { note in
            if let window = note.object as? NSWindow {
                WindowChrome.applyUnifiedIfNeeded(window)
            } else {
                WindowChrome.applyUnifiedToAllWindows()
            }
        }
        observations = [
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main,
                using: handler
            ),
            center.addObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: nil,
                queue: .main,
                using: handler
            ),
            center.addObserver(
                forName: NSApplication.didFinishLaunchingNotification,
                object: nil,
                queue: .main,
                using: handler
            ),
        ]
        WindowChrome.applyUnifiedToAllWindows()
    }
}
