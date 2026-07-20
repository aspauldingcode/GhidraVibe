import Foundation

/// Localhost HTTP client for the program engine (:8089) and vibe helpers (:8092).
/// Not a Cursor MCP requirement — transport for the embedded Ghidra engine.
enum MCPClient {
    struct Response {
        var ok: Bool
        var text: String
        var json: Any?
        var statusCode: Int
    }

    static func get(base: URL, path: String, query: [String: String] = [:]) async -> Response {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps?.url else {
            return Response(ok: false, text: "bad url", json: nil, statusCode: 0)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 120
        return await perform(req)
    }

    static func post(base: URL, path: String, body: [String: Any] = [:]) async -> Response {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 600
        return await perform(req)
    }

    /// Encode body on the caller actor, then POST bytes (avoids sending dictionaries across isolation).
    static func postData(base: URL, path: String, bodyData: Data?) async -> Response {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData
        req.timeoutInterval = 600
        return await perform(req)
    }

    private static func perform(_ req: URLRequest) async -> Response {
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: data, encoding: .utf8) ?? ""
            let json = try? JSONSerialization.jsonObject(with: data)
            let okFlag: Bool = {
                if let d = json as? [String: Any] {
                    if let ok = d["ok"] as? Bool { return ok }
                    // Headless MCP often returns HTTP 200 with {"error":"…"}.
                    if d["error"] != nil { return false }
                }
                return (200 ..< 300).contains(code)
            }()
            return Response(ok: okFlag, text: text, json: json, statusCode: code)
        } catch {
            return Response(ok: false, text: error.localizedDescription, json: nil, statusCode: 0)
        }
    }

    static func lines(from resp: Response) -> [String] {
        if let d = resp.json as? [String: Any] {
            if let arr = d["data"] as? [String] { return arr }
            if let arr = d["data"] as? [Any] {
                return arr.map { item -> String in
                    if let s = item as? String { return s }
                    if let dict = item as? [String: Any] {
                        if let p = dict["path"] as? String { return p }
                        if let n = dict["name"] as? String { return n }
                        if let a = dict["address"] as? String, let nm = dict["name"] as? String {
                            return "\(nm) @ \(a)"
                        }
                    }
                    if let t = try? JSONSerialization.data(withJSONObject: item),
                       let s = String(data: t, encoding: .utf8)
                    {
                        return s
                    }
                    return String(describing: item)
                }
            }
            if let text = d["text"] as? String {
                return text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
            }
        }
        return resp.text.split(whereSeparator: \.isNewline).map(String.init).filter {
            !$0.isEmpty && !$0.lowercased().contains("404")
        }
    }
}
