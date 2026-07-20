import SwiftUI

struct AgentChatView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            Divider()
            if model.showAgentWelcome {
                welcome
            } else {
                transcript
                if !model.agentPendingEdits.isEmpty {
                    pendingBar
                    Divider()
                }
                Divider()
                composer
            }
        }
        .navigationTitle("Agent")
        .a11yContainerCatalog("ghidra.vibe.agent.sidebar")
    }

    private var header: some View {
        HStack {
            Text("Agent")
                .font(.headline)
            Spacer()
            Text(model.agentMoE.enabled ? "MoE" : model.agentBackend)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help(model.agentMoELastRoute.isEmpty ? model.agentBackend : model.agentMoELastRoute)
            if model.agentBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to GhidraVibe Agent")
                    .font(.title2.weight(.semibold))
                    .a11yCatalog("ghidra.vibe.provider.agent")
                Text(
                    "Agent uses JSpace RAG + Mixture of Experts over local Ollama models (rename / decompile / "
                        + "ObjC-Swift / plan), with optional proprietary API escalation. Same OpenAI-compat path as "
                        + "the dendritic `chat` CLI. Configure experts in Settings."
                )
                .font(.body)
                Text("Prefer Cursor?")
                    .font(.headline)
                Text(
                    "Use the packaged bridges: ghidra (analysis MCP) + ghidra-vibe-gui (shell control). See docs/CURSOR.md and docs/AGENT_CHAT.md."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                HStack {
                    Button("Start chatting") { model.dismissAgentWelcome() }
                        .buttonStyle(.glass)
                        .help("Dismiss welcome and open the agent composer")
                    Button("Opt out of Agent") { model.optOutAgent() }
                        .help("Hide Agent panel by default")
                }
            }
            .padding()
        }
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(model.agentMessages) { msg in
                    Text(msg.text)
                        .frame(maxWidth: .infinity, alignment: msg.role == .user ? .trailing : .leading)
                        .padding(10)
                        .background(msg.role == .user ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .a11yCatalog("ghidra.vibe.provider.agent.transcript")
    }

    private var pendingBar: some View {
        HStack {
            Text("\(model.agentPendingEdits.count) pending edit(s)")
                .font(.caption)
            Spacer()
            Button("Apply") { model.applyAgentPendingEdits() }
                .buttonStyle(.glass)
                .a11yCatalog("ghidra.vibe.provider.agent.apply")
            Button("Clear") { model.clearAgentPendingEdits() }
                .a11yCatalog("ghidra.vibe.provider.agent.clear_pending")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var composer: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 8) {
            Text(model.jspaceStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(model.agentModel.isEmpty ? "(no model)" : model.agentModel) @ \(model.agentBaseURL)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !model.apiBackendAvailable && !model.agentUseLocalOllama {
                Text("API backend disabled (no key file). Enable local Ollama or set a key file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Index JSpace") { model.indexJSpace() }
                    .a11yCatalog("ghidra.vibe.provider.agent.index")
                Button("Autonomous RE") { model.runAutonomousREPlaybook() }
                    .help("Budgeted rename/comment playbook over interesting functions")
                    .a11yCatalog("ghidra.vibe.provider.agent.autonomous_re")
                Button("Improve") {
                    model.queueImproveDecompile(
                        name: model.selectedFunction?.name,
                        address: model.selectedFunction?.address,
                        apply: false
                    )
                }
                .help("Propose readability renames/comments for the selected function")
                .a11yCatalog("ghidra.vibe.provider.agent.improve")
            }
            HStack {
                TextField("Ask about the program…", text: $model.agentDraft, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .a11yCatalog("ghidra.vibe.provider.agent.composer")
                    .disabled(model.agentBusy)
                Button("Send") { model.sendAgentMessage() }
                    .buttonStyle(.glass)
                    .a11yCatalog("ghidra.vibe.provider.agent.send")
                    .disabled(model.agentBusy || model.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(8)
        }
    }
}
