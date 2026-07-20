import SwiftUI

/// 1:1 Project Window (FrontEndTool) layout — top→bottom matches stock
/// (`native-ui/parity/FrontEnd.chrome.json`). Liquid Glass on chrome only.
///
/// Resize policy (no redesign): fixed chrome strips keep their stock look;
/// Active Project absorbs height; toolbars clip/scroll only when the window
/// is narrower than the stock control row.
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
            frontEndToolbar
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            toolChest
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            activeProject
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            Divider()
            runningToolsRow
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            logPanel
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .a11yContainerCatalog("ghidra.vibe.project")
    }

    // MARK: Docking toolbar (VC + Refresh) — same slots as FrontEndPlugin

    private var frontEndToolbar: some View {
        LiquidGlass.Bar(spacing: 6) {
            // Horizontal scroll only when narrower than the stock icon row —
            // at default width this reads identically to a plain HStack.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.vcActions, id: \.0) { title, symbol, id in
                        GlassToolbarButton(id: id, systemImage: symbol, label: title) {
                            let act = id.split(separator: ".").last.map(String.init) ?? "refresh_vc"
                            model.runAction(id: act == "refresh" ? "refresh_vc" : act)
                        }
                    }
                    GlassToolbarButton(
                        id: "ghidra.vibe.project.toolbar.refresh",
                        systemImage: "arrow.clockwise",
                        label: "Refresh"
                    ) {
                        model.refreshProjectPrograms()
                        model.refreshRecentProjects()
                        model.statusMessage = "Refreshed project data"
                    }
                    .keyboardShortcut("r", modifiers: [])
                    Divider().frame(height: 18)
                    // In-content (not NSToolbar) so AX ids are stable for smokes / GuiControl.
                    GlassToolbarButton(
                        id: "ghidra.vibe.toolbar.mcp_health",
                        systemImage: "heart.text.square",
                        label: "Engine Status"
                    ) {
                        model.refreshMCPHealth()
                    }
                    GlassToolbarButton(
                        id: "ghidra.vibe.toolbar.start_mcp",
                        systemImage: "bolt.horizontal.circle",
                        label: "Restart Engine"
                    ) {
                        model.ensureProgramEngineRunning()
                    }
                    .a11yCatalog("ghidra.vibe.project.start_mcp")
                    Spacer(minLength: 0)
                }
                .vibeGlassBarBackground()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private static let vcActions: [(String, String, String)] = [
        ("Add to Version Control", "plus.rectangle.on.folder", "ghidra.vibe.project.toolbar.vc_add"),
        ("CheckOut", "arrow.down.doc", "ghidra.vibe.project.toolbar.vc_checkout"),
        ("Update", "arrow.triangle.2.circlepath", "ghidra.vibe.project.toolbar.vc_update"),
        ("CheckIn", "arrow.up.doc", "ghidra.vibe.project.toolbar.vc_checkin"),
        ("UndoCheckOut", "arrow.uturn.backward", "ghidra.vibe.project.toolbar.vc_undo"),
        ("Find Checkouts", "magnifyingglass", "ghidra.vibe.project.toolbar.vc_find"),
    ]

    // MARK: Tool Chest

    private var toolChest: some View {
        GroupBox("Tool Chest") {
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
            .padding(6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: Active Project

    private var activeProject: some View {
        @Bindable var model = model
        let title = model.projectPath.isEmpty
            ? "Active Project: "
            : "Active Project: \(URL(fileURLWithPath: model.projectPath).deletingPathExtension().lastPathComponent)"
        return GroupBox(title) {
            VStack(spacing: 0) {
                Picker("", selection: $projectTab) {
                    ForEach(ProjectDataTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(6)
                .accessibilityIdentifier("ghidra.vibe.project.data_tabs")

                HStack {
                    Text("Filter:")
                    TextField("Filter", text: $projectFilter)
                        .textFieldStyle(.roundedBorder)
                        .a11yCatalog("ghidra.vibe.project.filter")
                }
                .padding(.horizontal, 8)

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
                            emptyLabel: "No programs"
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
                                    .foregroundStyle(.secondary)
                                Text("Program").foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            .accessibilityIdentifier("ghidra.vibe.project.row.\(name)")
                        }
                        .a11yCatalog("ghidra.vibe.project.tree")
                    }
                }
                // Stock look at default size; list is the only flex region when shrinking.
                .frame(minHeight: 80, maxHeight: .infinity)

                LiquidGlass.Bar(spacing: 8) {
                    HStack(spacing: 8) {
                        Button("New Project...") { model.newProject() }
                            .buttonStyle(.glass)
                            .a11yCatalog("ghidra.vibe.project.new")
                        Button("Open Project...") { model.openProjectPicker() }
                            .buttonStyle(.glass)
                            .a11yCatalog("ghidra.vibe.project.open")
                        Button("Import File...") { model.importFilePicker() }
                            .buttonStyle(.glass)
                            .a11yCatalog("ghidra.vibe.project.import")
                        Button("Open Program") { model.openSelectedProgram() }
                            .buttonStyle(.glassProminent)
                            .a11yCatalog("ghidra.vibe.project.open_program")
                        Spacer(minLength: 0)
                    }
                }
                .padding(6)
            }
        }
        .padding(.horizontal, 8)
    }

    private var filteredPrograms: [String] {
        let q = projectFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return model.projectPrograms }
        return model.projectPrograms.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    // MARK: Running Tools + Workspace

    private var runningToolsRow: some View {
        GroupBox("Running Tools") {
            HStack {
                if model.toolMode == .debugger {
                    Button("Debugger") { model.openDebugger() }
                        .buttonStyle(.glassProminent)
                        .a11yCatalog("ghidra.vibe.project.running_debugger")
                } else if model.toolMode == .emulator {
                    Button("Emulator") { model.openEmulator() }
                        .buttonStyle(.glassProminent)
                        .a11yCatalog("ghidra.vibe.project.running_emulator")
                } else if model.toolMode == .versionTrackingTool {
                    Button("Version Tracking") { model.openVersionTracking() }
                        .buttonStyle(.glassProminent)
                        .a11yCatalog("ghidra.vibe.project.running_vt")
                } else if model.currentProgramName.isEmpty && model.toolMode != .codeBrowser {
                    Text("(none)")
                        .foregroundStyle(.secondary)
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
                    .buttonStyle(.glassProminent)
                    .a11yCatalog("ghidra.vibe.project.running_codebrowser")
                }
                Spacer(minLength: 8)
                Picker("Workspace", selection: .constant("Workspace")) {
                    Text("Workspace").tag("Workspace")
                }
                .frame(minWidth: 120, idealWidth: 200, maxWidth: 200)
                .a11yCatalog("ghidra.vibe.project.workspace_picker")
            }
            .padding(6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .a11yCatalog("ghidra.vibe.project.body.running_tools_workspace_combo")
    }

    // MARK: LogPanel (FrontEnd status window — not docking StatusBar)

    private var logPanel: some View {
        LiquidGlass.Bar(spacing: 8) {
            HStack(spacing: 10) {
                if model.taskMonitorActive {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.taskMonitorTitle.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func toolButton(_ title: String, _ symbol: String, _ id: String, action: @escaping () -> Void) -> some View {
        // Apply `.glassEffect` to the icon (content-first). Using
        // `.background { …glassEffect }` on Tahoe composites the material *over* the
        // SF Symbol. Avoid `.interactive` glass inside Button — it steals AX/click hits.
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .a11yCatalog(id)
        .help(A11yCatalog.hoverTip(for: id, fallback: title))
    }
}
