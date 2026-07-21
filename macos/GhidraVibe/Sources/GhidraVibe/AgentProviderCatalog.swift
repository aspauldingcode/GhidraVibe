import Foundation

/// Auth style for proprietary / local OpenAI-compatible gateways.
enum AgentAuthStyle: String, Codable, Sendable {
    case none
    case bearer
    case anthropicKey = "x-api-key"
    case googleQuery = "google_query"
}

/// First-class + generic providers. Minor vendors use `.openaiCompat` with a custom base URL.
enum AgentProviderKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case ollama
    case llamaCpp = "llamacpp"
    case openai
    case anthropic
    case google
    case openaiCompat = "openai_compat"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ollama: "Ollama (local)"
        case .llamaCpp: "llama.cpp (GGUF)"
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .google: "Google Gemini"
        case .openaiCompat: "OpenAI-compatible"
        }
    }

    var subtitle: String {
        switch self {
        case .ollama: "Metal / local tags — no weights in the app"
        case .llamaCpp: "Drop .gguf into Models folder → llama-server"
        case .openai: "api.openai.com"
        case .anthropic: "api.anthropic.com"
        case .google: "generativelanguage.googleapis.com"
        case .openaiCompat: "DeepSeek, Groq, Mistral, Together, OpenRouter, …"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .ollama: "http://127.0.0.1:11434"
        case .llamaCpp: "http://127.0.0.1:8080"
        case .openai: "https://api.openai.com"
        case .anthropic: "https://api.anthropic.com"
        case .google: "https://generativelanguage.googleapis.com"
        case .openaiCompat: "https://api.openai.com"
        }
    }

    var defaultModel: String {
        switch self {
        case .ollama: "qwen2.5-coder:3b"
        case .llamaCpp: ""
        case .openai: "gpt-4o-mini"
        case .anthropic: "claude-sonnet-4-20250514"
        case .google: "gemini-2.0-flash"
        case .openaiCompat: "gpt-4o-mini"
        }
    }

    var auth: AgentAuthStyle {
        switch self {
        case .ollama, .llamaCpp: .none
        case .openai, .openaiCompat: .bearer
        case .anthropic: .anthropicKey
        case .google: .googleQuery
        }
    }

    var needsKeyFile: Bool {
        switch self {
        case .ollama, .llamaCpp: false
        default: true
        }
    }

    /// Suggested model ids for the simplified picker (not a live catalog).
    var suggestedModels: [String] {
        switch self {
        case .ollama:
            [
                "qwen2.5-coder:3b", "qwen2.5-coder:7b", "qwen2.5-coder:1.5b",
                "llama3.2:3b", "llama3.2:1b", "gemma3:4b", "gemma3:1b",
            ]
        case .llamaCpp: []
        case .openai: ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "o4-mini"]
        case .anthropic: [
            "claude-sonnet-4-20250514", "claude-opus-4-20250514", "claude-haiku-4-5-20251001",
        ]
        case .google: ["gemini-2.0-flash", "gemini-2.5-flash", "gemini-2.5-pro"]
        case .openaiCompat: ["gpt-4o-mini", "deepseek-chat", "llama-3.3-70b-versatile"]
        }
    }

    static func from(raw: String?) -> AgentProviderKind {
        guard let raw, let v = AgentProviderKind(rawValue: raw.lowercased()) else { return .ollama }
        return v
    }
}

/// Named OpenAI-compatible gateways (minor APIs) — only base URL + default model differ.
struct AgentOpenAICompatPreset: Identifiable, Sendable {
    let id: String
    let title: String
    let baseURL: String
    let defaultModel: String

    static let all: [AgentOpenAICompatPreset] = [
        .init(id: "openrouter", title: "OpenRouter", baseURL: "https://openrouter.ai/api", defaultModel: "openrouter/auto"),
        .init(id: "groq", title: "Groq", baseURL: "https://api.groq.com/openai", defaultModel: "llama-3.3-70b-versatile"),
        .init(id: "deepseek", title: "DeepSeek", baseURL: "https://api.deepseek.com", defaultModel: "deepseek-chat"),
        .init(id: "mistral", title: "Mistral", baseURL: "https://api.mistral.ai", defaultModel: "mistral-small-latest"),
        .init(id: "together", title: "Together", baseURL: "https://api.together.xyz", defaultModel: "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo"),
        .init(id: "fireworks", title: "Fireworks", baseURL: "https://api.fireworks.ai/inference", defaultModel: "accounts/fireworks/models/llama-v3p1-8b-instruct"),
        .init(id: "custom", title: "Custom base URL", baseURL: "https://api.openai.com", defaultModel: "gpt-4o-mini"),
    ]
}
