import Foundation

/// LLM backend kinds — mirrors dendritic `chat` CLI (Metal Ollama OpenAI-compat).
enum AgentLLMBackendKind: String, CaseIterable, Sendable {
    case ollama
    case openaiCompat = "openai_compat"
    case anemllStub = "anemll_stub"
}

struct LocalAIConfig: Sendable {
    var baseURL: URL
    var model: String
    var apiKey: String?
    var backend: AgentLLMBackendKind

    /// Resolve like dendritic local-ai-cli:
    /// `GHIDRA_VIBE_AI_BASE_URL` → `AI_LOCAL_BASE_URL` → `OLLAMA_HOST` → `http://127.0.0.1:11434`
    static func resolve(
        env: [String: String] = ProcessInfo.processInfo.environment,
        userBaseURL: String? = nil,
        userModel: String? = nil,
        apiKeyFile: String? = nil,
        preferCloud: Bool = false
    ) -> LocalAIConfig {
        let keyPath = (apiKeyFile ?? env["GHIDRA_VIBE_API_KEY_FILE"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var apiKey: String?
        if !keyPath.isEmpty, let data = try? String(contentsOfFile: keyPath, encoding: .utf8) {
            apiKey = data.trimmingCharacters(in: .whitespacesAndNewlines)
            if apiKey?.isEmpty == true { apiKey = nil }
        }

        let anemll = (env["GHIDRA_VIBE_AI_BACKEND"] ?? "").lowercased()
        if anemll == "anemll" || anemll == "anemll_stub" || anemll == "npu" {
            return LocalAIConfig(
                baseURL: URL(string: "http://127.0.0.1:0")!,
                model: "anemll-stub",
                apiKey: nil,
                backend: .anemllStub
            )
        }

        if preferCloud || (apiKey != nil && (env["GHIDRA_VIBE_AI_CLOUD"] == "1")) {
            let cloudBase = env["GHIDRA_VIBE_AI_CLOUD_BASE_URL"]
                ?? env["OPENAI_BASE_URL"]
                ?? "https://api.openai.com"
            let model = userModel?.nilIfEmpty
                ?? env["GHIDRA_VIBE_AI_MODEL"]?.nilIfEmpty
                ?? env["OPENAI_MODEL"]?.nilIfEmpty
                ?? "gpt-4o-mini"
            return LocalAIConfig(
                baseURL: URL(string: cloudBase.trimmingSlash()) ?? URL(string: "https://api.openai.com")!,
                model: model,
                apiKey: apiKey,
                backend: .openaiCompat
            )
        }

        let rawBase = userBaseURL?.nilIfEmpty
            ?? env["GHIDRA_VIBE_AI_BASE_URL"]?.nilIfEmpty
            ?? env["AI_LOCAL_BASE_URL"]?.nilIfEmpty
            ?? env["OLLAMA_HOST"]?.nilIfEmpty
            ?? "http://127.0.0.1:11434"
        let model = userModel?.nilIfEmpty
            ?? env["GHIDRA_VIBE_AI_MODEL"]?.nilIfEmpty
            ?? env["AI_LOCAL_DEFAULT_MODEL"]?.nilIfEmpty
            ?? "qwen2.5-coder:3b"
        return LocalAIConfig(
            baseURL: URL(string: rawBase.trimmingSlash()) ?? URL(string: "http://127.0.0.1:11434")!,
            model: model,
            apiKey: apiKey,
            backend: .ollama
        )
    }
}

struct LocalAIChatMessage: Sendable {
    var role: String
    var content: String?
    var toolCallId: String?
    var name: String?
    var toolCalls: [LocalAIToolCall]?
}

struct LocalAIToolCall: Sendable {
    var id: String
    var name: String
    var argumentsJSON: String
}

struct LocalAIChatResult: Sendable {
    var content: String?
    var toolCalls: [LocalAIToolCall]
    var finishReason: String?
    var rawBackend: AgentLLMBackendKind
}

/// OpenAI-compatible chat client used by the Agent sidebar (same contract as dendritic `chat`).
enum LocalAIClient {
    static func listModels(config: LocalAIConfig) async -> [String] {
        switch config.backend {
        case .anemllStub:
            return []
        case .ollama:
            guard let url = URL(string: "/api/tags", relativeTo: config.baseURL)?.absoluteURL else {
                return []
            }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 8
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = obj["models"] as? [[String: Any]]
                else { return [] }
                return models.compactMap { $0["name"] as? String }
            } catch {
                return []
            }
        case .openaiCompat:
            return [config.model]
        }
    }

    static func chat(
        config: LocalAIConfig,
        messages: [LocalAIChatMessage],
        tools: [[String: Any]] = [],
        temperature: Double = 0.2
    ) async throws -> LocalAIChatResult {
        switch config.backend {
        case .anemllStub:
            return LocalAIChatResult(
                content: AnemllBackend.notConfiguredMessage,
                toolCalls: [],
                finishReason: "stop",
                rawBackend: .anemllStub
            )
        case .ollama, .openaiCompat:
            return try await openAICompatChat(
                config: config,
                messages: messages,
                tools: tools,
                temperature: temperature
            )
        }
    }

    private static func openAICompatChat(
        config: LocalAIConfig,
        messages: [LocalAIChatMessage],
        tools: [[String: Any]],
        temperature: Double
    ) async throws -> LocalAIChatResult {
        guard let url = URL(string: "/v1/chat/completions", relativeTo: config.baseURL)?.absoluteURL else {
            throw LocalAIError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        if let key = config.apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "model": config.model,
            "temperature": temperature,
            "stream": false,
            "messages": messages.map { msg -> [String: Any] in
                var m: [String: Any] = ["role": msg.role]
                if let content = msg.content { m["content"] = content }
                if let toolCallId = msg.toolCallId { m["tool_call_id"] = toolCallId }
                if let name = msg.name { m["name"] = name }
                if let calls = msg.toolCalls, !calls.isEmpty {
                    m["tool_calls"] = calls.map { call -> [String: Any] in
                        [
                            "id": call.id,
                            "type": "function",
                            "function": [
                                "name": call.name,
                                "arguments": call.argumentsJSON,
                            ],
                        ]
                    }
                }
                return m
            },
        ]
        if !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalAIError.badResponse(String(data: data, encoding: .utf8) ?? "non-json")
        }
        if code >= 400 {
            let err = (obj["error"] as? [String: Any])?["message"] as? String
                ?? (obj["error"] as? String)
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(code)"
            throw LocalAIError.http(code, err)
        }
        guard let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any]
        else {
            throw LocalAIError.badResponse("missing choices")
        }
        let content = message["content"] as? String
        var toolCalls: [LocalAIToolCall] = []
        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            for call in rawCalls {
                let id = (call["id"] as? String) ?? UUID().uuidString
                let fn = call["function"] as? [String: Any] ?? [:]
                let name = (fn["name"] as? String) ?? ""
                let args: String
                if let s = fn["arguments"] as? String {
                    args = s
                } else if let d = fn["arguments"] {
                    args = (try? String(data: JSONSerialization.data(withJSONObject: d), encoding: .utf8)) ?? "{}"
                } else {
                    args = "{}"
                }
                if !name.isEmpty {
                    toolCalls.append(LocalAIToolCall(id: id, name: name, argumentsJSON: args))
                }
            }
        }
        return LocalAIChatResult(
            content: content,
            toolCalls: toolCalls,
            finishReason: first["finish_reason"] as? String,
            rawBackend: config.backend
        )
    }
}

enum LocalAIError: Error, LocalizedError {
    case badURL
    case badResponse(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid AI base URL"
        case .badResponse(let s): return "Bad AI response: \(s.prefix(200))"
        case .http(let c, let m): return "AI HTTP \(c): \(m.prefix(200))"
        }
    }
}

/// True ANEMLL / ANE ranking stays a stub (dendritic `mba-ane.yaml` pattern).
enum AnemllBackend {
    static let notConfiguredMessage = """
    ANEMLL/NPU backend is not configured.
    Local Agent chat uses Metal Ollama (OpenAI-compat at :11434), same as the dendritic `chat` CLI.
    Set GHIDRA_VIBE_AI_BACKEND=anemll only for stub probing; real Core ML ranking is future work.
    """
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    func trimmingSlash() -> String {
        if hasSuffix("/") { return String(dropLast()) }
        return self
    }
}
