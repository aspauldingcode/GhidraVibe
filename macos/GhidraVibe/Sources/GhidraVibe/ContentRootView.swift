import SwiftUI

/// Startup → Workspace → Project Window / CodeBrowser chrome (native + Liquid Glass).
struct ContentRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    switch model.toolMode {
                    case .splash:
                        SplashView()
                    case .workspacePicker:
                        WorkspacePickerView()
                    case .welcomeHelp:
                        WelcomeHelpView()
                    case .projectWindow:
                        ProjectWindowView()
                    case .codeBrowser:
                        CodeBrowserDockView()
                            .a11yContainerCatalog("ghidra.vibe.codebrowser")
                    case .debugger, .emulator, .versionTrackingTool:
                        StockToolShellView(toolMode: model.toolMode)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if model.toolMode == .projectWindow, let sheet = model.sheetProvider {
                    Divider()
                    ProviderSheetHost(kind: sheet)
                        .frame(minHeight: 160, idealHeight: 220, maxHeight: 320)
                        .layoutPriority(0)
                }

                if model.toolMode != .splash {
                    StatusBar()
                }
            }
            .a11yContainerCatalog("ghidra.vibe.root")
            .navigationTitle(model.toolMode.rawValue)
            // Engine Status / Restart live in ProjectWindowView chrome (AX-stable).
            // CodeBrowser keeps its own in-content toolbar.
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
                    .buttonStyle(.glassProminent)
                    .a11yCatalog("ghidra.vibe.goto.go")
                Button("Cancel", role: .cancel) {}
                    .a11yCatalog("ghidra.vibe.goto.cancel")
            } message: {
                Text("Enter an address (hex) or symbol name.")
            }
            .alert("Search Memory", isPresented: $model.showMemorySearchAlert) {
                TextField("Hex / ASCII pattern", text: $model.memorySearchDraft)
                Button("Search") { model.performMemorySearch() }
                    .buttonStyle(.glassProminent)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                MCPStatusChip()
            }
            .vibeGlassBarBackground()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
                        .background(Color.orange.opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
                        .a11yCatalog("ghidra.vibe.status.busy_badge")

                    Text(model.statusMessage)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .a11yCatalog("ghidra.vibe.status.message")

                    Text(model.taskMonitorElapsedLabel)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .a11yCatalog("ghidra.vibe.status.elapsed")

                    Text(model.currentProgramName.isEmpty ? "No program" : model.currentProgramName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    MCPStatusChip()

                    if model.analysisBusy {
                        Button {
                            model.cancelAutoAnalyze()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                        .help("Cancel Auto Analysis")
                        .a11yCatalog("ghidra.vibe.status.cancel_analysis")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.orange)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .a11yCatalog("ghidra.vibe.status.progress_bar")
            }
            // Opaque task plate (not Liquid Glass) — stock Task Monitor must read as a
            // content/status surface, not another glass chrome layer.
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.7), lineWidth: 2)
            }
            .background(Color.orange.opacity(0.12))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
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
                        .buttonStyle(.glass)
                        .a11yCatalog("ghidra.vibe.sheet.close")
                }
                .padding(.horizontal, 4)
            }
            .padding(8)
            Divider()
            // Content layer stays opaque (no glass-on-glass over listing/providers).
            ProviderView(kind: kind)
        }
        .a11yContainerCatalog(kind.a11yRoot)
    }
}
