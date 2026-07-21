import Foundation

/// Risk tier for Agent tools (Cursor-style permission buckets).
enum AgentToolRisk: String, CaseIterable, Codable, Sendable {
    case read
    case navigate
    case mutate
    case network

    var title: String {
        switch self {
        case .read: "Read"
        case .navigate: "Navigate"
        case .mutate: "Write"
        case .network: "Network"
        }
    }

    var subtitle: String {
        switch self {
        case .read: "Inspect program / GUI state"
        case .navigate: "Change selection or panes"
        case .mutate: "Rename, comment, index, playbooks"
        case .network: "Public web research"
        }
    }
}

/// Persisted / session decision for a tool (or risk tier key).
enum AgentToolPermission: String, Codable, Sendable {
    case ask
    case allowSession
    case alwaysAllow
    case alwaysDeny

    var title: String {
        switch self {
        case .ask: "Ask every time"
        case .allowSession: "Allow for session"
        case .alwaysAllow: "Always allow"
        case .alwaysDeny: "Always deny"
        }
    }
}

/// Default profile for how new tools are gated.
enum AgentToolPermissionProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Every tool prompts (except already Always Allow).
    case askEveryTime
    /// Reads auto-run; writes / network ask (Cursor-like default).
    case askWrites
    /// Allow everything for this app session (still respects Always Deny).
    case allowSession
    /// Persist Always Allow for all tools.
    case allowAlways

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askEveryTime: "Ask every time"
        case .askWrites: "Allow reads · ask writes"
        case .allowSession: "Allow for session"
        case .allowAlways: "Always allow all"
        }
    }

    var subtitle: String {
        switch self {
        case .askEveryTime: "Approve each tool call"
        case .askWrites: "Reads free; writes & network need approval"
        case .allowSession: "No prompts until quit (deny list still applies)"
        case .allowAlways: "Remember allow for every tool"
        }
    }
}

/// User choice from the approval card.
enum AgentToolUserDecision: String, Sendable {
    case allowOnce
    case allowSession
    case alwaysAllow
    case deny
}

enum AgentToolGateResult: Sendable {
    case allow
    case deny(String)
    case ask
}

/// Pending approval shown in the Agent sidebar while the tool loop is paused.
struct AgentToolApprovalRequest: Identifiable, Sendable {
    let id: UUID
    let toolName: String
    let risk: AgentToolRisk
    let argsPreview: String
}

/// Cursor-like tool permissions + optional sandbox for Agent tool calling.
@MainActor
final class AgentToolPermissionStore {
    static let shared = AgentToolPermissionStore()

    private static let profileKey = "ghidra.vibe.agent.tool.profile"
    private static let sandboxKey = "ghidra.vibe.agent.tool.sandbox"
    private static let alwaysKey = "ghidra.vibe.agent.tool.always"

    /// Profile drives defaults when no per-tool override exists.
    var profile: AgentToolPermissionProfile {
        didSet { UserDefaults.standard.set(profile.rawValue, forKey: Self.profileKey) }
    }

    /// When on: network host allowlist + treat dangerous gui_action ids as mutate.
    var sandboxEnabled: Bool {
        didSet { UserDefaults.standard.set(sandboxEnabled, forKey: Self.sandboxKey) }
    }

    /// Session-scoped allow/deny (cleared on reset / app quit naturally).
    private(set) var session: [String: AgentToolPermission] = [:]

    /// Persisted Always Allow / Always Deny per tool name.
    private(set) var always: [String: AgentToolPermission] = [:]

    /// gui_action ids that mutate state — sandbox promotes them to `.mutate`.
    nonisolated static let sandboxMutatingActionIds: Set<String> = [
        "auto_analyze", "save_program", "save", "import_file", "import_apple",
        "open_app_bundle", "open_framework_from_dsc", "open_shared_cache",
        "open_debugger", "open_emulator", "listing_clear_code", "listing_disassemble",
        "listing_define_data", "listing_create_label", "listing_create_function",
        "listing_create_structure", "listing_add_bookmark", "edit_cut", "edit_paste",
        "vc_checkin", "vc_checkout", "vc_add", "vc_undo",
    ]

    nonisolated static let networkAllowHosts: Set<String> = [
        "api.duckduckgo.com",
        "duckduckgo.com",
        "html.duckduckgo.com",
        "en.wikipedia.org",
        "wikipedia.org",
    ]

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.profileKey) ?? ""
        profile = AgentToolPermissionProfile(rawValue: raw) ?? .askWrites
        if UserDefaults.standard.object(forKey: Self.sandboxKey) == nil {
            sandboxEnabled = true
        } else {
            sandboxEnabled = UserDefaults.standard.bool(forKey: Self.sandboxKey)
        }
        always = Self.loadAlwaysMap()
    }

    nonisolated static func risk(forTool name: String, args: [String: Any] = [:]) -> AgentToolRisk {
        switch name {
        case "web_search":
            return .network
        case "rename_function", "set_comment", "rag_index",
             "improve_decompile", "autonomous_re":
            return .mutate
        case "gui_navigate", "gui_select_function":
            return .navigate
        case "gui_action":
            let id = ((args["id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if sandboxMutatingActionIds.contains(id) { return .mutate }
            return .navigate
        default:
            return .read
        }
    }

    func evaluate(tool name: String, args: [String: Any] = [:]) -> AgentToolGateResult {
        let risk = Self.risk(forTool: name, args: args)
        if let always = always[name] {
            switch always {
            case .alwaysAllow: return .allow
            case .alwaysDeny: return .deny("Always deny — \(name)")
            case .ask, .allowSession: break
            }
        }
        if let session = session[name] {
            switch session {
            case .allowSession, .alwaysAllow: return .allow
            case .alwaysDeny: return .deny("Denied for this session — \(name)")
            case .ask: return .ask
            }
        }
        // Profile defaults.
        switch profile {
        case .askEveryTime:
            return .ask
        case .askWrites:
            switch risk {
            case .read, .navigate: return .allow
            case .mutate, .network: return .ask
            }
        case .allowSession:
            return .allow
        case .allowAlways:
            return .allow
        }
    }

    func record(tool name: String, decision: AgentToolUserDecision) {
        switch decision {
        case .allowOnce:
            break
        case .allowSession:
            session[name] = .allowSession
        case .alwaysAllow:
            always[name] = .alwaysAllow
            session[name] = .alwaysAllow
            persistAlways()
        case .deny:
            // One-shot deny for this call only (does not persist).
            break
        }
    }

    /// Persist Always Allow for every known tool (Allow always profile).
    func applyAllowAlwaysProfile() {
        for name in AgentTools.knownToolNames {
            always[name] = .alwaysAllow
        }
        persistAlways()
    }

    func setAlwaysDeny(tool name: String) {
        always[name] = .alwaysDeny
        session[name] = .alwaysDeny
        persistAlways()
    }

    func resetPermissions() {
        session.removeAll()
        always.removeAll()
        persistAlways()
        profile = .askWrites
        sandboxEnabled = true
    }

    func summaryLines() -> [String] {
        var lines: [String] = []
        lines.append("Profile: \(profile.title)")
        lines.append("Sandbox: \(sandboxEnabled ? "on" : "off")")
        let alwaysAllow = always.filter { $0.value == .alwaysAllow }.map(\.key).sorted()
        let alwaysDeny = always.filter { $0.value == .alwaysDeny }.map(\.key).sorted()
        let sessionAllow = session.filter {
            $0.value == .allowSession || $0.value == .alwaysAllow
        }.map(\.key).sorted()
        if !alwaysAllow.isEmpty {
            lines.append("Always allow: \(alwaysAllow.joined(separator: ", "))")
        }
        if !alwaysDeny.isEmpty {
            lines.append("Always deny: \(alwaysDeny.joined(separator: ", "))")
        }
        if !sessionAllow.isEmpty {
            lines.append("Session allow: \(sessionAllow.joined(separator: ", "))")
        }
        if alwaysAllow.isEmpty, alwaysDeny.isEmpty, sessionAllow.isEmpty {
            lines.append("No remembered tool permissions")
        }
        return lines
    }

    func controlState() -> [String: Any] {
        [
            "profile": profile.rawValue,
            "sandbox": sandboxEnabled,
            "alwaysAllow": always.filter { $0.value == .alwaysAllow }.map(\.key).sorted(),
            "alwaysDeny": always.filter { $0.value == .alwaysDeny }.map(\.key).sorted(),
            "sessionAllow": session.filter {
                $0.value == .allowSession || $0.value == .alwaysAllow
            }.map(\.key).sorted(),
        ]
    }

    private func persistAlways() {
        let raw = always.mapValues(\.rawValue)
        UserDefaults.standard.set(raw, forKey: Self.alwaysKey)
    }

    private static func loadAlwaysMap() -> [String: AgentToolPermission] {
        guard let raw = UserDefaults.standard.dictionary(forKey: alwaysKey) as? [String: String]
        else { return [:] }
        var out: [String: AgentToolPermission] = [:]
        for (k, v) in raw {
            if let p = AgentToolPermission(rawValue: v), p == .alwaysAllow || p == .alwaysDeny {
                out[k] = p
            }
        }
        return out
    }

    nonisolated static func argsPreview(_ args: [String: Any], limit: Int = 280) -> String {
        guard JSONSerialization.isValidJSONObject(args),
              let data = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return String(text.prefix(limit))
    }
}
