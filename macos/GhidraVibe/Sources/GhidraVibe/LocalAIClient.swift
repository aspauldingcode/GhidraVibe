import Foundation

/// LLM transport kinds used by `LocalAIClient`.
enum AgentLLMBackendKind: String, CaseIterable, Sendable {
    case ollama
    case openaiCompat = "openai_compat"
    case anthropic
    case google
    case anemllStub = "anemll_stub"
}

struct LocalAIConfig: Sendable {
    var baseURL: URL
    var model: String
    var apiKey: String?
    var backend: AgentLLMBackendKind
    var provider: AgentProviderKind

    static func resolve(
        env: [String: String] = ProcessInfo.processInfo.environment,
        provider: AgentProviderKind? = nil,
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
                backend: .anemllStub,
                provider: .ollama
            )
        }

        var kind = provider
            ?? AgentProviderKind.from(raw: env["GHIDRA_VIBE_AI_PROVIDER"])
        if preferCloud, kind == .ollama || kind == .llamaCpp {
            kind = AgentProviderKind.from(raw: env["GHIDRA_VIBE_AI_CLOUD_PROVIDER"]) 
            if kind == .ollama { kind = .openai }
        }

        let rawBase = userBaseURL?.nilIfEmpty
            ?? env["GHIDRA_VIBE_AI_BASE_URL"]?.nilIfEmpty
            ?? (kind == .ollama
                ? (env["AI_LOCAL_BASE_URL"]?.nilIfEmpty ?? env["OLLAMA_HOST"]?.nilIfEmpty)
                : nil)
            ?? (kind == .openai || kind == .openaiCompat
                ? (env["GHIDRA_VIBE_AI_CLOUD_BASE_URL"]?.nilIfEmpty ?? env["OPENAI_BASE_URL"]?.nilIfEmpty)
                : nil)
            ?? kind.defaultBaseURL

        let model = userModel?.nilIfEmpty
            ?? env["GHIDRA_VIBE_AI_MODEL"]?.nilIfEmpty
            ?? env["AI_LOCAL_DEFAULT_MODEL"]?.nilIfEmpty
            ?? env["OPENAI_MODEL"]?.nilIfEmpty
            ?? kind.defaultModel

        let backend: AgentLLMBackendKind
        switch kind {
        case .ollama: backend = .ollama
        case .llamaCpp, .openai, .openaiCompat: backend = .openaiCompat
        case .anthropic: backend = .anthropic
        case .google: backend = .google
        }

        return LocalAIConfig(
            baseURL: URL(string: rawBase.trimmingSlash()) ?? URL(string: kind.defaultBaseURL)!,
            model: model,
            apiKey: apiKey,
            backend: backend,
            provider: kind
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

/// Multi-provider chat client (Ollama / llama.cpp / OpenAI-compat / Anthropic / Google).
enum LocalAIClient {
    static func listModels(config: LocalAIConfig) async -> [String] {
        switch config.backend {
        case .anemllStub:
            return []
        case .ollama:
            return await listOllamaTags(baseURL: config.baseURL)
        case .openaiCompat:
            if config.provider == .llamaCpp {
                let local = AgentLocalModels.listEntries().map(\.displayName)
                if !local.isEmpty { return local }
            }
            if let remote = await listOpenAIModels(config: config), !remote.isEmpty {
                return remote
            }
            return config.provider.suggestedModels
        case .anthropic, .google:
            return config.provider.suggestedModels
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
        case .anthropic:
            return try await anthropicChat(
                config: config,
                messages: messages,
                tools: tools,
                temperature: temperature
            )
        case .google:
            return try await googleChat(
                config: config,
                messages: messages,
                tools: tools,
                temperature: temperature
            )
        }
    }

    /// Progressive OpenAI-compat streaming (no tools). Falls back to `chat` otherwise.
    static func chatStream(
        config: LocalAIConfig,
        messages: [LocalAIChatMessage],
        tools: [[String: Any]] = [],
        temperature: Double = 0.2,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> LocalAIChatResult {
        guard tools.isEmpty,
              config.backend == .ollama || config.backend == .openaiCompat
        else {
            let result = try await chat(
                config: config,
                messages: messages,
                tools: tools,
                temperature: temperature
            )
            if let content = result.content, !content.isEmpty {
                onDelta(content)
            }
            return result
        }
        return try await openAICompatChatStream(
            config: config,
            messages: messages,
            temperature: temperature,
            onDelta: onDelta
        )
    }

    // MARK: - List

    private static func listOllamaTags(baseURL: URL) async -> [String] {
        guard let url = URL(string: "/api/tags", relativeTo: baseURL)?.absoluteURL else { return [] }
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
    }

    private static func listOpenAIModels(config: LocalAIConfig) async -> [String]? {
        guard let url = URL(string: "/v1/models", relativeTo: config.baseURL)?.absoluteURL else {
            return nil
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 8
        if let key = config.apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code < 400,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = obj["data"] as? [[String: Any]]
            else { return nil }
            return arr.compactMap { $0["id"] as? String }.sorted()
        } catch {
            return nil
        }
    }

    // MARK: - OpenAI-compat (Ollama, llama.cpp, OpenAI, Groq, …)

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
        applyAuth(config, to: &req)

        var body: [String: Any] = [
            "model": config.model,
            "temperature": temperature,
            "stream": false,
            "messages": messages.map { encodeOpenAIMessage($0) },
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
            throw LocalAIError.http(code, openAIErrorMessage(obj, data: data))
        }
        guard let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any]
        else {
            throw LocalAIError.badResponse("missing choices")
        }
        let content = message["content"] as? String
        var toolCalls = parseOpenAIToolCalls(message["tool_calls"] as? [[String: Any]])
        // Tiny local models (e.g. qwen2.5-coder:3b) often print tool JSON in `content`
        // instead of structured `tool_calls` — promote those so the agent loop can run them.
        if toolCalls.isEmpty, !tools.isEmpty {
            let inline = AgentTools.parseInlineToolCalls(from: content)
            if !inline.isEmpty {
                toolCalls = inline
            }
        }
        return LocalAIChatResult(
            content: toolCalls.isEmpty ? content : nil,
            toolCalls: toolCalls,
            finishReason: first["finish_reason"] as? String,
            rawBackend: config.backend
        )
    }

    private static func openAICompatChatStream(
        config: LocalAIConfig,
        messages: [LocalAIChatMessage],
        temperature: Double,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> LocalAIChatResult {
        guard let url = URL(string: "/v1/chat/completions", relativeTo: config.baseURL)?.absoluteURL else {
            throw LocalAIError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 180
        applyAuth(config, to: &req)
        let body: [String: Any] = [
            "model": config.model,
            "temperature": temperature,
            "stream": true,
            "messages": messages.map { encodeOpenAIMessage($0) },
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code >= 400 {
            var errData = Data()
            for try await b in bytes { errData.append(b) }
            let obj = (try? JSONSerialization.jsonObject(with: errData)) as? [String: Any]
            throw LocalAIError.http(code, openAIErrorMessage(obj ?? [:], data: errData))
        }

        var assembled = ""
        var finish: String?
        for try await line in bytes.lines {
            try Task.checkCancellation()
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let first = choices.first
            else { continue }
            if let fr = first["finish_reason"] as? String { finish = fr }
            let deltaObj = first["delta"] as? [String: Any]
            if let piece = deltaObj?["content"] as? String, !piece.isEmpty {
                assembled += piece
                onDelta(piece)
            }
        }
        return LocalAIChatResult(
            content: assembled,
            toolCalls: [],
            finishReason: finish ?? "stop",
            rawBackend: config.backend
        )
    }

    // MARK: - Anthropic Messages

    private static func anthropicChat(
        config: LocalAIConfig,
        messages: [LocalAIChatMessage],
        tools: [[String: Any]],
        temperature: Double
    ) async throws -> LocalAIChatResult {
        guard let url = URL(string: "/v1/messages", relativeTo: config.baseURL)?.absoluteURL else {
            throw LocalAIError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.timeoutInterval = 120
        applyAuth(config, to: &req)

        var systemText = ""
        var apiMessages: [[String: Any]] = []
        for msg in messages {
            if msg.role == "system" {
                systemText += (msg.content ?? "") + "\n"
                continue
            }
            if msg.role == "tool" {
                apiMessages.append([
                    "role": "user",
                    "content": [
                        [
                            "type": "tool_result",
                            "tool_use_id": msg.toolCallId ?? "",
                            "content": msg.content ?? "",
                        ],
                    ],
                ])
                continue
            }
            if let calls = msg.toolCalls, !calls.isEmpty {
                var content: [[String: Any]] = []
                if let text = msg.content, !text.isEmpty {
                    content.append(["type": "text", "text": text])
                }
                for call in calls {
                    let input = (try? JSONSerialization.jsonObject(
                        with: Data(call.argumentsJSON.utf8)
                    )) ?? [:]
                    content.append([
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name,
                        "input": input,
                    ])
                }
                apiMessages.append(["role": "assistant", "content": content])
                continue
            }
            apiMessages.append([
                "role": msg.role == "assistant" ? "assistant" : "user",
                "content": msg.content ?? "",
            ])
        }

        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": 4096,
            "temperature": temperature,
            "messages": apiMessages,
        ]
        if !systemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["system"] = systemText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !tools.isEmpty {
            body["tools"] = tools.compactMap { openaiToolToAnthropic($0) }
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalAIError.badResponse(String(data: data, encoding: .utf8) ?? "non-json")
        }
        if code >= 400 {
            let err = (obj["error"] as? [String: Any])?["message"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(code)"
            throw LocalAIError.http(code, err)
        }
        var text = ""
        var toolCalls: [LocalAIToolCall] = []
        if let blocks = obj["content"] as? [[String: Any]] {
            for block in blocks {
                let type = block["type"] as? String ?? ""
                if type == "text", let t = block["text"] as? String {
                    text += t
                } else if type == "tool_use" {
                    let id = (block["id"] as? String) ?? UUID().uuidString
                    let name = (block["name"] as? String) ?? ""
                    let input = block["input"] ?? [:]
                    let args = (try? String(
                        data: JSONSerialization.data(withJSONObject: input),
                        encoding: .utf8
                    )) ?? "{}"
                    if !name.isEmpty {
                        toolCalls.append(LocalAIToolCall(id: id, name: name, argumentsJSON: args))
                    }
                }
            }
        }
        return LocalAIChatResult(
            content: text.isEmpty ? nil : text,
            toolCalls: toolCalls,
            finishReason: obj["stop_reason"] as? String,
            rawBackend: .anthropic
        )
    }

    // MARK: - Google Gemini

    private static func googleChat(
        config: LocalAIConfig,
        messages: [LocalAIChatMessage],
        tools: [[String: Any]],
        temperature: Double
    ) async throws -> LocalAIChatResult {
        let modelId = config.model
        var components = URLComponents(
            url: config.baseURL.appendingPathComponent("v1beta/models/\(modelId):generateContent"),
            resolvingAgainstBaseURL: false
        )
        if config.provider.auth == .googleQuery, let key = config.apiKey, !key.isEmpty {
            components?.queryItems = [URLQueryItem(name: "key", value: key)]
        }
        guard let url = components?.url else { throw LocalAIError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        if config.provider.auth == .bearer, let key = config.apiKey {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        var contents: [[String: Any]] = []
        var systemInstruction: [String: Any]?
        for msg in messages {
            if msg.role == "system" {
                systemInstruction = ["parts": [["text": msg.content ?? ""]]]
                continue
            }
            let role = msg.role == "assistant" ? "model" : "user"
            if msg.role == "tool" {
                contents.append([
                    "role": "user",
                    "parts": [
                        [
                            "functionResponse": [
                                "name": msg.name ?? "tool",
                                "response": ["result": msg.content ?? ""],
                            ],
                        ],
                    ],
                ])
                continue
            }
            if let calls = msg.toolCalls, !calls.isEmpty {
                var parts: [[String: Any]] = []
                if let text = msg.content, !text.isEmpty {
                    parts.append(["text": text])
                }
                for call in calls {
                    let args = (try? JSONSerialization.jsonObject(
                        with: Data(call.argumentsJSON.utf8)
                    )) ?? [:]
                    parts.append([
                        "functionCall": [
                            "name": call.name,
                            "args": args,
                        ],
                    ])
                }
                contents.append(["role": "model", "parts": parts])
                continue
            }
            contents.append([
                "role": role,
                "parts": [["text": msg.content ?? ""]],
            ])
        }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": temperature,
            ],
        ]
        if let systemInstruction {
            body["systemInstruction"] = systemInstruction
        }
        if !tools.isEmpty {
            let decls = tools.compactMap { openaiToolToGoogle($0) }
            if !decls.isEmpty {
                body["tools"] = [["functionDeclarations": decls]]
            }
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalAIError.badResponse(String(data: data, encoding: .utf8) ?? "non-json")
        }
        if code >= 400 {
            let err = (obj["error"] as? [String: Any])?["message"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(code)"
            throw LocalAIError.http(code, err)
        }
        guard let candidates = obj["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else {
            throw LocalAIError.badResponse("missing candidates")
        }
        var text = ""
        var toolCalls: [LocalAIToolCall] = []
        for part in parts {
            if let t = part["text"] as? String {
                text += t
            } else if let fc = part["functionCall"] as? [String: Any] {
                let name = (fc["name"] as? String) ?? ""
                let args = fc["args"] ?? [:]
                let argsJSON = (try? String(
                    data: JSONSerialization.data(withJSONObject: args),
                    encoding: .utf8
                )) ?? "{}"
                if !name.isEmpty {
                    toolCalls.append(
                        LocalAIToolCall(id: UUID().uuidString, name: name, argumentsJSON: argsJSON)
                    )
                }
            }
        }
        return LocalAIChatResult(
            content: text.isEmpty ? nil : text,
            toolCalls: toolCalls,
            finishReason: (first["finishReason"] as? String),
            rawBackend: .google
        )
    }

    // MARK: - Helpers

    private static func applyAuth(_ config: LocalAIConfig, to req: inout URLRequest) {
        guard let key = config.apiKey, !key.isEmpty else { return }
        switch config.provider.auth {
        case .none, .googleQuery:
            break
        case .bearer:
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropicKey:
            req.setValue(key, forHTTPHeaderField: "x-api-key")
        }
    }

    private static func encodeOpenAIMessage(_ msg: LocalAIChatMessage) -> [String: Any] {
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
    }

    private static func parseOpenAIToolCalls(_ raw: [[String: Any]]?) -> [LocalAIToolCall] {
        guard let raw else { return [] }
        var toolCalls: [LocalAIToolCall] = []
        for call in raw {
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
        return toolCalls
    }

    private static func openAIErrorMessage(_ obj: [String: Any], data: Data) -> String {
        (obj["error"] as? [String: Any])?["message"] as? String
            ?? (obj["error"] as? String)
            ?? String(data: data, encoding: .utf8)
            ?? "error"
    }

    private static func openaiToolToAnthropic(_ tool: [String: Any]) -> [String: Any]? {
        guard let fn = tool["function"] as? [String: Any],
              let name = fn["name"] as? String
        else { return nil }
        return [
            "name": name,
            "description": fn["description"] as? String ?? "",
            "input_schema": fn["parameters"] as? [String: Any] ?? ["type": "object", "properties": [:]],
        ]
    }

    private static func openaiToolToGoogle(_ tool: [String: Any]) -> [String: Any]? {
        guard let fn = tool["function"] as? [String: Any],
              let name = fn["name"] as? String
        else { return nil }
        var decl: [String: Any] = [
            "name": name,
            "description": fn["description"] as? String ?? "",
        ]
        if let params = fn["parameters"] as? [String: Any] {
            decl["parameters"] = params
        }
        return decl
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

enum AnemllBackend {
    static let notConfiguredMessage = """
    ANEMLL/NPU backend is not configured.
    Use Ollama, llama.cpp (GGUF drop), or a proprietary provider in Agent Setup.
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
