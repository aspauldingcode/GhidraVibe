import AppKit
import SwiftUI

/// Native stand-in for stock Ghidra’s Java splash (`Creating front end tool…`).
struct SplashView: View {
    @Environment(AppModel.self) private var model
    @State private var statusIndex = 0
    @State private var progress: Double = 0.08

    private let phases = [
        "Initializing…",
        "Loading configuration…",
        "Creating front end tool…",
        "Preparing workspace…",
        "Starting GuiControl…",
        "GhidraVibe ready",
    ]

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer(minLength: 40)
                dragon
                Text("GHIDRA")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom)
                    )
                    .a11yCatalog("ghidra.vibe.splash.title")

                Divider().frame(width: 280)

                VStack(spacing: 4) {
                    Text("Version 12.1.2")
                    Text("Build NIX · GhidraVibe native")
                    Text(javaVersionLine)
                }
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .a11yCatalog("ghidra.vibe.splash.version")

                Divider().frame(width: 320)

                Text(
                    "Licensed under the Apache License, Version 2.0. Software is provided on an \"AS IS\" BASIS without warranties. Third-party components have separate licenses."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.horizontal)

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progress)
                        .tint(.orange)
                    Text(phases[min(statusIndex, phases.count - 1)])
                        .font(.caption.monospaced())
                        .a11yCatalog("ghidra.vibe.splash.status")
                }
                .frame(maxWidth: 420)
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .padding(.bottom, 28)
            }
            .padding()
        }
        .a11yContainerCatalog("ghidra.vibe.splash")
        .task { await runSplash() }
    }

    private var dragon: some View {
        Group {
            if let img = NSImage(named: "AppIcon") ?? loadBundledIcon() {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 160, height: 160)
            } else {
                Image(systemName: "flame.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityLabel("Ghidra dragon")
    }

    private var javaVersionLine: String {
        if let v = ProcessInfo.processInfo.environment["JAVA_HOME"] {
            return "Java: \(URL(fileURLWithPath: v).lastPathComponent)"
        }
        return "Java (in-process Ghidra engine)"
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
        for i in phases.indices {
            statusIndex = i
            progress = Double(i + 1) / Double(phases.count)
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        model.finishSplash()
    }
}
