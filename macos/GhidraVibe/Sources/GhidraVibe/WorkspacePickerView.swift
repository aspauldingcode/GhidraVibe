import SwiftUI

/// Native stand-in for stock Front End workspace / project chooser.
struct WorkspacePickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Select Project / Workspace")
                    .font(.title2.weight(.semibold))
                    .a11yCatalog("ghidra.vibe.workspace.title")

                Text("Open an existing Ghidra project, create a new one, or pick a recent workspace. Gains access to CodeBrowser after a project is active.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox("Recent projects") {
                    if model.recentProjects.isEmpty {
                        Text("No recent projects")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    } else {
                        List(model.recentProjects, id: \.self, selection: $model.selectedRecentProject) { path in
                            VStack(alignment: .leading) {
                                Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                                    .font(.body.weight(.medium))
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
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
                            .buttonStyle(.glassProminent)
                            .disabled(model.selectedRecentProject == nil)
                            .a11yCatalog("ghidra.vibe.workspace.open_selected")
                        Button("Browse…") { model.openProjectPicker() }
                            .buttonStyle(.glass)
                            .a11yCatalog("ghidra.vibe.workspace.browse")
                        Button("New Project…") { model.newProject() }
                            .buttonStyle(.glass)
                            .a11yCatalog("ghidra.vibe.workspace.new")
                        Spacer()
                        Button("Continue without project") { model.enterProjectWindow() }
                            .buttonStyle(.glass)
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
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 10))
                    .a11yCatalog("ghidra.vibe.workspace.default")
                Text("Stock Ghidra stores running tools per workspace. GhidraVibe uses a single Default workspace; open CodeBrowser from the Project Window Tool Chest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show Welcome / Help") { model.showWelcomeHelp() }
                    .buttonStyle(.glass)
                    .a11yCatalog("ghidra.vibe.workspace.show_help")
            }
            .padding(24)
            .frame(width: 280)
        }
        .a11yContainerCatalog("ghidra.vibe.workspace")
        .onAppear { model.refreshRecentProjects() }
    }
}
