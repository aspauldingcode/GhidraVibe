import Foundation

/// Stock JavaHelp corpus extracted into `Contents/Resources/help/` (or `native-ui/help`).
struct HelpCatalog {
    struct Manifest: Decodable {
        var version: Int?
        var articles: Int?
        var mapIds: Int?
        var tips: Int?
        var defaultTarget: String?
        var defaultPath: String?
    }

    struct TocNode: Codable, Identifiable, Hashable {
        var id: String
        var title: String
        var target: String?
        var children: [TocNode]

        init(id: String, title: String, target: String? = nil, children: [TocNode] = []) {
            self.id = id
            self.title = title
            self.target = target
            self.children = children
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, target, children
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            target = try c.decodeIfPresent(String.self, forKey: .target)
            children = try c.decodeIfPresent([TocNode].self, forKey: .children) ?? []
        }
    }

    struct SearchEntry: Codable, Identifiable, Hashable {
        var id: String
        var title: String
        var path: String
        var text: String
    }

    let rootURL: URL
    let articlesURL: URL
    let manifest: Manifest
    let toc: TocNode
    let map: [String: String]
    let search: [SearchEntry]
    let tips: [String]

    static func load() -> HelpCatalog? {
        for root in candidateRoots() {
            let tocURL = root.appendingPathComponent("toc.json")
            let mapURL = root.appendingPathComponent("map.json")
            let articles = root.appendingPathComponent("articles")
            guard FileManager.default.fileExists(atPath: tocURL.path),
                  FileManager.default.fileExists(atPath: articles.path)
            else { continue }
            do {
                let rawToc = try JSONDecoder().decode(TocNode.self, from: Data(contentsOf: tocURL))
                let toc = uniquifyTocIds(rawToc, prefix: "")
                let map =
                    (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: mapURL)))
                    ?? [:]
                let manifestURL = root.appendingPathComponent("manifest.json")
                let manifest =
                    (try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL)))
                    ?? Manifest()
                let searchURL = root.appendingPathComponent("search.json")
                let search =
                    (try? JSONDecoder().decode([SearchEntry].self, from: Data(contentsOf: searchURL)))
                    ?? []
                let tipsURL = root.appendingPathComponent("tips.txt")
                let tips: [String]
                if let raw = try? String(contentsOf: tipsURL, encoding: .utf8) {
                    tips = raw.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
                } else {
                    tips = []
                }
                return HelpCatalog(
                    rootURL: root,
                    articlesURL: articles,
                    manifest: manifest,
                    toc: toc,
                    map: map,
                    search: search,
                    tips: tips
                )
            } catch {
                continue
            }
        }
        return nil
    }

    private static func candidateRoots() -> [URL] {
        var out: [URL] = []
        if let res = Bundle.main.resourceURL {
            out.append(res.appendingPathComponent("help"))
        }
        if let resPath = Bundle.main.resourcePath {
            out.append(URL(fileURLWithPath: resPath).appendingPathComponent("help"))
        }
        // Dev / unpackaged: repo native-ui/help next to Sources
        let exe = Bundle.main.bundleURL
        let probes = [
            exe.deletingLastPathComponent() // .build/release
                .deletingLastPathComponent() // .build
                .deletingLastPathComponent() // GhidraVibe
                .deletingLastPathComponent() // macos
                .appendingPathComponent("native-ui/help"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("native-ui/help"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("../native-ui/help"),
        ]
        out.append(contentsOf: probes)
        return out
    }

    func url(forTarget target: String?) -> URL? {
        guard let target, let mapped = map[target] else { return nil }
        return url(forArticlePath: mapped)
    }

    /// Open a stock JavaHelp mapID → article URL (F1 / context Help).
    static func open(mapId: String) -> URL? {
        guard let catalog = load() else { return nil }
        let resolved = HelpContext.resolve(mapId, catalog: catalog)
        return catalog.url(forTarget: resolved) ?? catalog.defaultArticleURL
    }

    /// Whether `mapId` exists in the packaged map (after soft resolve).
    static func hasMapId(_ mapId: String) -> Bool {
        guard let catalog = load() else { return false }
        return catalog.map[HelpContext.resolve(mapId, catalog: catalog)] != nil
    }

    func url(forArticlePath path: String) -> URL? {
        let base = path.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let rel = String(base[0])
        guard !rel.isEmpty else { return nil }
        let file = articlesURL.appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        if base.count > 1, !base[1].isEmpty {
            var comps = URLComponents(url: file, resolvingAgainstBaseURL: false)
            comps?.fragment = String(base[1])
            return comps?.url ?? file
        }
        return file
    }

    var defaultArticleURL: URL? {
        if let t = manifest.defaultTarget, let u = url(forTarget: t) { return u }
        if let p = manifest.defaultPath, let u = url(forArticlePath: p) { return u }
        return url(forArticlePath: "topics/Misc/Welcome_to_Help.htm")
    }

    func search(query: String, limit: Int = 40) -> [SearchEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { return [] }
        let tokens = q.split(whereSeparator: \.isWhitespace).map(String.init)
        var scored: [(Int, SearchEntry)] = []
        for entry in search {
            let title = entry.title.lowercased()
            let body = entry.text.lowercased()
            var score = 0
            for t in tokens {
                if title.contains(t) { score += 10 }
                if body.contains(t) { score += 1 }
            }
            if score > 0 { scored.append((score, entry)) }
        }
        scored.sort { $0.0 > $1.0 }
        return scored.prefix(limit).map(\.1)
    }

    /// Flatten TOC for OutlineGroup selection → open article.
    func firstTarget(in node: TocNode) -> String? {
        if let t = node.target { return t }
        for c in node.children {
            if let t = firstTarget(in: c) { return t }
        }
        return nil
    }

    /// Stock TOC reuses `toc_id` across branches; SwiftUI selection needs unique ids.
    private static func uniquifyTocIds(_ node: TocNode, prefix: String) -> TocNode {
        let path = prefix.isEmpty ? node.id : "\(prefix)/\(node.id)"
        return TocNode(
            id: path,
            title: node.title,
            target: node.target,
            children: node.children.map { uniquifyTocIds($0, prefix: path) }
        )
    }
}
