import AppKit
import SwiftUI

/// Front End / tool chrome only. Splash is a separate `Window` scene — never morph here.
struct ContentRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.vibeTheme) private var themes
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    private var restoreSize: CGSize {
        switch model.toolMode {
        case .codeBrowser, .debugger, .emulator, .versionTrackingTool:
            return CGSize(
                width: WindowChrome.codeBrowserSize.width,
                height: WindowChrome.codeBrowserSize.height
            )
        default:
            return CGSize(
                width: WindowChrome.frontEndSize.width,
                height: WindowChrome.frontEndSize.height
            )
        }
    }

    /// Stock Ghidra tool title 1:1 — never the app bundle name.
    private var stockWindowTitle: String {
        let mode = model.toolMode == .splash ? .projectWindow : model.toolMode
        return WindowChrome.stockWindowTitle(
            toolMode: mode,
            programName: model.currentProgramName
        )
    }

    var body: some View {
        // Observe Ghidra Theme so ProviderSurface / chrome redraw on change.
        let _ = themes.revision
        mainChrome
            .background(themes.theme.vibeWindow)
            .vibeUnifiedWindowChrome(
                restoreSize: NSSize(width: restoreSize.width, height: restoreSize.height),
                windowTitle: stockWindowTitle
            )
            .onAppear {
                if model.dockLayout.agentDetached {
                    FloatingAgentRouter.open(openWindow: openWindow)
                } else if !FloatingAgentRouter.agentWindows().isEmpty {
                    // Leaked Agent window(s) while dock says attached — close without reattach loop.
                    FloatingAgentRouter.dismiss(dismissWindow: dismissWindow)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ghidraVibeDetachAgent)) { _ in
                FloatingAgentRouter.open(openWindow: openWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: .ghidraVibeAttachAgent)) { _ in
                FloatingAgentRouter.dismiss(dismissWindow: dismissWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: .ghidraVibeFocusAgent)) { _ in
                // Focus only — never openWindow (that was spawning hundreds of windows).
                if !FloatingAgentRouter.focusExisting() {
                    FloatingAgentRouter.open(openWindow: openWindow)
                }
            }
    }

    private var mainChrome: some View {
        @Bindable var model = model
        return NavigationStack {
            VStack(spacing: 0) {
                Group {
                    switch model.toolMode {
                    case .splash:
                        // Separate splash window owns loading; main should already be past this.
                        ProgressView("Opening…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .workspacePicker:
                        WorkspacePickerView()
                    case .welcomeHelp:
                        WelcomeHelpView()
                    case .projectWindow:
                        // Tool Chest is a section *inside* this view — not a separate window.
                        ProjectWindowView()
                    case .codeBrowser:
                        CodeBrowserDockView()
                            .a11yContainerCatalog("ghidra.vibe.codebrowser")
                    case .debugger, .emulator, .versionTrackingTool:
                        StockToolShellView(toolMode: model.toolMode)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VibeChrome.ProviderSurface.content)
                .vibeContainer(radius: VibeChrome.Radius.shell)

                if model.toolMode == .projectWindow, let sheet = model.sheetProvider {
                    Divider()
                    ProviderSheetHost(kind: sheet)
                        .frame(minHeight: 160, idealHeight: 220, maxHeight: 320)
                        .layoutPriority(0)
                        .vibeContainer(radius: VibeChrome.Radius.panel)
                }

                if model.toolMode != .splash {
                    StatusBar()
                }
            }
            .a11yContainerCatalog("ghidra.vibe.root")
            .vibeContainer(radius: VibeChrome.Radius.shell)
            .navigationTitle(stockWindowTitle)
            .toolbarBackground(.automatic, for: .windowToolbar)
            .alert("Headless", isPresented: $model.showHeadlessHelp) {
                Button("OK", role: .cancel) {}
                    .help("Dismiss headless help")
                    .a11yCatalog("ghidra.vibe.headless.ok")
            } message: {
                Text(model.headlessHelpText)
            }
            .alert("Go To", isPresented: $model.showGoToAlert) {
                TextField("Address or label", text: $model.goToDraft)
                Button("Go") { model.performGoTo() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.vibeAccent)
                    .a11yCatalog("ghidra.vibe.goto.go")
                Button("Cancel", role: .cancel) {}
                    .a11yCatalog("ghidra.vibe.goto.cancel")
            } message: {
                Text("Enter an address (hex) or symbol name.")
            }
            .alert("Search Memory", isPresented: $model.showMemorySearchAlert) {
                TextField("Hex / ASCII pattern", text: $model.memorySearchDraft)
                Button("Search") { model.performMemorySearch() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.vibeAccent)
                    .a11yCatalog("ghidra.vibe.search.memory.go")
                Button("Cancel", role: .cancel) {}
                    .a11yCatalog("ghidra.vibe.search.memory.cancel")
            } message: {
                Text("Search the open program memory for a byte/ASCII pattern.")
            }
            .modifier(TipOfTheDayAlert(isPresented: $model.showTipOfTheDay))
            .sheet(isPresented: $model.showFrameworkOpenSheet) {
                FrameworkOpenSheet()
                    .environment(model)
            }
        }
    }
}

/// Bottom chrome — idle caption bar, or stock-like Task Monitor when work is running.
struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.taskMonitorActive {
                taskMonitor
            } else {
                idleBar
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.taskMonitorActive)
        .vibeStatusBarInset()
        .a11yContainerCatalog("ghidra.vibe.status.bar")
    }

    private var idleBar: some View {
        LiquidGlass.Bar(spacing: 12) {
            HStack(spacing: 12) {
                Text(model.statusMessage)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .a11yCatalog("ghidra.vibe.status.message")
                Spacer(minLength: 8)
                Text(model.currentProgramName.isEmpty ? "No program" : model.currentProgramName)
                    .font(.caption2)
                    .foregroundStyle(Color.vibeSecondary)
                    .lineLimit(1)
                MCPStatusChip()
            }
            .vibeGlassBarBackground()
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Tall, high-contrast strip — mirrors stock Ghidra’s bottom Task Monitor.
    private var taskMonitor: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                        .a11yCatalog("ghidra.vibe.status.progress")

                    Text(model.taskMonitorTitle.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(VibeChrome.ProviderSurface.warning.opacity(0.9), in: Capsule())
                        .foregroundStyle(VibeChrome.ProviderSurface.window)
                        .a11yCatalog("ghidra.vibe.status.busy_badge")

                    Text(model.statusMessage)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .a11yCatalog("ghidra.vibe.status.message")

                    Text(model.taskMonitorElapsedLabel)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.vibeSecondary)
                        .a11yCatalog("ghidra.vibe.status.elapsed")

                    Text(model.currentProgramName.isEmpty ? "No program" : model.currentProgramName)
                        .font(.caption2)
                        .foregroundStyle(Color.vibeSecondary)
                        .lineLimit(1)

                    MCPStatusChip()

                    if model.analysisBusy || model.dyldImportBusy {
                        Button {
                            model.cancelTaskMonitorWork()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VibeChrome.ProviderSurface.warning)
                        .controlSize(.small)
                        .help(
                            model.dyldImportBusy
                                ? "Cancel DSC import (stops headless importer)"
                                : "Cancel Auto Analysis"
                        )
                        .a11yCatalog(
                            model.dyldImportBusy
                                ? "ghidra.vibe.status.cancel_dsc"
                                : "ghidra.vibe.status.cancel_analysis"
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(VibeChrome.ProviderSurface.warning)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .a11yCatalog("ghidra.vibe.status.progress_bar")
            }
            .vibeStatusTaskPlate()
            .background(VibeChrome.ProviderSurface.control)
        }
    }
}

struct MCPStatusChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text(model.mcpStatus)
            .font(.caption2)
            .vibeGlassChip()
            .a11yCatalog("ghidra.vibe.status.mcp")
    }
}

struct ProviderSheetHost: View {
    @Environment(AppModel.self) private var model
    let kind: ProviderKind

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LiquidGlass.Bar(spacing: 8) {
                HStack {
                    Text(kind.title).font(.headline)
                    Spacer()
                    Button("Close") { model.sheetProvider = nil }
                        .buttonStyle(.bordered)
                        .a11yCatalog("ghidra.vibe.sheet.close")
                }
                .padding(.horizontal, 4)
            }
            .padding(8)
            Divider()
            // Content layer stays opaque (no glass-on-glass over listing/providers).
            ProviderView(kind: kind)
                .background(VibeChrome.ProviderSurface.content)
        }
        .background(VibeChrome.ProviderSurface.window)
        .a11yContainerCatalog(kind.a11yRoot)
    }
}
