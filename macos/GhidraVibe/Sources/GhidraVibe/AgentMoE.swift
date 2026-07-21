import Foundation

/// RE-oriented Mixture of Experts — route Agent turns to the best local model,
/// with optional proprietary API escalation. Not a neural MoE layer; a task router
/// over OpenAI-compatible endpoints (Ollama Metal + opt-in cloud).
enum AgentExpertRole: String, CaseIterable, Identifiable, Sendable {
    /// Tool-calling chat / orchestration.
    case general
    /// Rename, symbols, xrefs, listing edits.
    case code
    /// Decompile readability / improve_decompile.
    case decompile
    /// ObjC / Swift / SwiftUI naming & idioms.
    case apple
    /// Long Autonomous RE / batch planning.
    case plan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .code: "Code / rename"
        case .decompile: "Decompile"
        case .apple: "ObjC / Swift"
        case .plan: "Plan / Autonomous RE"
        }
    }

    var hint: String {
        switch self {
        case .general: "Tool loop, navigation, Q&A"
        case .code: "Renames, comments, xrefs"
        case .decompile: "Readability rewrites"
        case .apple: "ObjC/Swift/SwiftUI idioms"
        case .plan: "Budgeted playbooks"
        }
    }

    /// Env override for this expert's model id.
    var envKey: String {
        switch self {
        case .general: "GHIDRA_VIBE_AI_MODEL_GENERAL"
        case .code: "GHIDRA_VIBE_AI_MODEL_CODE"
        case .decompile: "GHIDRA_VIBE_AI_MODEL_DECOMPILE"
        case .apple: "GHIDRA_VIBE_AI_MODEL_APPLE"
        case .plan: "GHIDRA_VIBE_AI_MODEL_PLAN"
        }
    }

    var defaultsKey: String { "ghidra.vibe.agent.moe.\(rawValue)" }
}

struct AgentMoESettings: Sendable, Equatable {
    /// When true, pick expert models by task; when false, always use `agentModel`.
    var enabled: Bool = true
    /// Allow falling back to proprietary API when local fails or user asks for cloud.
    var allowCloudEscalation: Bool = false
    /// Per-role model ids (empty = inherit default agent model).
    var models: [AgentExpertRole: String] = [:]

    static func load(
        env: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        fallbackModel: String
    ) -> AgentMoESettings {
        var s = AgentMoESettings()
        if defaults.object(forKey: "ghidra.vibe.agent.moe.enabled") != nil {
            s.enabled = defaults.bool(forKey: "ghidra.vibe.agent.moe.enabled")
        } else if let e = env["GHIDRA_VIBE_AI_MOE"] {
            s.enabled = e != "0"
        }
        if defaults.object(forKey: "ghidra.vibe.agent.moe.cloudEscalation") != nil {
            s.allowCloudEscalation = defaults.bool(forKey: "ghidra.vibe.agent.moe.cloudEscalation")
        } else {
            s.allowCloudEscalation = env["GHIDRA_VIBE_AI_MOE_CLOUD"] == "1"
        }
        for role in AgentExpertRole.allCases {
            let fromDefaults = defaults.string(forKey: role.defaultsKey)?.nilIfEmpty
            let fromEnv = env[role.envKey]?.nilIfEmpty
            s.models[role] = fromDefaults ?? fromEnv ?? ""
        }
        // Sensible local defaults when unset — still overridable.
        if (s.models[.code] ?? "").isEmpty { s.models[.code] = fallbackModel }
        if (s.models[.general] ?? "").isEmpty { s.models[.general] = fallbackModel }
        if (s.models[.decompile] ?? "").isEmpty {
            s.models[.decompile] = env["GHIDRA_VIBE_AI_MODEL_DECOMPILE"]?.nilIfEmpty
                ?? fallbackModel
        }
        if (s.models[.apple] ?? "").isEmpty {
            s.models[.apple] = env["GHIDRA_VIBE_AI_MODEL_APPLE"]?.nilIfEmpty ?? fallbackModel
        }
        if (s.models[.plan] ?? "").isEmpty {
            s.models[.plan] = env["GHIDRA_VIBE_AI_MODEL_PLAN"]?.nilIfEmpty ?? fallbackModel
        }
        return s
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: "ghidra.vibe.agent.moe.enabled")
        defaults.set(allowCloudEscalation, forKey: "ghidra.vibe.agent.moe.cloudEscalation")
        for role in AgentExpertRole.allCases {
            defaults.set(models[role] ?? "", forKey: role.defaultsKey)
        }
    }

    func model(for role: AgentExpertRole, fallback: String) -> String {
        let m = (models[role] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? fallback : m
    }
}

struct AgentMoERoute: Sendable {
    var role: AgentExpertRole
    var config: LocalAIConfig
    var reason: String
    var escalatedToCloud: Bool
}

enum AgentMoERouter {
    /// Classify user text (+ light context) into an expert role.
    static func classify(
        userText: String,
        selectedFunctionName: String? = nil,
        force: AgentExpertRole? = nil
    ) -> (AgentExpertRole, String) {
        if let force { return (force, "forced") }
        let t = userText.lowercased()
        let fn = (selectedFunctionName ?? "").lowercased()

        if t.contains("autonomous") || (t.contains("batch") && t.contains("rename"))
            || t.contains("playbook") || t.contains("whole program")
        {
            return (.plan, "autonomous/batch")
        }
        if t.contains("improve") || t.contains("readab") || t.contains("decompile")
            || t.contains("pseudocode") || t.contains("make this clearer")
        {
            return (.decompile, "decompile/readability")
        }
        if t.contains("objc") || t.contains("swiftui") || t.contains("swift ")
            || t.contains("nsobject") || t.contains("uiview") || t.contains("@objc")
            || fn.hasPrefix("-[") || fn.hasPrefix("+[") || fn.hasPrefix("$s")
        {
            return (.apple, "objc/swift")
        }
        if t.contains("rename") || t.contains("symbol") || t.contains("xref")
            || t.contains("cross-ref") || t.contains("comment") || t.contains("label")
        {
            return (.code, "rename/symbols")
        }
        return (.general, "default")
    }

    /// Build the config for a classified expert. Cloud escalation only when allowed
    /// and (preferCloud / escalate keyword / local unavailable path).
    static func route(
        userText: String,
        moe: AgentMoESettings,
        base: LocalAIConfig,
        selectedFunctionName: String? = nil,
        force: AgentExpertRole? = nil,
        preferCloud: Bool = false
    ) -> AgentMoERoute {
        let (role, why) = classify(
            userText: userText,
            selectedFunctionName: selectedFunctionName,
            force: force
        )

        let wantsCloud = preferCloud
            || userText.lowercased().contains("use cloud")
            || userText.lowercased().contains("use api")
            || userText.lowercased().contains("gpt-")
            || userText.lowercased().contains("claude")

        var cfg = base
        var escalated = false

        if moe.enabled {
            let expertModel = moe.model(for: role, fallback: base.model)
            cfg.model = expertModel
        }

        if wantsCloud && moe.allowCloudEscalation && base.apiKey != nil {
            let cloud = LocalAIConfig.resolve(
                provider: .openai,
                userBaseURL: nil,
                userModel: moe.enabled ? moe.model(for: role, fallback: base.model) : base.model,
                apiKeyFile: nil,
                preferCloud: true
            )
            // Preserve key from base if resolve didn't re-read file.
            cfg = LocalAIConfig(
                baseURL: cloud.baseURL,
                model: cloud.model,
                apiKey: base.apiKey ?? cloud.apiKey,
                backend: cloud.backend,
                provider: cloud.provider
            )
            escalated = true
        }

        return AgentMoERoute(
            role: role,
            config: cfg,
            reason: why,
            escalatedToCloud: escalated
        )
    }

    /// Retry helper: same messages on cloud expert when local failed and escalation is on.
    static func cloudFallback(
        moe: AgentMoESettings,
        role: AgentExpertRole,
        local: LocalAIConfig
    ) -> LocalAIConfig? {
        guard moe.allowCloudEscalation, let key = local.apiKey, !key.isEmpty else { return nil }
        let cloud = LocalAIConfig.resolve(
            provider: .openai,
            userModel: moe.model(for: role, fallback: local.model),
            preferCloud: true
        )
        return LocalAIConfig(
            baseURL: cloud.baseURL,
            model: cloud.model,
            apiKey: key,
            backend: cloud.backend,
            provider: cloud.provider
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
