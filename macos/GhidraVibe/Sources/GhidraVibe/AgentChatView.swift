import AppKit
import SwiftUI

struct AgentChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.vibeTheme) private var themes
    /// Cursor-style `@` mention picker.
    @State private var mentionOpen = false
    @State private var mentionCategory: AgentMentionCategory?
    @State private var mentionFilter = ""
    @State private var mentionReplaceStart: Int = 0
    @State private var insertMentionToken: String?
    /// Agent sidebar height (for composer max = min(20 lines, 20% of sidebar)).
    @State private var agentSidebarHeight: CGFloat = 560
    /// Intrinsic draft height measured from the NSTextView (before capping).
    @State private var composerContentHeight: CGFloat = AgentComposerField.minHeight

    var body: some View {
        @Bindable var model = model
        let t = themes.theme
        GeometryReader { geo in
            VStack(spacing: 0) {
                header
                if model.showAgentWelcome {
                    welcome
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(t.vibeContent)
                } else {
                    ZStack(alignment: .bottom) {
                        VStack(spacing: 0) {
                            if let plan = model.agentPlan {
                                AgentPlanCard(
                                    plan: plan,
                                    onToggle: { model.toggleAgentPlanStep($0) },
                                    onBuild: { model.buildAgentPlan() },
                                    onDiscard: { model.discardAgentPlan() }
                                )
                                .padding(.horizontal, VibeChrome.Space.md)
                                .padding(.top, VibeChrome.Space.sm)
                            }
                            transcript
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .background(t.vibeContent)
                        if mentionOpen {
                            AgentMentionPicker(
                                category: $mentionCategory,
                                filter: $mentionFilter,
                                model: model
                            ) { item in
                                applyMention(item)
                            } onDismiss: {
                                closeMentionPicker()
                            }
                            .padding(.horizontal, VibeChrome.Space.md)
                            .padding(.bottom, 4)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(2)
                        }
                    }
                    if model.agentToolApproval != nil {
                        toolApprovalBar
                        Divider()
                    }
                    if !model.agentPendingEdits.isEmpty {
                        pendingBar
                        Divider()
                    }
                    if !model.agentSendQueue.isEmpty {
                        queueBar
                        Divider()
                    }
                    Divider()
                    composer
                }
            }
            // Square dock column — no rounded provider shell / curved titlebar chrome.
            .background(t.vibeContent)
            // Stroke-only overlays still hit-test their full bounds by default and steal
            // clicks from SwiftUI Reply / transcript controls (AppKit composer can still work).
            .overlay {
                Rectangle()
                    .stroke(t.vibeSelection, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .a11yContainerCatalog("ghidra.vibe.agent.sidebar")
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { agentSidebarHeight = geo.size.height }
            .onChange(of: geo.size.height) { _, h in
                agentSidebarHeight = h
            }
        }
        .animation(.easeOut(duration: 0.15), value: mentionOpen)
        .animation(.easeOut(duration: 0.12), value: composerFieldHeight)
        .onAppear {
            // Opening the Agent column must not steal keyboard focus — show the placeholder hint.
            guard model.agentDraft.isEmpty else { return }
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    private var header: some View {
        @Bindable var model = model
        let t = themes.theme
        return HStack(spacing: VibeChrome.Space.sm) {
            Menu {
                ForEach(AgentInteractionMode.allCases) { mode in
                    Button {
                        model.setAgentInteractionMode(mode)
                    } label: {
                        Label(mode.title, systemImage: mode.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: model.agentInteractionMode.systemImage)
                    Text(model.agentInteractionMode.title)
                        .font(.caption.weight(.semibold))
                }
            }
            .menuStyle(.borderlessButton)
            .help(model.agentInteractionMode.subtitle)
            .a11yCatalog("ghidra.vibe.agent.mode")
            Spacer(minLength: VibeChrome.Space.xs)
            Menu {
                if !model.agentModelPicker.isEmpty {
                    ForEach(model.agentModelPicker.prefix(16), id: \.self) { name in
                        Button(name) {
                            model.agentModel = name
                            model.persistAgentAISettings()
                            model.schedulePersistAgentChat()
                        }
                    }
                    Divider()
                }
                Button("Agent Setup…") { model.showAgentSetup = true }
            } label: {
                Text(model.agentModel.isEmpty ? model.agentProvider.title : model.agentModel)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .help(model.agentMoELastRoute.isEmpty ? model.agentBaseURL : model.agentMoELastRoute)
            .a11yCatalog("ghidra.vibe.agent.model_picker")
            .foregroundStyle(t.vibeSecondary)
            Menu {
                Button("New Chat") {
                    model.startNewAgentChat()
                }
                .a11yCatalog("ghidra.vibe.agent.history.new")
                if !model.agentHistoryThisProject.isEmpty {
                    Section(
                        model.projectPath.isEmpty
                            ? "This workspace"
                            : URL(fileURLWithPath: model.projectPath)
                                .deletingPathExtension()
                                .lastPathComponent
                    ) {
                        ForEach(model.agentHistoryThisProject) { meta in
                            Button {
                                model.openAgentChatSession(meta.id)
                            } label: {
                                historyRowLabel(meta, showProject: false)
                            }
                            .disabled(meta.id == model.agentSessionId)
                        }
                    }
                }
                if !historyFromOtherProjects.isEmpty {
                    Section("Recent projects") {
                        ForEach(historyFromOtherProjects) { meta in
                            Button {
                                model.openAgentChatSession(meta.id)
                            } label: {
                                historyRowLabel(meta, showProject: true)
                            }
                        }
                    }
                }
                if model.agentHistoryThisProject.isEmpty, model.agentHistoryRecent.isEmpty {
                    Text("No saved chats yet")
                }
                Divider()
                if !model.agentMessages.isEmpty {
                    ShareLink(
                        item: model.agentShareChatText,
                        subject: Text(model.agentShareChatTitle),
                        message: Text(model.agentShareChatText)
                    ) {
                        Label("Share Chat", systemImage: "square.and.arrow.up")
                    }
                    .a11yCatalog("ghidra.vibe.agent.history.share")
                    Button("Copy Chat") {
                        AgentShare.copyToPasteboard(model.agentShareChatText)
                        model.statusMessage = "Chat copied"
                    }
                    .a11yCatalog("ghidra.vibe.agent.history.copy")
                    Divider()
                }
                if !model.agentMessages.isEmpty || model.agentHistoryThisProject.contains(where: {
                    $0.id == model.agentSessionId
                }) {
                    Button("Delete Current Chat", role: .destructive) {
                        model.deleteAgentChatSession(model.agentSessionId)
                    }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .menuStyle(.borderlessButton)
            .help("Recent Agent conversations for this project and recent projects")
            .a11yCatalog("ghidra.vibe.agent.history")
            .onAppear { model.refreshAgentChatHistoryLists() }
            Button {
                model.showAgentSetup = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Configure providers, API keys, and local GGUF models")
            .a11yCatalog("ghidra.vibe.agent.setup")
            if model.agentBusy {
                ProgressView()
                    .controlSize(.small)
                Button {
                    model.interruptAgentTurn(keepPartial: true)
                } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .help("Interrupt current turn (⌘Return also interrupts then sends)")
                .a11yCatalog("ghidra.vibe.agent.interrupt")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            ZStack {
                t.vibeContentAlt
                t.vibeForeground.opacity(0.05)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(t.vibeSelection)
                .frame(height: 1)
        }
        .sheet(isPresented: $model.showAgentSetup) {
            NavigationStack {
                AgentSetupPanel()
                    .environment(model)
                    .vibeThemed(themes)
                    .navigationTitle("Agent Setup")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                model.persistAgentAISettings()
                                model.showAgentSetup = false
                            }
                        }
                    }
            }
            .frame(minWidth: 420, minHeight: 560)
        }
    }

    private var historyFromOtherProjects: [AgentChatStore.SessionMeta] {
        let thisKey = AgentChatStore.projectKey(model.projectPath)
        return Array(
            model.agentHistoryRecent
                .filter { AgentChatStore.projectKey($0.projectPath) != thisKey }
                .prefix(12)
        )
    }

    @ViewBuilder
    private func historyRowLabel(_ meta: AgentChatStore.SessionMeta, showProject: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(meta.title)
                    .lineLimit(1)
                if meta.id == model.agentSessionId {
                    Text("· open")
                        .foregroundStyle(Color.vibeSecondary)
                        .font(.caption2)
                }
            }
            Text(
                showProject
                    ? "\(meta.projectDisplayName) · \(meta.updatedAt.formatted(date: .abbreviated, time: .shortened))"
                    : meta.updatedAt.formatted(date: .abbreviated, time: .shortened)
            )
            .font(.caption2)
            .foregroundStyle(Color.vibeSecondary)
            .lineLimit(1)
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VibeChrome.Space.xl) {
                Text("Welcome to GhidraVibe Agent")
                    .font(.title2.weight(.semibold))
                    .a11yCatalog("ghidra.vibe.provider.agent")
                Text(
                    "Configure OpenAI, Anthropic, Google, or any OpenAI-compatible API — or use "
                        + "local Ollama / llama.cpp (drop .gguf into Models). No LLM weights are "
                        + "bundled with GhidraVibe."
                )
                .font(.body)
                Text("Shortcuts")
                    .font(.headline)
                Text("Return sends · Shift+Return newline · ⌘Return send now (queue jump)")
                    .font(.callout)
                    .foregroundStyle(Color.vibeSecondary)
                HStack(spacing: VibeChrome.Space.sm) {
                    Button("Set up models…") { model.showAgentSetup = true }
                        .buttonStyle(.borderedProminent)
                    .tint(Color.vibeAccent)
                        .controlSize(.regular)
                        .help("Pick a provider, API key file, or drop a GGUF")
                    Button("Start chatting") { model.dismissAgentWelcome() }
                        .buttonStyle(.bordered)
                        .tint(Color.vibeAccent)
                        .controlSize(.regular)
                        .help("Dismiss welcome and open the agent composer")
                    Button("Opt out of Agent") { model.optOutAgent() }
                        .controlSize(.regular)
                        .help("Hide Agent panel by default")
                }
            }
            .padding(VibeChrome.Space.xl)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .center, spacing: VibeChrome.Space.md) {
                    ForEach(model.agentMessages) { msg in
                        AgentBubble(message: msg) {
                            model.beginReply(to: msg)
                        }
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, VibeChrome.Space.md)
                .padding(.vertical, VibeChrome.Space.lg)
            }
            .onChange(of: model.agentMessages.count) { _, _ in
                if let last = model.agentMessages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .a11yCatalog("ghidra.vibe.provider.agent.transcript")
    }

    private var toolApprovalBar: some View {
        let t = themes.theme
        return Group {
            if let req = model.agentToolApproval {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(Color.vibeWarning)
                        Text("Allow tool “\(req.toolName)”?")
                            .font(.caption.weight(.bold))
                        Text(req.risk.title.uppercased())
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.vibeWarning.opacity(0.25), in: Capsule())
                        Spacer(minLength: 0)
                    }
                    Text(req.argsPreview)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color.vibeSecondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                    HStack(spacing: 6) {
                        Button("Allow once") {
                            model.resolveAgentToolApproval(.allowOnce)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .a11yCatalog("ghidra.vibe.agent.tool.allow_once")
                        Button("Session") {
                            model.resolveAgentToolApproval(.allowSession)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Allow this tool until GhidraVibe quits")
                        .a11yCatalog("ghidra.vibe.agent.tool.allow_session")
                        Button("Always") {
                            model.resolveAgentToolApproval(.alwaysAllow)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Remember Always Allow for this tool")
                        .a11yCatalog("ghidra.vibe.agent.tool.allow_always")
                        Spacer(minLength: 0)
                        Button("Deny", role: .destructive) {
                            model.resolveAgentToolApproval(.deny)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .a11yCatalog("ghidra.vibe.agent.tool.deny")
                    }
                }
                .padding(.horizontal, VibeChrome.Space.md)
                .padding(.vertical, VibeChrome.Space.sm)
                .background(t.vibeContentAlt)
                .a11yContainerCatalog("ghidra.vibe.agent.tool.approval")
            }
        }
    }

    private var pendingBar: some View {
        HStack(spacing: VibeChrome.Space.sm) {
            Text("\(model.agentPendingEdits.count) pending edit(s)")
                .font(.caption)
            Spacer()
            Button("Apply") { model.applyAgentPendingEdits() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .a11yCatalog("ghidra.vibe.provider.agent.apply")
            Button("Clear") { model.clearAgentPendingEdits() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .a11yCatalog("ghidra.vibe.provider.agent.clear_pending")
        }
        .padding(.horizontal, VibeChrome.Space.md)
        .padding(.vertical, VibeChrome.Space.sm)
    }

    private var queueBar: some View {
        let t = themes.theme
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: VibeChrome.Space.sm) {
                Image(systemName: "tray.full")
                    .font(.caption)
                    .foregroundStyle(t.vibeSecondary)
                Text("\(model.agentSendQueue.count) queued")
                    .font(.caption)
                    .foregroundStyle(t.vibeForeground)
                Spacer()
                Button("Clear queue") { model.clearAgentSendQueue() }
                    .controlSize(.small)
                    .a11yCatalog("ghidra.vibe.provider.agent.clear_queue")
            }
            ForEach(model.agentSendQueue) { item in
                HStack(spacing: 6) {
                    if model.agentInteractionMode.showsQueueLanes {
                        Text(item.lane)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(t.vibeAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(t.vibeAccent.opacity(0.14)))
                            .a11yCatalog("ghidra.vibe.agent.queue_lane")
                    }
                    Text(item.text)
                        .font(.caption2)
                        .foregroundStyle(t.vibeSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        model.removeAgentQueueItem(item.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(t.vibeMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from queue")
                    .a11yCatalog("ghidra.vibe.agent.queue_remove")
                }
            }
        }
        .padding(.horizontal, VibeChrome.Space.md)
        .padding(.vertical, VibeChrome.Space.sm)
        .background(t.vibeContentAlt.opacity(0.85))
    }

    /// Display height: grow with draft, capped at min(20 lines, 20% of Agent sidebar).
    private var composerFieldHeight: CGFloat {
        let cap = AgentComposerField.heightCap(sidebarHeight: agentSidebarHeight)
        return min(max(composerContentHeight, AgentComposerField.minHeight), cap)
    }

    private var composer: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: VibeChrome.Space.sm) {
            // Status + Cursor-style context radial
            HStack(alignment: .center, spacing: VibeChrome.Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.jspaceStatus)
                        .font(.caption2)
                        .foregroundStyle(Color.vibeSecondary)
                    Text("\(model.agentModel.isEmpty ? "(no model)" : model.agentModel)")
                        .font(.caption2)
                        .foregroundStyle(Color.vibeSecondary)
                        .lineLimit(1)
                        .help(model.agentMoELastRoute.isEmpty ? model.agentBaseURL : model.agentMoELastRoute)
                    if !model.agentLastTurnStatus.isEmpty {
                        Text(model.agentLastTurnStatus)
                            .font(.caption2)
                            .foregroundStyle(Color.vibeMuted)
                            .lineLimit(1)
                            .a11yCatalog("ghidra.vibe.provider.agent.last_turn")
                    }
                }
                Spacer(minLength: 4)
                AgentContextRadial(
                    fraction: model.agentContextUsageFraction,
                    used: model.agentContextUsedTokens,
                    window: model.agentContextWindowTokens,
                    renewing: model.agentContextRenewing
                ) {
                    model.renewAgentContext(manual: true)
                }
            }

            if !model.apiBackendAvailable && !model.agentUseLocalOllama {
                Text("API backend disabled (no key file). Enable local Ollama or set a key file.")
                    .font(.caption)
                    .foregroundStyle(Color.vibeWarning)
            }

            if !model.agentContextSummary.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption2)
                    Text("Earlier turns remembered (summary)")
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.vibeSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.vibeContentAlt.opacity(0.9), in: Capsule())
                .help(String(model.agentContextSummary.prefix(1200)))
                .a11yCatalog("ghidra.vibe.provider.agent.memory_chip")
            }

            if let reply = model.agentReplyTo {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.caption)
                        .foregroundStyle(Color.vibeAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replying to \(reply.role == .user ? "you" : "assistant")")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.vibeAccent)
                        Text(reply.replyPreviewLine.isEmpty
                             ? String(reply.text.prefix(120))
                             : reply.replyPreviewLine)
                            .font(.caption2)
                            .foregroundStyle(Color.vibeSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Button {
                        model.clearAgentReply()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.vibeMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel reply")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.vibeAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.vibeAccent.opacity(0.35), lineWidth: 1)
                }
                .a11yCatalog("ghidra.vibe.provider.agent.reply_chip")
            }

            HStack(spacing: VibeChrome.Space.sm) {
                agentActionButton("Index JSpace", id: "ghidra.vibe.provider.agent.index") {
                    model.indexJSpace()
                }
                agentActionButton("Autonomous RE", id: "ghidra.vibe.provider.agent.autonomous_re") {
                    model.runAutonomousREPlaybook()
                }
                .help("Budgeted rename/comment playbook over interesting functions")
                agentActionButton("Improve", id: "ghidra.vibe.provider.agent.improve") {
                    model.queueImproveDecompile(
                        name: model.selectedFunction?.name,
                        address: model.selectedFunction?.address,
                        apply: false
                    )
                }
                .help("Propose readability renames/comments for the selected function")
            }

            if !model.agentAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.agentAttachments) { att in
                            HStack(spacing: 4) {
                                Image(systemName: att.isText ? "doc.text" : "doc")
                                    .font(.caption2)
                                Text(att.chipLabel)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Button {
                                    model.removeAgentAttachment(att.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule(style: .continuous).fill(Color.vibeSelection.opacity(0.16)))
                        }
                    }
                }
                .a11yCatalog("ghidra.vibe.provider.agent.attachments")
            }

            // Expandable entry: [ + | text | send ]. Grows with draft up to
            // min(20 lines, 20% of Agent sidebar); scrolls when content is taller.
            HStack(alignment: .bottom, spacing: 6) {
                Menu {
                    Button("Attach File…") { pickAttachment() }
                    Button("Mention…") { beginMentionFromButton() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.vibeSecondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.vibeSelection.opacity(0.14)))
                }
                .menuStyle(.borderlessButton)
                .help("Attach a file or insert an @ mention")
                .a11yCatalog("ghidra.vibe.provider.agent.plus")

                AgentComposerField(
                    text: $model.agentDraft,
                    insertToken: $insertMentionToken,
                    replaceStart: mentionReplaceStart,
                    placeholder: "Message Agent…  (@ mention · + attach)",
                    autofocus: false,
                    onContentHeightChange: { h in
                        if abs(h - composerContentHeight) > 0.5 {
                            composerContentHeight = h
                        }
                    }
                ) {
                    closeMentionPicker()
                    model.sendAgentMessage(sendNow: false)
                } onSendNow: {
                    closeMentionPicker()
                    model.sendAgentMessage(sendNow: true)
                } onMentionQuery: { active in
                    handleMentionQuery(active)
                }
                .frame(maxWidth: .infinity)
                .frame(height: composerFieldHeight)
                .onChange(of: model.agentDraft) { _, _ in
                    model.refreshAgentContextMeter()
                }

                Button {
                    closeMentionPicker()
                    model.sendAgentMessage(sendNow: false)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.vibeOnAccent)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(
                                (model.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    && model.agentAttachments.isEmpty)
                                    ? Color.vibeSelection.opacity(0.35)
                                    : themes.theme.vibeAccent
                            )
                        )
                }
                .buttonStyle(.plain)
                .disabled(
                    model.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && model.agentAttachments.isEmpty
                )
                .a11yCatalog("ghidra.vibe.provider.agent.send")
                .help("Return sends · Shift+Return newline · ⌘Return send now")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(themes.theme.vibeContent)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(themes.theme.vibeSelection, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .a11yCatalog("ghidra.vibe.provider.agent.composer")
        }
        .padding(.horizontal, VibeChrome.Space.md)
        .padding(.vertical, VibeChrome.Space.sm)
        .onAppear { model.refreshAgentContextMeter() }
    }

    private func beginMentionFromButton() {
        openMentionPicker(replaceStart: (model.agentDraft as NSString).length, filter: "")
        if !model.agentDraft.hasSuffix("@"), !model.agentDraft.isEmpty,
           !model.agentDraft.hasSuffix(" ")
        {
            model.agentDraft += " @"
            mentionReplaceStart = (model.agentDraft as NSString).length - 1
        } else if model.agentDraft.isEmpty || model.agentDraft.hasSuffix(" ") {
            model.agentDraft += "@"
            mentionReplaceStart = (model.agentDraft as NSString).length - 1
        } else if model.agentDraft.hasSuffix("@") {
            mentionReplaceStart = (model.agentDraft as NSString).length - 1
        }
        insertMentionToken = nil
    }

    private func pickAttachment() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Attach files to the next Agent message"
        panel.begin { resp in
            guard resp == .OK else { return }
            for url in panel.urls {
                model.addAgentAttachment(url: url)
            }
        }
    }

    private func handleMentionQuery(_ active: (replaceStart: Int, query: String)?) {
        if let active {
            mentionReplaceStart = active.replaceStart
            mentionFilter = active.query
            if !mentionOpen { mentionOpen = true }
            if mentionCategory == nil, let colon = active.query.firstIndex(of: ":") {
                let catName = String(active.query[..<colon])
                if let cat = AgentMentionCategory.allCases.first(where: {
                    $0.title.compare(catName, options: [.caseInsensitive]) == .orderedSame
                        || $0.rawValue.compare(catName, options: [.caseInsensitive]) == .orderedSame
                }) {
                    mentionCategory = cat
                    mentionFilter = String(active.query[active.query.index(after: colon)...])
                }
            }
        } else if mentionOpen, mentionCategory == nil, mentionFilter.isEmpty {
            closeMentionPicker()
        }
    }

    private func agentActionButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .a11yCatalog(id)
    }

    private func openMentionPicker(replaceStart: Int, filter: String) {
        mentionReplaceStart = replaceStart
        mentionFilter = filter
        mentionCategory = nil
        mentionOpen = true
    }

    private func closeMentionPicker() {
        mentionOpen = false
        mentionCategory = nil
        mentionFilter = ""
    }

    private func applyMention(_ item: AgentMentionItem) {
        if item.token.isEmpty, let cat = AgentMentionCategory.allCases.first(where: { $0.title == item.title }) {
            mentionCategory = cat
            mentionFilter = ""
            return
        }
        insertMentionToken = item.token + " "
        // Side effects for RE context
        if item.token.hasPrefix("@Functions:") {
            let name = String(item.token.dropFirst("@Functions:".count))
            model.selectFunction(name: name, address: nil, id: nil)
        } else if item.token.hasPrefix("@Providers:"),
                  let raw = item.token.split(separator: ":").last,
                  let kind = ProviderKind(rawValue: String(raw))
        {
            model.showProvider(kind)
        } else if item.token == "@Selection", let sel = model.selectedFunction {
            model.selectFunction(name: sel.name, address: sel.address, id: sel.id)
        }
        closeMentionPicker()
    }
}

// MARK: - Bubbles

/// Caps width for wrapping, then hugs the measured content width (iMessage-style trim).
private struct AgentBubbleFitLayout: Layout {
    var maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let cap = min(maxWidth, proposal.width ?? maxWidth)
        // Ideal (often single-line) width — short bubbles stay tight.
        let ideal = child.sizeThatFits(.unspecified)
        if ideal.width <= cap {
            return CGSize(width: max(ideal.width, 0), height: ideal.height)
        }
        // Long content: wrap at the cap.
        let wrapped = child.sizeThatFits(ProposedViewSize(width: cap, height: proposal.height))
        return CGSize(width: cap, height: wrapped.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let child = subviews.first else { return }
        child.place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}

private struct AgentBubble: View {
    @Environment(\.vibeTheme) private var themes
    @Environment(AppModel.self) private var model
    let message: AgentMessage
    var onReply: () -> Void
    @State private var hovered = false

    /// Max bubble body width; opposite edge stays open.
    private static let maxBubbleWidth: CGFloat = 420
    /// Minimum inset on the opposite edge (user → left, agent → right).
    private static let oppositeEdgeTrim: CGFloat = 56

    private var isUser: Bool { message.role == .user }
    private var messageBody: String {
        AgentShare.cleanBody(message.text)
    }
    private var shareText: String {
        AgentShare.formatMessage(message)
    }
    private var canAct: Bool {
        !messageBody.isEmpty && !message.text.hasPrefix("↻ Context renewed")
    }
    private var canReply: Bool { canAct }

    var body: some View {
        let t = themes.theme
        let align: Alignment = isUser ? .trailing : .leading
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if let preview = message.replyPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
               !preview.isEmpty
            {
                HStack(spacing: 4) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.caption2)
                    Text(String(preview.prefix(100)))
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(Color.vibeSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(t.vibeContent.opacity(0.65), in: Capsule())
            }
            AgentBubbleFitLayout(maxWidth: Self.maxBubbleWidth) {
                AgentMarkdownView(
                    text: message.text,
                    isUser: isUser,
                    maxContentWidth: Self.maxBubbleWidth - (VibeChrome.Space.md * 2)
                )
                .padding(.horizontal, VibeChrome.Space.md)
                .padding(.vertical, VibeChrome.Space.sm)
                .background {
                    RoundedRectangle(cornerRadius: VibeChrome.Radius.nestMin, style: .continuous)
                        .fill(isUser ? t.vibeAccent.opacity(0.20) : t.vibeContentAlt)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: VibeChrome.Radius.nestMin, style: .continuous)
                        .strokeBorder(isUser ? t.vibeAccent.opacity(0.35) : t.vibeSelection, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .clipped()
            }
            .a11yCatalog(isUser ? "ghidra.vibe.agent.bubble.user" : "ghidra.vibe.agent.bubble.assistant")
            .contextMenu {
                if canReply {
                    Button("Reply") { onReply() }
                }
                if canAct {
                    Button("Copy Message") {
                        copyMessage()
                    }
                    Button("Share Message…") {
                        AgentShare.presentShareSheet(text: shareText)
                    }
                }
            }

            if canAct {
                HStack(spacing: 6) {
                    if canReply {
                        Button(action: onReply) {
                            Label("Reply", systemImage: "arrowshape.turn.up.left")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(t.vibeAccent)
                        .help("Reply to this message")
                        .a11yCatalog("ghidra.vibe.agent.bubble.reply")
                    }

                    Button(action: copyMessage) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(t.vibeAccent)
                    .help("Copy this message (selection uses ⌘C / Edit → Copy)")
                    .a11yCatalog("ghidra.vibe.agent.bubble.copy")

                    AgentShareButton(text: shareText, helpText: "Share this message")
                        .tint(t.vibeAccent)
                        .a11yCatalog("ghidra.vibe.agent.bubble.share")
                }
                .opacity(hovered ? 1 : 0.92)
            }
        }
        // Pin the hugged bubble to the correct edge; opposite side stays open.
        .frame(maxWidth: .infinity, alignment: align)
        .padding(isUser ? .leading : .trailing, Self.oppositeEdgeTrim)
        .onHover { hovered = $0 }
    }

    private func copyMessage() {
        // Prefer an in-bubble Textual / Text selection when present.
        if model.copyFocusedTextSelection() {
            model.statusMessage = "Copied selection"
            return
        }
        AgentShare.copyToPasteboard(messageBody)
        model.statusMessage = "Message copied"
    }
}

// MARK: - Context radial (Cursor-style)

private struct AgentContextRadial: View {
    var fraction: Double
    var used: Int
    var window: Int
    var renewing: Bool
    var onRenew: () -> Void

    private var pct: Int { Int((fraction * 100).rounded()) }
    private var tint: Color {
        if renewing { return .accentColor }
        if fraction >= AgentContextMeter.autoRenewThreshold { return Color.vibeWarning }
        if fraction >= 0.65 { return Color.vibeWarning.opacity(0.75) }
        return Color.vibeSecondary
    }

    var body: some View {
        Button(action: onRenew) {
            ZStack {
                Circle()
                    .stroke(Color.vibeSelection, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, max(0, fraction))))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if renewing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Text("\(pct)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.vibeSecondary)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(
            renewing
                ? "Renewing context…"
                : "Context ~\(used)/\(window) tokens (\(pct)%). Click to renew/summarize like Cursor."
        )
        .a11yCatalog("ghidra.vibe.provider.agent.context_radial")
    }
}

// MARK: - @ Mention picker

private struct AgentMentionPicker: View {
    @Binding var category: AgentMentionCategory?
    @Binding var filter: String
    var model: AppModel
    var onSelect: (AgentMentionItem) -> Void
    var onDismiss: () -> Void

    private var rows: [AgentMentionItem] {
        if let category {
            return AgentMentions.items(category: category, query: filter, model: model)
        }
        let q = filter.lowercased()
        let roots = AgentMentions.rootItems()
        guard !q.isEmpty else { return roots }
        return roots.filter {
            $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: VibeChrome.Space.sm) {
                if category != nil {
                    Button {
                        category = nil
                        filter = ""
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .help("Back to mention categories")
                }
                Text(category?.title ?? "Mention")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.vibeSecondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
            .padding(.horizontal, VibeChrome.Space.sm)
            .padding(.vertical, VibeChrome.Space.xs)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            HStack(spacing: VibeChrome.Space.sm) {
                                Image(systemName: item.systemImage)
                                    .frame(width: 18)
                                    .foregroundStyle(Color.vibeSecondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.callout)
                                        .foregroundStyle(Color.vibeForeground)
                                        .lineLimit(1)
                                    Text(item.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(Color.vibeSecondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if item.token.isEmpty {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(Color.vibeMuted)
                                }
                            }
                            .padding(.horizontal, VibeChrome.Space.sm)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if rows.isEmpty {
                        Text("No matches")
                            .font(.caption)
                            .foregroundStyle(Color.vibeSecondary)
                            .padding(VibeChrome.Space.md)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .background(VibeChrome.ProviderSurface.control)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(VibeChrome.ProviderSurface.separator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .a11yCatalog("ghidra.vibe.provider.agent.mention_picker")
    }
}

// MARK: - Composer (Return / Shift+Return / ⌘Return)

/// Full text-editing NSTextView: ⌘A/C/X/V/Z even when the app Edit menu is customized.
private final class AgentComposerTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override func paste(_ sender: Any?) {
        // Plain paste keeps mention chip styling under our control.
        pasteAsPlainText(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.option),
              !event.modifierFlags.contains(.control)
        else {
            return super.performKeyEquivalent(with: event)
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let shift = event.modifierFlags.contains(.shift)
        switch key {
        case "a":
            selectAll(nil)
            return true
        case "c":
            copy(nil)
            return true
        case "x":
            cut(nil)
            return true
        case "v":
            paste(nil)
            return true
        case "z":
            if shift {
                if let um = undoManager, um.canRedo {
                    um.redo()
                    return true
                }
            } else if let um = undoManager, um.canUndo {
                um.undo()
                return true
            }
            return false
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

/// NSTextView-backed field so we can own Return vs Shift+Return without fighting SwiftUI TextField.
/// Shows a placeholder when empty; does not steal focus when the Agent sidebar opens.
/// Auto-expands with draft height up to `maxVisibleHeight` (caller: min(20 lines, 20% sidebar)).
private struct AgentComposerField: NSViewRepresentable {
    /// Single-line resting height.
    static let minHeight: CGFloat = 24
    /// Absolute maximum visible lines before scrolling (when sidebar is tall enough).
    static let maxLines: Int = 20

    /// Back-compat alias for callers that still reference the old constant.
    static let preferredHeight: CGFloat = minHeight

    static func lineHeight(font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    /// Cap: never above 20 lines; never above 20% of the Agent sidebar height.
    static func heightCap(sidebarHeight: CGFloat) -> CGFloat {
        let twentyLines = lineHeight() * CGFloat(maxLines) + 4
        let twentyPercent = max(0, sidebarHeight) * 0.20
        return max(minHeight, min(twentyLines, twentyPercent))
    }

    static func measureContentHeight(of tv: NSTextView) -> CGFloat {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return minHeight }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height
        let inset = tv.textContainerInset.height * 2
        // Empty / placeholder still needs one line of chrome.
        return max(minHeight, ceil(used + inset + 2))
    }

    @Binding var text: String
    @Binding var insertToken: String?
    var replaceStart: Int
    var placeholder: String = "Message Agent…"
    /// When false (default), the field is not focused on appear — placeholder stays visible.
    var autofocus: Bool = false
    /// Intrinsic content height (uncapped) so SwiftUI can grow the field up to the sidebar cap.
    var onContentHeightChange: ((CGFloat) -> Void)?
    var onSend: () -> Void
    var onSendNow: () -> Void
    var onMentionQuery: (( (replaceStart: Int, query: String)? ) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            insertToken: $insertToken,
            onSend: onSend,
            onSendNow: onSendNow,
            onMentionQuery: onMentionQuery,
            onContentHeightChange: onContentHeightChange
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        // Nested inside the rounded field — transparent fill.
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.focusRingType = .none
        scroll.wantsLayer = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let tv = AgentComposerTextView()
        tv.delegate = context.coordinator
        // Rich text only for @mention chip runs; paste stays plain via Coordinator.
        tv.isRichText = true
        tv.allowsUndo = true
        tv.isEditable = true
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        let fg = ThemeStore.shared.theme.nsForeground
        tv.textColor = fg
        tv.insertionPointColor = fg
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        tv.font = font
        tv.typingAttributes = [
            .font: font,
            .foregroundColor: fg,
            .backgroundColor: NSColor.clear,
        ]
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.usesAdaptiveColorMappingForDarkAppearance = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if let container = tv.textContainer {
            container.widthTracksTextView = true
            container.heightTracksTextView = false
            container.lineFragmentPadding = 4
            container.containerSize = NSSize(
                width: 0,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        scroll.documentView = tv
        Self.applyPlaceholder(placeholder, to: tv, font: font)
        tv.string = text
        Coordinator.styleMentionRuns(in: tv)
        // Keep caret at end only when there is draft text; empty + no autofocus → show placeholder.
        if !text.isEmpty {
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        }
        context.coordinator.textView = tv
        context.coordinator.scrollView = scroll
        context.coordinator.didResignInitialFocus = autofocus
        context.coordinator.onContentHeightChange = onContentHeightChange
        if !autofocus {
            // SwiftUI often focuses the first text view — resign so the hint stays visible.
            // Run twice: first pass may race window attachment; second catches late focus steal.
            let resign: () -> Void = { [weak scroll, weak tv] in
                guard let scroll, let tv else { return }
                if let window = scroll.window, window.firstResponder === tv {
                    window.makeFirstResponder(nil)
                }
            }
            DispatchQueue.main.async {
                resign()
                context.coordinator.didResignInitialFocus = true
                DispatchQueue.main.async(execute: resign)
            }
        }
        DispatchQueue.main.async {
            context.coordinator.publishContentHeight()
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onSend = onSend
        context.coordinator.onSendNow = onSendNow
        context.coordinator.onMentionQuery = onMentionQuery
        context.coordinator.onContentHeightChange = onContentHeightChange
        context.coordinator.replaceStart = replaceStart
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        guard let tv = scroll.documentView as? NSTextView else { return }
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textColor = ThemeStore.shared.theme.nsForeground
        let font = tv.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        Self.applyPlaceholder(placeholder, to: tv, font: font)
        let width = max(scroll.contentSize.width, 1)
        tv.textContainer?.containerSize = NSSize(
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )

        if let token = insertToken, !token.isEmpty {
            let ns = tv.string as NSString
            let caret = tv.selectedRange().location
            let start = max(0, min(replaceStart, ns.length))
            let end = max(start, min(caret, ns.length))
            let range = NSRange(location: start, length: end - start)
            if tv.shouldChangeText(in: range, replacementString: token) {
                tv.replaceCharacters(in: range, with: token)
                tv.didChangeText()
                Coordinator.styleMentionRuns(in: tv)
                let loc = start + (token as NSString).length
                tv.setSelectedRange(NSRange(location: loc, length: 0))
            }
            DispatchQueue.main.async {
                insertToken = nil
            }
            text = tv.string
            context.coordinator.publishContentHeight()
            return
        }

        if tv.string != text {
            let selected = tv.selectedRange()
            tv.string = text
            Coordinator.styleMentionRuns(in: tv)
            let maxLoc = (tv.string as NSString).length
            if text.isEmpty {
                tv.setSelectedRange(NSRange(location: 0, length: 0))
            } else {
                // Preserve selection length (⌘A) across SwiftUI binding sync.
                let loc = min(selected.location, maxLoc)
                let len = min(selected.length, maxLoc - loc)
                tv.setSelectedRange(NSRange(location: loc, length: len))
            }
        }
        context.coordinator.publishContentHeight()
    }

    private static func applyPlaceholder(_ placeholder: String, to tv: NSTextView, font: NSFont) {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: ThemeStore.shared.theme.nsBase03Color,
            .font: font,
        ]
        // AppKit draws this when the text view is empty (same path as NSTextField placeholder).
        tv.setValue(
            NSAttributedString(string: placeholder, attributes: attrs),
            forKey: "placeholderAttributedString"
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var insertToken: String?
        var replaceStart: Int = 0
        var onSend: () -> Void
        var onSendNow: () -> Void
        var onMentionQuery: (( (replaceStart: Int, query: String)? ) -> Void)?
        var onContentHeightChange: ((CGFloat) -> Void)?
        var didResignInitialFocus = false
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        init(
            text: Binding<String>,
            insertToken: Binding<String?>,
            onSend: @escaping () -> Void,
            onSendNow: @escaping () -> Void,
            onMentionQuery: (( (replaceStart: Int, query: String)? ) -> Void)?,
            onContentHeightChange: ((CGFloat) -> Void)?
        ) {
            _text = text
            _insertToken = insertToken
            self.onSend = onSend
            self.onSendNow = onSendNow
            self.onMentionQuery = onMentionQuery
            self.onContentHeightChange = onContentHeightChange
        }

        func publishContentHeight() {
            guard let tv = textView else { return }
            // Ensure container width matches the scroll viewport before measuring wraps.
            if let scroll = scrollView {
                let width = max(scroll.contentSize.width, 1)
                tv.textContainer?.containerSize = NSSize(
                    width: width,
                    height: CGFloat.greatestFiniteMagnitude
                )
            }
            let h = AgentComposerField.measureContentHeight(of: tv)
            onContentHeightChange?(h)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            Self.styleMentionRuns(in: tv)
            text = tv.string
            publishContentHeight()
            tv.scrollRangeToVisible(tv.selectedRange())
            publishMention(from: tv)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            // Keep paste plain so mention chrome is re-applied, not nested RTF.
            true
        }

        /// Capsule-like accent runs for `@Category:value` / `@Program` / `@Selection`.
        static func styleMentionRuns(in tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            let font = tv.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: ThemeStore.shared.theme.nsForeground, range: full)
            storage.addAttribute(.font, value: font, range: full)
            let pattern = #"(@(?:Functions|Providers|Classes|PastChats|Docs):[^\s@]+|@(?:Selection|Program)\b)"#
            if let re = try? NSRegularExpression(pattern: pattern) {
                let accent = ThemeStore.shared.theme.nsAccent
                let fill = accent.withAlphaComponent(0.16)
                re.enumerateMatches(in: storage.string, options: [], range: full) { match, _, _ in
                    guard let match else { return }
                    storage.addAttribute(.foregroundColor, value: accent, range: match.range)
                    storage.addAttribute(.backgroundColor, value: fill, range: match.range)
                    storage.addAttribute(
                        .font,
                        value: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold),
                        range: match.range
                    )
                }
            }
            storage.endEditing()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            publishMention(from: tv)
        }

        private func publishMention(from tv: NSTextView) {
            let active = AgentMentions.activeMention(
                in: tv.string,
                utf16Offset: tv.selectedRange().location
            )
            onMentionQuery?(active)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Never intercept standard editing (selectAll / delete / move / etc.).
            if commandSelector == #selector(NSResponder.selectAll(_:))
                || commandSelector == #selector(NSText.selectAll(_:))
                || commandSelector == #selector(NSText.copy(_:))
                || commandSelector == #selector(NSText.cut(_:))
                || commandSelector == #selector(NSText.paste(_:))
                || commandSelector == #selector(NSResponder.deleteBackward(_:))
                || commandSelector == #selector(NSResponder.deleteForward(_:))
            {
                return false
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onMentionQuery?(nil)
                return false
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) {
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                    return true
                }
                if flags.contains(.command) {
                    onSendNow()
                    return true
                }
                onSend()
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                onSendNow()
                return true
            }
            return false
        }
    }
}
