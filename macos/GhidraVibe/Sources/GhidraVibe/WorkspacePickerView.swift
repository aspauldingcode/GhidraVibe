import SwiftUI

/// Native stand-in for stock Front End workspace / project chooser.
struct WorkspacePickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.vibeTheme) private var themes

    var body: some View {
        @Bindable var model = model
        let t = themes.theme
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Select Project / Workspace")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(t.vibeForeground)
                    .a11yCatalog("ghidra.vibe.workspace.title")

                Text("Open an existing Ghidra project, create a new one, or pick a recent workspace. Gains access to CodeBrowser after a project is active.")
                    .foregroundStyle(t.vibeSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox("Recent projects") {
                    if model.recentProjects.isEmpty {
                        Text("No recent projects")
                            .foregroundStyle(Color.vibeMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    } else {
                        List(model.recentProjects, id: \.self, selection: $model.selectedRecentProject) { path in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                                    .font(.body.weight(.medium))
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(Color.vibeSecondary)
                                    .lineLimit(1)
                                if let chat = model.agentChatPreview(forProject: path) {
                                    Text(chat)
                                        .font(.caption2)
                                        .foregroundStyle(Color.vibeMuted)
                                        .lineLimit(1)
                                }
                            }
                            .tag(path)
                        }
                        .frame(minHeight: 180)
                        .a11yCatalog("ghidra.vibe.workspace.recent_list")
                    }
                }

                LiquidGlass.Bar(spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Open Selected") { model.openSelectedRecentProject() }
                            .buttonStyle(.borderedProminent)
                    .tint(Color.vibeAccent)
                            .disabled(model.selectedRecentProject == nil)
                            .a11yCatalog("ghidra.vibe.workspace.open_selected")
                        Button("Browse…") { model.openProjectPicker() }
                            .buttonStyle(.bordered)
                            .a11yCatalog("ghidra.vibe.workspace.browse")
                        Button("New Project…") { model.newProject() }
                            .buttonStyle(.bordered)
                            .a11yCatalog("ghidra.vibe.workspace.new")
                        Spacer()
                        Button("Continue without project") { model.enterProjectWindow() }
                            .buttonStyle(.bordered)
                            .a11yCatalog("ghidra.vibe.workspace.skip")
                    }
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Workspaces")
                    .font(.headline)
                Text("Default")
                    .padding(VibeChrome.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: VibeChrome.concentric(minimum: VibeChrome.Radius.nestMin))
                    .vibeContainer(radius: VibeChrome.Radius.panel)
                    .a11yCatalog("ghidra.vibe.workspace.default")
                Text("Stock Ghidra stores running tools per workspace. GhidraVibe uses a single Default workspace; open CodeBrowser from the Project Window Tool Chest.")
                    .font(.caption)
                    .foregroundStyle(Color.vibeSecondary)
                Spacer()
                Button("Show Welcome / Help") { model.showWelcomeHelp() }
                    .buttonStyle(.bordered)
                    .a11yCatalog("ghidra.vibe.workspace.show_help")
            }
            .padding(24)
            .frame(width: 280)
        }
        .background(t.vibeWindow)
        .a11yContainerCatalog("ghidra.vibe.workspace")
        .onAppear { model.refreshRecentProjects() }
    }
}
