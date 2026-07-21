import SwiftUI
import UniformTypeIdentifiers

/// Simplified Agent configuration — provider + model + optional key file + GGUF drop.
struct AgentSetupPanel: View {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false
    @State private var importNote = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Provider") {
                Picker("API", selection: $model.agentProvider) {
                    ForEach(AgentProviderKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .onChange(of: model.agentProvider) { _, new in
                    model.applyAgentProviderDefaults(new)
                    model.persistAgentAISettings()
                    model.refreshAgentModels()
                }
                Text(model.agentProvider.subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.vibeSecondary)

                if model.agentProvider == .openaiCompat {
                    Picker("Gateway", selection: $model.agentCompatPresetId) {
                        ForEach(AgentOpenAICompatPreset.all) { preset in
                            Text(preset.title).tag(preset.id)
                        }
                    }
                    .onChange(of: model.agentCompatPresetId) { _, id in
                        if let preset = AgentOpenAICompatPreset.all.first(where: { $0.id == id }) {
                            model.agentBaseURL = preset.baseURL
                            if model.agentModel.isEmpty || model.agentProvider.suggestedModels.contains(model.agentModel) {
                                model.agentModel = preset.defaultModel
                            }
                            model.persistAgentAISettings()
                        }
                    }
                }

                TextField("Base URL", text: $model.agentBaseURL)
                    .onSubmit { model.persistAgentAISettings() }
            }

            Section("Model") {
                if !model.agentModelPicker.isEmpty {
                    Picker("Model", selection: $model.agentModel) {
                        ForEach(model.agentModelPicker, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .onChange(of: model.agentModel) { _, _ in
                        model.persistAgentAISettings()
                    }
                } else if !model.agentProvider.suggestedModels.isEmpty {
                    Picker("Model", selection: $model.agentModel) {
                        ForEach(model.agentProvider.suggestedModels, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .onChange(of: model.agentModel) { _, _ in
                        model.persistAgentAISettings()
                    }
                }
                TextField("Model id", text: $model.agentModel)
                    .help("Any model id your provider accepts")
                    .onSubmit { model.persistAgentAISettings() }
                HStack {
                    Button("Refresh models") { model.refreshAgentModels() }
                    Spacer()
                    Text(model.agentBackend)
                        .font(.caption2)
                        .foregroundStyle(Color.vibeSecondary)
                }
            }

            if model.agentProvider.needsKeyFile {
                Section("API key") {
                    TextField("Key file path", text: $model.apiKeyFilePath)
                        .help("Path to a file containing the key (never paste keys into Nix)")
                        .onSubmit { model.persistAgentAISettings() }
                    Text("OpenAI / Anthropic / Google / OpenRouter — one file per provider profile.")
                        .font(.caption2)
                        .foregroundStyle(Color.vibeSecondary)
                }
            }

            if model.agentProvider == .ollama || model.agentProvider == .llamaCpp {
                Section("Local models (no bundled weights)") {
                    Text(AgentLocalModels.modelsDirectory.path)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                    dropZone
                    HStack {
                        Button("Open Models folder") { AgentLocalModels.openInFinder() }
                        Button("Scan folder") {
                            model.refreshLocalWeightModels()
                        }
                    }
                    if !importNote.isEmpty {
                        Text(importNote)
                            .font(.caption2)
                            .foregroundStyle(Color.vibeSecondary)
                    }
                    if model.agentProvider == .llamaCpp {
                        Text("Serve with: llama-server -m <file.gguf> --port 8080")
                            .font(.caption2)
                            .foregroundStyle(Color.vibeSecondary)
                    }
                }
            }

            Section("Sounds") {
                Toggle(
                    "Play sound when Agent finishes",
                    isOn: Binding(
                        get: { model.agentCompletionSoundEnabled },
                        set: {
                            model.agentCompletionSoundEnabled = $0
                            model.persistAgentAISettings()
                        }
                    )
                )
                .help("Glass on success, Basso on error — silent when you interrupt a turn")
                .a11yCatalog("ghidra.vibe.agent.setup.completion_sound")
            }

            Section("Tool permissions") {
                Picker(
                    "Default",
                    selection: Binding(
                        get: { AgentToolPermissionStore.shared.profile },
                        set: { model.setAgentToolPermissionProfile($0) }
                    )
                ) {
                    ForEach(AgentToolPermissionProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .help("Cursor-like defaults for Agent tool calling")
                .a11yCatalog("ghidra.vibe.agent.setup.tool_profile")

                Text(AgentToolPermissionStore.shared.profile.subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.vibeSecondary)

                Toggle(
                    "Sandbox tool calls",
                    isOn: Binding(
                        get: { AgentToolPermissionStore.shared.sandboxEnabled },
                        set: { model.setAgentToolSandboxEnabled($0) }
                    )
                )
                .help(
                    "On: network allowlist (DuckDuckGo/Wikipedia) + treat dangerous gui_action ids as writes"
                )
                .a11yCatalog("ghidra.vibe.agent.setup.tool_sandbox")

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(AgentToolPermissionStore.shared.summaryLines(), id: \.self) { line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Color.vibeSecondary)
                    }
                }
                .id(model.agentToolPermissionEpoch)
                .a11yCatalog("ghidra.vibe.agent.setup.tool_summary")

                Button("Reset tool permissions", role: .destructive) {
                    model.resetAgentToolPermissions()
                }
                .help("Clear Always Allow / session allows and restore Ask writes + sandbox")
                .a11yCatalog("ghidra.vibe.agent.setup.tool_reset")
            }

            Section("Experts (optional)") {
                Toggle(
                    "Route by task (MoE)",
                    isOn: Binding(
                        get: { model.agentMoE.enabled },
                        set: { model.agentMoE.enabled = $0; model.persistAgentAISettings() }
                    )
                )
                Toggle(
                    "Allow cloud escalation",
                    isOn: Binding(
                        get: { model.agentMoE.allowCloudEscalation },
                        set: {
                            model.agentMoE.allowCloudEscalation = $0
                            model.persistAgentAISettings()
                        }
                    )
                )
                .help("On local failure, retry with the configured proprietary provider")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 360, idealWidth: 400)
        .onAppear {
            try? AgentLocalModels.ensureDirectory()
            model.refreshAgentModels()
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.title2)
            Text("Drop .gguf or .ccp here")
                .font(.caption.weight(.semibold))
            Text("Copied into the GhidraVibe Models folder")
                .font(.caption2)
                .foregroundStyle(Color.vibeSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .padding(12)
        .background(
            isTargeted
                ? VibeChrome.ProviderSurface.control.opacity(0.55)
                : VibeChrome.ProviderSurface.control
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .a11yCatalog("ghidra.vibe.agent.setup.drop_models")
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let u = item as? URL {
                url = u
            } else {
                url = nil
            }
            guard let url else { return }
            Task { @MainActor in
                do {
                    let entry = try AgentLocalModels.importWeight(from: url)
                    importNote = "Imported \(entry.displayName)"
                    model.agentProvider = .llamaCpp
                    model.agentBaseURL = AgentProviderKind.llamaCpp.defaultBaseURL
                    model.agentModel = entry.displayName
                    model.persistAgentAISettings()
                    model.refreshLocalWeightModels()
                    model.statusMessage = "Local model ready: \(entry.displayName)"
                } catch {
                    importNote = error.localizedDescription
                }
            }
        }
        return true
    }
}
