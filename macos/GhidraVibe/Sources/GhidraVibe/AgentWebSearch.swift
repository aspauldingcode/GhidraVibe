import Foundation

/// Lightweight public web research for the Agent (`web_search` tool).
/// Uses DuckDuckGo Instant Answer + Wikipedia OpenSearch — no API keys.
enum AgentWebSearch {
    struct Hit: Sendable {
        var title: String
        var url: String
        var snippet: String
    }

    static func search(query: String, limit: Int = 6, sandbox: Bool = true) async -> String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            return #"{"ok":false,"error":"query required"}"#
        }
        let cap = min(max(limit, 1), 10)
        var hits: [Hit] = []

        if let ddg = await duckDuckGoInstant(q) {
            hits.append(contentsOf: ddg)
        }
        if hits.count < cap, let wiki = await wikipediaOpenSearch(q, limit: cap) {
            for h in wiki where !hits.contains(where: { $0.url == h.url }) {
                hits.append(h)
                if hits.count >= cap { break }
            }
        }
        // Instant Answer is sparse for RE queries — HTML lite often still returns links.
        if hits.count < cap, let lite = await duckDuckGoLite(q, limit: cap) {
            for h in lite where !hits.contains(where: { $0.url == h.url }) {
                hits.append(h)
                if hits.count >= cap { break }
            }
        }

        if sandbox {
            hits = hits.filter { hit in
                guard let host = URL(string: hit.url)?.host?.lowercased() else { return false }
                return AgentToolPermissionStore.networkAllowHosts.contains(host)
                    || host.hasSuffix(".wikipedia.org")
                    || host.hasSuffix(".duckduckgo.com")
            }
        }

        if hits.isEmpty {
            return """
            {"ok":true,"query":\(jsonString(q)),"hits":[],"note":"No structured hits. Try a more specific query (add ghidra, github, arm64, error text).","sandbox":\(sandbox ? "true" : "false")}
            """
        }

        let payload: [String: Any] = [
            "ok": true,
            "query": q,
            "sandbox": sandbox,
            "hits": hits.prefix(cap).map { h -> [String: String] in
                [
                    "title": h.title,
                    "url": h.url,
                    "snippet": String(h.snippet.prefix(280)),
                ]
            },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return #"{"ok":false,"error":"encode failed"}"#
        }
        return text
    }

    // MARK: - Providers

    private static func duckDuckGoInstant(_ query: String) async -> [Hit]? {
        var comps = URLComponents(string: "https://api.duckduckgo.com/")
        comps?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
        ]
        guard let url = comps?.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("GhidraVibeAgent/0.1 (reverse-engineering research)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code < 400,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }

            var hits: [Hit] = []
            let heading = (obj["Heading"] as? String) ?? ""
            let abstract = (obj["AbstractText"] as? String) ?? ""
            let abstractURL = (obj["AbstractURL"] as? String) ?? ""
            if !abstract.isEmpty {
                hits.append(Hit(
                    title: heading.isEmpty ? "DuckDuckGo Abstract" : heading,
                    url: abstractURL.isEmpty ? "https://duckduckgo.com/?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)" : abstractURL,
                    snippet: abstract
                ))
            }
            if let related = obj["RelatedTopics"] as? [Any] {
                for item in related {
                    guard hits.count < 8 else { break }
                    guard let dict = item as? [String: Any] else { continue }
                    if let topics = dict["Topics"] as? [[String: Any]] {
                        for t in topics {
                            appendRelated(t, into: &hits)
                            if hits.count >= 8 { break }
                        }
                    } else {
                        appendRelated(dict, into: &hits)
                    }
                }
            }
            return hits
        } catch {
            return nil
        }
    }

    private static func appendRelated(_ dict: [String: Any], into hits: inout [Hit]) {
        let text = (dict["Text"] as? String) ?? ""
        let url = (dict["FirstURL"] as? String) ?? ""
        guard !text.isEmpty, !url.isEmpty else { return }
        let title = text.split(separator: " - ").first.map(String.init) ?? text
        hits.append(Hit(title: String(title.prefix(120)), url: url, snippet: text))
    }

    private static func wikipediaOpenSearch(_ query: String, limit: Int) async -> [Hit]? {
        var comps = URLComponents(string: "https://en.wikipedia.org/w/api.php")
        comps?.queryItems = [
            URLQueryItem(name: "action", value: "opensearch"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "namespace", value: "0"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = comps?.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        // Wikipedia requires a descriptive UA; bare tokens are often filtered.
        req.setValue(
            "GhidraVibeAgent/0.1 (https://github.com/; reverse-engineering research; local-only)",
            forHTTPHeaderField: "User-Agent"
        )
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code < 400,
                  let arr = try JSONSerialization.jsonObject(with: data) as? [Any],
                  arr.count >= 4,
                  let titles = arr[1] as? [String],
                  let descs = arr[2] as? [String],
                  let urls = arr[3] as? [String]
            else { return nil }
            var hits: [Hit] = []
            for i in 0 ..< min(titles.count, urls.count) {
                let snippet = i < descs.count ? descs[i] : ""
                hits.append(Hit(title: titles[i], url: urls[i], snippet: snippet.isEmpty ? titles[i] : snippet))
            }
            return hits
        } catch {
            return nil
        }
    }

    /// Parse DuckDuckGo lite HTML for result links when Instant Answer is empty.
    private static func duckDuckGoLite(_ query: String, limit: Int) async -> [Hit]? {
        var comps = URLComponents(string: "https://lite.duckduckgo.com/lite/")
        comps?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = comps?.url else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 14
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(
            "GhidraVibeAgent/0.1 (reverse-engineering research)",
            forHTTPHeaderField: "User-Agent"
        )
        let body = "q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
        req.httpBody = Data(body.utf8)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code < 400, let html = String(data: data, encoding: .utf8) else { return nil }

            var hits: [Hit] = []
            // lite results: <a rel="nofollow" href="https://…">Title</a>
            let pattern = #"href="(https?://[^"]+)"[^>]*>([^<]{3,160})"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else { return nil }
            let range = NSRange(html.startIndex ..< html.endIndex, in: html)
            for match in regex.matches(in: html, options: [], range: range) {
                guard hits.count < limit else { break }
                guard match.numberOfRanges >= 3,
                      let urlR = Range(match.range(at: 1), in: html),
                      let titleR = Range(match.range(at: 2), in: html)
                else { continue }
                let link = String(html[urlR])
                let title = String(html[titleR])
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Skip DDG chrome / tracking redirects noise.
                if link.contains("duckduckgo.com") { continue }
                if title.lowercased().contains("duckduckgo") { continue }
                if hits.contains(where: { $0.url == link }) { continue }
                hits.append(Hit(title: title, url: link, snippet: title))
            }
            return hits.isEmpty ? nil : hits
        } catch {
            return nil
        }
    }

    private static func jsonString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: s),
              let out = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return out
    }
}
