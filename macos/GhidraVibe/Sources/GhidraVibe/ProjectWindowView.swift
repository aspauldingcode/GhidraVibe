import SwiftUI

/// 1:1 Project Window (FrontEndTool) layout — top→bottom matches stock
/// (`native-ui/parity/FrontEnd.chrome.json`). Liquid Glass on chrome only.
///
/// Stock order (unchanged): unified toolbar → Tool Chest → Active Project
/// (tabs / Filter / tree|table / New·Open·Import·Open Program) → Running Tools → Log.
/// Resize: Active Project absorbs height; no control relocation.
struct ProjectWindowView: View {
    @Environment(AppModel.self) private var model
    @State private var projectTab: ProjectDataTab = .tree
    @State private var projectFilter = ""

    enum ProjectDataTab: String, CaseIterable, Identifiable {
        case tree = "Tree View"
        case table = "Table View"
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            toolChest
                .fixedSize(horizontal: false, vertical: true)
            activeProject
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            runningToolsRow
                .fixedSize(horizontal: false, vertical: true)
            logPanel
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .a11yContainerCatalog("ghidra.vibe.project")
        // Narrow windows (macOS 26): trailing More… mirrors every toolbar action.
        // Adopt `.visibilityPriority` + `ToolbarOverflowMenu` when building with macOS 27 SDK.
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                ForEach(Array(UnifiedToolbars.projectWindow.prefix(6)), id: \.id) { item in
                    UnifiedToolbarButton(id: item.id, systemImage: item.symbol, label: item.label) {
                        projectToolbarAction(item.id)
                    }
                }
            }

            ToolbarSpacer(.fixed, placement: .navigation)

            ToolbarItemGroup(placement: .navigation) {
                if let refresh = UnifiedToolbars.projectWindow[safe: 6] {
                    UnifiedToolbarButton(
                        id: refresh.id,
                        systemImage: refresh.symbol,
                        label: refresh.label
                    ) {
                        projectToolbarAction(refresh.id)
                    }
                    .keyboardShortcut("r", modifiers: [])
                }
            }

            ToolbarSpacer(.fixed, placement: .navigation)

            ToolbarItemGroup(placement: .navigation) {
                UnifiedToolbarButton(
                    id: "ghidra.vibe.toolbar.mcp_health",
                    systemImage: "heart.text.square",
                    label: "Engine Status"
                ) {
                    projectToolbarAction("ghidra.vibe.toolbar.mcp_health")
                }
                UnifiedToolbarButton(
                    id: "ghidra.vibe.toolbar.start_mcp",
                    systemImage: "bolt.horizontal.circle",
                    label: "Restart Engine"
                ) {
                    projectToolbarAction("ghidra.vibe.toolbar.start_mcp")
                }
                .a11yCatalog("ghidra.vibe.project.start_mcp")
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Section("Version Control") {
                        ForEach(Array(UnifiedToolbars.projectWindow.prefix(6)), id: \.id) { item in
                            Button(item.label) { projectToolbarAction(item.id) }
                        }
                    }
                    if let refresh = UnifiedToolbars.projectWindow[safe: 6] {
                        Button(refresh.label) { projectToolbarAction(refresh.id) }
                    }
                    Section("Engine") {
                        Button("Engine Status") {
                            projectToolbarAction("ghidra.vibe.toolbar.mcp_health")
                        }
                        Button("Restart Engine") {
                            projectToolbarAction("ghidra.vibe.toolbar.start_mcp")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("More Project Window tools (includes actions clipped on narrow windows)")
                .accessibilityIdentifier("ghidra.vibe.project.toolbar.more")
            }
        }
    }

    private func projectToolbarAction(_ id: String) {
        switch id {
        case "ghidra.vibe.project.toolbar.refresh":
            model.refreshProjectPrograms()
            model.refreshRecentProjects()
            model.statusMessage = "Refreshed project data"
        case "ghidra.vibe.toolbar.mcp_health":
            model.refreshMCPHealth()
        case "ghidra.vibe.toolbar.start_mcp":
            model.ensureProgramEngineRunning()
        default:
            let act = id.split(separator: ".").last.map(String.init) ?? "refresh_vc"
            model.runAction(id: act == "refresh" ? "refresh_vc" : act)
        }
    }

    // MARK: Tool Chest

    private var toolChest: some View {
        stockSection("Tool Chest") {
            LiquidGlass.Bar(spacing: 20) {
                HStack(spacing: 20) {
                    // Stock FrontEnd ProjectToolBar: alphabetical tool-chest order
                    toolButton("CodeBrowser", "flame.fill", "ghidra.vibe.project.tool.codebrowser") {
                        model.openCodeBrowser()
                    }
                    toolButton("Debugger", "ant", "ghidra.vibe.project.tool.debugger") {
                        model.openDebugger()
                    }
                    toolButton("Emulator", "cpu", "ghidra.vibe.project.tool.emulator") {
                        model.openEmulator()
                    }
                    toolButton(
                        "Version Tracking",
                        "shoeprints.fill",
                        "ghidra.vibe.project.tool.version_tracking"
                    ) {
                        model.openVersionTracking()
                    }
                    Divider().frame(height: 36)
                    toolButton(
                        "Shared Cache",
                        "internaldrive",
                        "ghidra.vibe.project.tool.dsc"
                    ) {
                        model.presentFrameworkOpenSheet()
                    }
                    toolButton(
                        "App Bundle",
                        "apple.logo",
                        "ghidra.vibe.project.tool.apple"
                    ) {
                        model.openAppBundlePicker()
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Active Project

    private var activeProject: some View {
        @Bindable var model = model
        let title = model.projectPath.isEmpty
            ? "Active Project: "
            : "Active Project: \(URL(fileURLWithPath: model.projectPath).deletingPathExtension().lastPathComponent)"
        return stockSection(title) {
            VStack(spacing: VibeChrome.Space.sm) {
                Picker("", selection: $projectTab) {
                    ForEach(ProjectDataTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ghidra.vibe.project.data_tabs")

                projectFilterRow

                Group {
                    switch projectTab {
                    case .tree:
                        NativeOutlineTree(
                            roots: OutlineTreeBuilder.projectTree(
                                projectPath: model.projectPath,
                                programs: filteredPrograms
                            ),
                            selection: Binding(
                                get: {
                                    model.selectedProjectProgram.map { "ghidra.vibe.project.row.\($0)" }
                                },
                                set: { id in
                                    if let id, id.hasPrefix("ghidra.vibe.project.row.") {
                                        model.selectedProjectProgram = String(
                                            id.dropFirst("ghidra.vibe.project.row.".count)
                                        )
                                    } else if id == nil {
                                        model.selectedProjectProgram = nil
                                    }
                                }
                            ),
                            a11yId: "ghidra.vibe.project.tree",
                            emptyLabel: "No programs",
                            agentDrag: OutlineAgentDragSource { _ in .mention(.program) }
                        ) { node in
                            if let name = node.payload, !node.isFolder {
                                model.selectedProjectProgram = name
                                model.statusMessage = "Selected \(name)"
                            }
                        }
                    case .table:
                        List(filteredPrograms, id: \.self, selection: $model.selectedProjectProgram) { name in
                            HStack {
                                Text(name).frame(maxWidth: .infinity, alignment: .leading)
                                Text(model.projectPath)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(Color.vibeSecondary)
                                Text("Program").foregroundStyle(Color.vibeSecondary)
                            }
                            .font(.caption)
                            .contentShape(Rectangle())
                            .agentMentionDraggable(AgentMentionDrag.program, title: name)
                            .help("Drag onto Agent to insert @Program")
                            .accessibilityIdentifier("ghidra.vibe.project.row.\(name)")
                        }
                        .listStyle(.inset)
                .vibeThemedList()
                        .scrollContentBackground(.hidden)
                        .a11yCatalog("ghidra.vibe.project.tree")
                    }
                }
                // Rounded nested plate under Project Window shell. Explicit continuous radius —
                // ConcentricRectangle alone collapsed to sharp after stockSection was flattened
                // (no panel containerShape for the List's square AppKit chrome to nest under).
                .frame(minHeight: 80, maxHeight: .infinity)
                .padding(VibeChrome.Space.xs)
                .vibeProviderShell(radius: VibeChrome.Radius.panel)
                .vibeContainer(radius: VibeChrome.Radius.panel)

                LiquidGlass.Bar(spacing: VibeChrome.Space.md) {
                    HStack(spacing: VibeChrome.Space.md) {
                        Button("New Project...") { model.newProject() }
                            .buttonStyle(.bordered)
                            .a11yCatalog("ghidra.vibe.project.new")
                        Button("Open Project...") { model.openProjectPicker() }
                            .buttonStyle(.bordered)
                            .a11yCatalog("ghidra.vibe.project.open")
                        Button("Import File...") { model.importFilePicker() }
                            .buttonStyle(.bordered)
                            .a11yCatalog("ghidra.vibe.project.import")
                        Button("Open Program") { model.openSelectedProgram() }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.vibeAccent)
                            .a11yCatalog("ghidra.vibe.project.open_program")
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    /// Stock “Filter:” above the tree — concentric field nest (not AppKit roundedBorder).
    private var projectFilterRow: some View {
        HStack(alignment: .center, spacing: VibeChrome.Space.sm) {
            Text("Filter:")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.vibeSecondary)
                .fixedSize()

            HStack(spacing: VibeChrome.Space.sm) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.vibeSecondary)
                    .accessibilityHidden(true)

                TextField("Filter", text: $projectFilter)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .a11yCatalog("ghidra.vibe.project.filter")

                if !projectFilter.isEmpty {
                    Button {
                        projectFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.vibeSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear filter")
                    .accessibilityLabel("Clear filter")
                }
            }
            .padding(.horizontal, VibeChrome.Space.lg)
            .padding(.vertical, VibeChrome.Space.sm)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .glassEffect(
                .regular.interactive(),
                in: VibeChrome.concentric(minimum: VibeChrome.Radius.dock)
            )
            .containerShape(
                .rect(cornerRadius: VibeChrome.nested(
                    outer: VibeChrome.Radius.panel,
                    padding: VibeChrome.Space.md
                ))
            )
        }
        .padding(.horizontal, VibeChrome.Space.xxs)
        .accessibilityElement(children: .contain)
    }

    private var filteredPrograms: [String] {
        let q = projectFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return model.projectPrograms }
        return model.projectPrograms.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    // MARK: Running Tools + Workspace

    private var runningToolsRow: some View {
        stockSection("Running Tools") {
            HStack {
                if model.toolMode == .debugger {
                    Button("Debugger") { model.openDebugger() }
                        .buttonStyle(.borderedProminent)
                    .tint(Color.vibeAccent)
                        .a11yCatalog("ghidra.vibe.project.running_debugger")
                } else if model.toolMode == .emulator {
                    Button("Emulator") { model.openEmulator() }
                        .buttonStyle(.borderedProminent)
                    .tint(Color.vibeAccent)
                        .a11yCatalog("ghidra.vibe.project.running_emulator")
                } else if model.toolMode == .versionTrackingTool {
                    Button("Version Tracking") { model.openVersionTracking() }
                        .buttonStyle(.borderedProminent)
                    .tint(Color.vibeAccent)
                        .a11yCatalog("ghidra.vibe.project.running_vt")
                } else if model.currentProgramName.isEmpty && model.toolMode != .codeBrowser {
                    Text("(none)")
                        .foregroundStyle(Color.vibeSecondary)
                        .font(.caption)
                } else {
                    Button {
                        model.openCodeBrowser()
                    } label: {
                        Label(
                            model.currentProgramName.isEmpty
                                ? "CodeBrowser" : "CodeBrowser — \(model.currentProgramName)",
                            systemImage: "flame.fill"
                        )
                        .lineLimit(1)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.vibeAccent)
                    .a11yCatalog("ghidra.vibe.project.running_codebrowser")
                }
                Spacer(minLength: 8)
                Picker("Workspace", selection: .constant("Workspace")) {
                    Text("Workspace").tag("Workspace")
                }
                .frame(minWidth: 120, idealWidth: 200, maxWidth: 200)
                .a11yCatalog("ghidra.vibe.project.workspace_picker")
            }
        }
        .a11yCatalog("ghidra.vibe.project.body.running_tools_workspace_combo")
    }

    // MARK: LogPanel (FrontEnd in-content log strip — concentric with shell; StatusBar is separate)

    private var logPanel: some View {
        LiquidGlass.Bar(spacing: VibeChrome.Space.md) {
            HStack(spacing: VibeChrome.Space.lg) {
                if model.taskMonitorActive {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.taskMonitorTitle.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.vibeWarning)
                }
                Text(model.consoleText.split(separator: "\n").last.map(String.init) ?? model.statusMessage)
                    .font(model.taskMonitorActive ? .caption.weight(.medium) : .caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .a11yCatalog("ghidra.vibe.project.log")
                GlassToolbarButton(
                    id: "ghidra.vibe.project.show_log",
                    systemImage: "text.alignleft",
                    label: "Show Log / Console"
                ) {
                    model.showProvider(.console)
                    model.toolMode = .codeBrowser
                }
            }
            .vibeGlassBarBackground()
        }
        .vibeStatusBarInset()
    }

    /// Labeled FrontEnd section (stock GroupBox title strings).
    /// Flat in-window strip — not a nested “card window” (Tool Chest lives *inside* Project Window).
    @ViewBuilder
    private func stockSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: VibeChrome.Space.sm) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.vibeSecondary)
                .padding(.horizontal, VibeChrome.Space.md)

            content()
                .padding(.horizontal, VibeChrome.Space.md)
                .padding(.vertical, VibeChrome.Space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, VibeChrome.Space.xs)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(VibeChrome.ProviderSurface.separator)
                .frame(height: 1)
        }
    }

    private func toolButton(_ title: String, _ symbol: String, _ id: String, action: @escaping () -> Void) -> some View {
        // Apply `.glassEffect` to the icon (content-first). Using
        // `.background { …glassEffect }` on Tahoe composites the material *over* the
        // SF Symbol. Avoid `.interactive` glass inside Button — it steals AX/click hits.
        Button(action: action) {
            VStack(spacing: VibeChrome.Space.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.vibeForeground)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular, in: VibeChrome.rounded(VibeChrome.Radius.well))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(Color.vibeForeground)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .a11yCatalog(id)
        .help(A11yCatalog.hoverTip(for: id, fallback: title))
    }
}
