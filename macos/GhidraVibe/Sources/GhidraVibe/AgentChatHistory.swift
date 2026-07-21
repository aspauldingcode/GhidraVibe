import Foundation

/// Durable Agent conversations under Application Support, keyed by Ghidra project path.
enum AgentChatStore {
    static let directoryName = "agent-chats"
    static let indexName = "index.json"
    static let maxSessions = 80
    static let maxMessagesPerSession = 400

    struct PersistedMessage: Codable, Hashable, Sendable {
        var id: UUID
        var role: String
        var text: String
        var replyToId: UUID?
        var replyPreview: String?

        init(
            id: UUID = UUID(),
            role: String,
            text: String,
            replyToId: UUID? = nil,
            replyPreview: String? = nil
        ) {
            self.id = id
            self.role = role
            self.text = text
            self.replyToId = replyToId
            self.replyPreview = replyPreview
        }

        init(_ msg: AgentMessage) {
            self.id = msg.id
            self.role = msg.role.rawValue
            self.text = msg.text
            self.replyToId = msg.replyToId
            self.replyPreview = msg.replyPreview
        }

        func toAgentMessage() -> AgentMessage {
            let role: AgentMessage.Role = (self.role == "user") ? .user : .assistant
            return AgentMessage(
                id: id,
                role: role,
                text: text,
                replyToId: replyToId,
                replyPreview: replyPreview,
                meta: nil
            )
        }
    }

    struct SessionMeta: Codable, Identifiable, Hashable, Sendable {
        var id: UUID
        var projectPath: String
        var programName: String
        var title: String
        var preview: String
        var messageCount: Int
        var createdAt: Date
        var updatedAt: Date
        /// Persisted interaction mode (ask/agent/plan/debug/multitask).
        var interactionMode: String?
        /// Last model id used in this session.
        var model: String?

        var projectDisplayName: String {
            if projectPath.isEmpty { return "No project" }
            return URL(fileURLWithPath: projectPath).deletingPathExtension().lastPathComponent
        }
    }

    struct Session: Codable, Identifiable, Sendable {
        var id: UUID
        var projectPath: String
        var programName: String
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var summary: String
        var messages: [PersistedMessage]
        /// Turns dropped from the live transcript by context renew (kept for History / @PastChats).
        var archivedMessages: [PersistedMessage]
        var interactionMode: String?
        var model: String?
        var plan: AgentPlan?

        var meta: SessionMeta {
            SessionMeta(
                id: id,
                projectPath: projectPath,
                programName: programName,
                title: title,
                preview: Self.makePreview(messages: messages),
                messageCount: messages.count + archivedMessages.count,
                createdAt: createdAt,
                updatedAt: updatedAt,
                interactionMode: interactionMode,
                model: model
            )
        }

        static func makePreview(messages: [PersistedMessage]) -> String {
            guard let last = messages.last else { return "" }
            let line = last.text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? last.text
            return String(line.prefix(120))
        }

        static func makeTitle(from messages: [PersistedMessage]) -> String {
            if let firstUser = messages.first(where: { $0.role == "user" }) {
                let line = firstUser.text
                    .split(separator: "\n", maxSplits: 1)
                    .first
                    .map(String.init) ?? firstUser.text
                let clipped = String(line.prefix(48))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !clipped.isEmpty { return clipped }
            }
            return "New chat"
        }
    }

    struct Index: Codable, Sendable {
        var sessions: [SessionMeta]
        /// Last open session id per project key (empty string = no project).
        var activeByProject: [String: String]
    }

    /// `~/Library/Application Support/GhidraVibe/agent-chats`
    static var rootDirectory: URL {
        if let env = ProcessInfo.processInfo.environment["GHIDRA_VIBE_AGENT_CHATS_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty
        {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("GhidraVibe", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static var sessionsDirectory: URL {
        rootDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    static var indexURL: URL {
        rootDirectory.appendingPathComponent(indexName)
    }

    static func projectKey(_ projectPath: String) -> String {
        projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    static func ensureDirectory() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        return rootDirectory
    }

    static func loadIndex() -> Index {
        guard let data = try? Data(contentsOf: indexURL),
              let idx = try? decoder.decode(Index.self, from: data)
        else {
            return Index(sessions: [], activeByProject: [:])
        }
        return idx
    }

    static func saveIndex(_ index: Index) {
        _ = try? ensureDirectory()
        var idx = index
        idx.sessions.sort { $0.updatedAt > $1.updatedAt }
        if idx.sessions.count > maxSessions {
            let drop = Array(idx.sessions.suffix(from: maxSessions))
            idx.sessions = Array(idx.sessions.prefix(maxSessions))
            for meta in drop {
                try? FileManager.default.removeItem(at: sessionURL(meta.id))
            }
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(idx) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    static func sessionURL(_ id: UUID) -> URL {
        sessionsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    static func loadSession(_ id: UUID) -> Session? {
        guard let data = try? Data(contentsOf: sessionURL(id)),
              let session = try? decoder.decode(Session.self, from: data)
        else { return nil }
        return session
    }

    static func saveSession(_ session: Session) {
        _ = try? ensureDirectory()
        var s = session
        s.updatedAt = Date()
        if s.title == "New chat" || s.title.isEmpty {
            s.title = Session.makeTitle(from: s.messages)
        }
        if s.messages.count > maxMessagesPerSession {
            let overflow = s.messages.prefix(s.messages.count - maxMessagesPerSession)
            s.archivedMessages.append(contentsOf: overflow)
            s.messages = Array(s.messages.suffix(maxMessagesPerSession))
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(s) else { return }
        try? data.write(to: sessionURL(s.id), options: .atomic)

        var idx = loadIndex()
        let meta = s.meta
        idx.sessions.removeAll { $0.id == s.id }
        idx.sessions.insert(meta, at: 0)
        idx.activeByProject[projectKey(s.projectPath)] = s.id.uuidString
        saveIndex(idx)
    }

    static func deleteSession(_ id: UUID) {
        try? FileManager.default.removeItem(at: sessionURL(id))
        var idx = loadIndex()
        idx.sessions.removeAll { $0.id == id }
        for (key, value) in idx.activeByProject where value == id.uuidString {
            idx.activeByProject.removeValue(forKey: key)
        }
        saveIndex(idx)
    }

    static func recentSessions(limit: Int = 24) -> [SessionMeta] {
        Array(loadIndex().sessions.prefix(limit))
    }

    static func sessions(forProject path: String, limit: Int = 24) -> [SessionMeta] {
        let key = projectKey(path)
        return Array(
            loadIndex().sessions
                .filter { projectKey($0.projectPath) == key }
                .prefix(limit)
        )
    }

    static func latestSession(forProject path: String) -> SessionMeta? {
        sessions(forProject: path, limit: 1).first
    }

    static func activeSessionId(forProject path: String) -> UUID? {
        let key = projectKey(path)
        guard let raw = loadIndex().activeByProject[key],
              let id = UUID(uuidString: raw)
        else { return nil }
        return id
    }

    static func setActiveSession(_ id: UUID?, forProject path: String) {
        var idx = loadIndex()
        let key = projectKey(path)
        if let id {
            idx.activeByProject[key] = id.uuidString
        } else {
            idx.activeByProject.removeValue(forKey: key)
        }
        saveIndex(idx)
    }

    /// Decode index with flexible dates (ISO8601 ± fractional seconds).
    private static var decoder: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let d = ISO8601DateFormatter().date(from: raw) { return d }
            let frac = ISO8601DateFormatter()
            frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = frac.date(from: raw) { return d }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date: \(raw)"
            )
        }
        return dec
    }

    static func newSession(projectPath: String, programName: String) -> Session {
        let now = Date()
        return Session(
            id: UUID(),
            projectPath: projectPath,
            programName: programName,
            title: "New chat",
            createdAt: now,
            updatedAt: now,
            summary: "",
            messages: [],
            archivedMessages: [],
            interactionMode: AgentInteractionMode.agent.rawValue,
            model: nil,
            plan: nil
        )
    }
}
