import AppKit
import SwiftUI

/// Stock-parity startup splash in its **own** undecorated window.
/// Never shares an NSWindow with Project Window — finish opens main, then dismisses this scene.
struct SplashView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.vibeTheme) private var themes
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var statusIndex = 0
    @State private var progress: Double = 0.08
    @State private var finished = false

    private let phases = [
        "Initializing…",
        "Loading configuration…",
        "Creating front end tool…",
        "Preparing workspace…",
        "Starting GuiControl…",
        "GhidraVibe ready",
    ]

    private var licenseBlurb: String {
        "Licensed under the Apache License, Version 2.0. "
            + "Software is provided on an \"AS IS\" BASIS, WITHOUT WARRANTIES OR CONDITIONS "
            + "OF ANY KIND, either express or implied."
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Spacer(minLength: 8)

                dragon
                    .padding(.top, 2)

                Text("GHIDRA")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                themes.theme.vibeWarning,
                                themes.theme.vibeAccent,
                                themes.theme.vibeError,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .a11yCatalog("ghidra.vibe.splash.title")

                VStack(spacing: 2) {
                    Text("Version 12.1.2")
                    Text("Build NIX · GhidraVibe native")
                    Text(javaVersionLine)
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.vibeSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .a11yCatalog("ghidra.vibe.splash.version")

                Text(licenseBlurb)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.vibeMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 2)
                    .layoutPriority(1)
                    .a11yCatalog("ghidra.vibe.splash.license")

                Spacer(minLength: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(themes.theme.vibeWindow)

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(themes.theme.vibeAccent)
                    .controlSize(.small)
                Text(phases[min(statusIndex, phases.count - 1)])
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(themes.theme.vibeForeground)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .a11yCatalog("ghidra.vibe.splash.status")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(themes.theme.vibeControl)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(themes.theme.vibeSeparator)
                    .frame(height: 1)
            }
        }
        .frame(width: WindowChrome.splashSize.width, height: WindowChrome.splashSize.height)
        .background(themes.theme.vibeWindow)
        .clipShape(Rectangle())
        .overlay {
            Rectangle()
                .strokeBorder(themes.theme.vibeSeparator, lineWidth: 1)
        }
        .overlay {
            SplashWindowDragSurface()
        }
        .a11yContainerCatalog("ghidra.vibe.splash")
        .vibeSplashWindowChrome()
        .task { await runSplash() }
        .onChange(of: model.toolMode) { _, mode in
            // Backup: if mode advanced but the splash scene is still up, tear it down.
            if mode != .splash {
                finishAndDismissSplash(openMain: false)
            }
        }
    }

    private var dragon: some View {
        Group {
            if let img = NSImage(named: "AppIcon") ?? loadBundledIcon() {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 120, height: 120)
            } else {
                Image(systemName: "flame.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.vibeWarning)
                    .frame(width: 120, height: 120)
            }
        }
        .accessibilityLabel("Ghidra dragon")
    }

    private var javaVersionLine: String {
        if let v = ProcessInfo.processInfo.environment["JAVA_HOME"] {
            return "Java: \(URL(fileURLWithPath: v).lastPathComponent)"
        }
        return "Java (Ghidra engine)"
    }

    private func loadBundledIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        if let url = Bundle.main.url(forResource: "GhidraIcon256", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }

    @MainActor
    private func runSplash() async {
        guard !finished else { return }
        for i in phases.indices {
            if Task.isCancelled {
                // Still complete startup if the view task was cancelled mid-animation.
                finishAndDismissSplash(openMain: true)
                return
            }
            statusIndex = i
            progress = Double(i + 1) / Double(phases.count)
            try? await Task.sleep(nanoseconds: 320_000_000)
        }
        finishAndDismissSplash(openMain: true)
    }

    /// Advance app mode, open Project Window, then dismiss splash.
    /// Dismissal runs in an unstructured task so SwiftUI cancelling `.task` cannot leave the plate up.
    @MainActor
    private func finishAndDismissSplash(openMain: Bool) {
        guard !finished else {
            // Already advanced — still ensure the plate is gone.
            WindowChrome.closeSplashWindows()
            return
        }
        finished = true
        // Stop AppActivation from re-keying splash while we open the main window.
        WindowChrome.splashActive = false
        if model.toolMode == .splash {
            model.finishSplash()
        }
        if openMain {
            openWindow(id: WindowChrome.mainWindowID)
        }
        // Unstructured: survives cancellation of SplashView's `.task` after toolMode changes.
        Task { @MainActor in
            // One run-loop tick so the main WindowGroup can present first.
            try? await Task.sleep(nanoseconds: 16_000_000)
            dismissWindow(id: WindowChrome.splashWindowID)
            WindowChrome.closeSplashWindows()
            for win in NSApp.windows where !WindowChrome.isSplashWindow(win) && win.isVisible {
                win.makeKeyAndOrderFront(nil)
                break
            }
        }
    }
}

/// Forwards mouse-down to `NSWindow.performDrag` so the borderless splash moves.
private struct SplashWindowDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> DragSurfaceView {
        DragSurfaceView()
    }

    func updateNSView(_ nsView: DragSurfaceView, context: Context) {}

    final class DragSurfaceView: NSView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            self
        }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
