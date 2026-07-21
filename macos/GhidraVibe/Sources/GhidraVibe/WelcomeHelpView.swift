import SwiftUI

/// Native Ghidra Help: stock JavaHelp TOC + WKWebView articles (no Swing).
struct WelcomeHelpView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.vibeTheme) private var themes
    @State private var catalog: HelpCatalog? = HelpCatalog.load()
    @State private var selectedTocId: String?
    @State private var articleURL: URL?
    @State private var articleTitle: String = "Ghidra Help"
    @State private var searchText: String = ""
    @State private var searchResults: [HelpCatalog.SearchEntry] = []
    @State private var showFallback: Bool = false
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var navigateAction: HelpWebView.HelpNavigateAction?

    var body: some View {
        Group {
            if let catalog, !showFallback {
                stockBrowser(catalog: catalog)
            } else {
                FallbackHelpView()
            }
        }
        .background(themes.theme.vibeWindow)
        .a11yContainerCatalog("ghidra.vibe.help")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    navigateAction = .back
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)
                .a11yCatalog("ghidra.vibe.help.back")
                Button {
                    navigateAction = .forward
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canGoForward)
                .a11yCatalog("ghidra.vibe.help.forward")
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { model.dismissWelcomeHelp() }
                    .a11yCatalog("ghidra.vibe.help.close")
            }
        }
        .onAppear {
            if let catalog {
                openDefault(catalog)
            } else {
                showFallback = true
            }
        }
        .onChange(of: model.helpPendingMapId) { _, mapId in
            guard let catalog, let mapId else { return }
            openMapId(mapId, catalog: catalog)
        }
        .onChange(of: navigateAction) { _, action in
            // Consume one-shot nav after HelpWebView applies it.
            if action != nil {
                DispatchQueue.main.async { navigateAction = nil }
            }
        }
    }

    @ViewBuilder
    private func stockBrowser(catalog: HelpCatalog) -> some View {
        let t = themes.theme
        NavigationSplitView {
            VStack(spacing: 0) {
                TextField("Search Help", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                    .a11yCatalog("ghidra.vibe.help.search")
                    .onChange(of: searchText) { _, q in
                        searchResults = catalog.search(query: q)
                    }

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    List(searchResults, id: \.path, selection: Binding(
                        get: { selectedTocId },
                        set: { path in
                            selectedTocId = path
                            if let entry = searchResults.first(where: { $0.path == path }) {
                                articleURL = catalog.url(forArticlePath: entry.path)
                                articleTitle = entry.title
                            }
                        }
                    )) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).lineLimit(2)
                            Text(entry.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .tag(entry.path)
                    }
                    .listStyle(.sidebar)
                    .vibeThemedList()
                    .a11yCatalog("ghidra.vibe.help.search_results")
                } else {
                    List(selection: $selectedTocId) {
                        OutlineGroup(
                            catalog.toc.children.isEmpty ? [catalog.toc] : catalog.toc.children,
                            children: \.childrenOrNil
                        ) { node in
                            Text(node.title)
                                .tag(node.id)
                                .accessibilityIdentifier("ghidra.vibe.help.topic.\(sanitizeId(node.id))")
                        }
                    }
                    .listStyle(.sidebar)
                    .vibeThemedList()
                    .a11yCatalog("ghidra.vibe.help.toc")
                    .onChange(of: selectedTocId) { _, id in
                        guard let id, let node = findNode(id: id, in: catalog.toc) else { return }
                        if let target = catalog.firstTarget(in: node),
                           let url = catalog.url(forTarget: target)
                        {
                            articleURL = url
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(t.vibeContentAlt)
            .navigationTitle("Ghidra Help")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Text(articleTitle)
                        .font(.headline)
                        .foregroundStyle(t.vibeForeground)
                        .lineLimit(1)
                    Spacer()
                    if catalog.manifest.articles != nil {
                        Text("\(catalog.manifest.articles ?? 0) articles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(t.vibeContentAlt)

                HelpWebView(
                    articlesRoot: catalog.articlesURL,
                    articleURL: $articleURL,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    navigateAction: navigateAction,
                    onTitleChange: { title in
                        if !title.isEmpty { articleTitle = title }
                    }
                )
                .a11yCatalog("ghidra.vibe.help.content")
            }
            .background(t.vibeContent)
        }
    }

    private func openDefault(_ catalog: HelpCatalog) {
        if let mapId = model.helpPendingMapId {
            openMapId(mapId, catalog: catalog)
            return
        }
        articleURL = catalog.defaultArticleURL
        if let root = catalog.toc.children.first {
            selectedTocId = root.id
        } else {
            selectedTocId = catalog.toc.id
        }
    }

    private func openMapId(_ mapId: String, catalog: HelpCatalog) {
        let resolved = HelpContext.resolve(mapId, catalog: catalog)
        if let url = catalog.url(forTarget: resolved) {
            articleURL = url
            articleTitle = resolved
        } else {
            articleURL = catalog.defaultArticleURL
        }
        model.helpPendingMapId = nil
    }

    private func findNode(id: String, in node: HelpCatalog.TocNode) -> HelpCatalog.TocNode? {
        if node.id == id { return node }
        for c in node.children {
            if let n = findNode(id: id, in: c) { return n }
        }
        return nil
    }

    private func sanitizeId(_ id: String) -> String {
        id.replacingOccurrences(of: "/", with: ".")
            .replacingOccurrences(of: " ", with: "_")
    }
}

private extension HelpCatalog.TocNode {
    /// OutlineGroup wants `children: KeyPath` to optional array (nil = leaf).
    var childrenOrNil: [HelpCatalog.TocNode]? {
        children.isEmpty ? nil : children
    }
}

// MARK: - Offline fallback (bundle missing)

private struct FallbackHelpView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.vibeTheme) private var themes
    @State private var selected: FallbackTopic = .welcome

    var body: some View {
        let t = themes.theme
        NavigationSplitView {
            List(FallbackTopic.allCases, selection: $selected) { topic in
                Label(topic.title, systemImage: topic.symbol)
                    .tag(topic)
                    .accessibilityIdentifier("ghidra.vibe.help.topic.\(topic.rawValue)")
            }
            .listStyle(.sidebar)
            .vibeThemedList()
            .scrollContentBackground(.hidden)
            .background(t.vibeContentAlt)
            .navigationTitle("Ghidra Help")
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
            .a11yCatalog("ghidra.vibe.help.toc")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Help corpus not packaged")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(t.vibeForeground)
                    Text(
                        "Run scripts/extract-stock-help.py and package-app.sh to ship the full stock Help. Showing GhidraVibe topics only."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Text(selected.title)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(t.vibeForeground)
                    Text(selected.body)
                        .font(.body)
                        .foregroundStyle(t.vibeForeground)
                        .textSelection(.enabled)
                    if selected == .welcome {
                        Button("Open Project Window") {
                            model.dismissWelcomeHelp()
                            if model.toolMode != .projectWindow {
                                model.enterProjectWindow()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.vibeAccent)
                        .a11yCatalog("ghidra.vibe.help.open_project")
                    }
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
            }
            .background(t.vibeContent)
            .a11yCatalog("ghidra.vibe.help.content")
        }
    }
}

private enum FallbackTopic: String, CaseIterable, Identifiable, Hashable {
    case welcome, gettingStarted, projects, codeBrowser, mcp, dsc, agent, support

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome to Help"
        case .gettingStarted: "Getting Started"
        case .projects: "Ghidra Projects"
        case .codeBrowser: "CodeBrowser"
        case .mcp: "Analysis MCP"
        case .dsc: "Shared Cache (dyld)"
        case .agent: "Agent & RAG"
        case .support: "Support"
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "hand.wave"
        case .gettingStarted: "flag"
        case .projects: "folder"
        case .codeBrowser: "chevron.left.forwardslash.chevron.right"
        case .mcp: "network"
        case .dsc: "internaldrive"
        case .agent: "bubble.left.and.bubble.right"
        case .support: "lifepreserver"
        }
    }

    var body: String {
        switch self {
        case .welcome:
            """
            GhidraVibe is Ghidra with a native macOS/Linux GUI — the engine runs in-process; Swing Front End is not shipped.

            What's New in this shell
            • Project Window + CodeBrowser layout mirrored from CodeBrowser.tool
            • Integrated MCP, Agent chat, JSpace RAG, and Rules
            • On-device dyld shared cache import with Apple symbols (macOS)
            """
        case .gettingStarted:
            """
            1. Accept the User Agreement (native alert).
            2. Pick or create a project in the workspace chooser.
            3. Start Analysis MCP (toolbar or Tools menu).
            4. Import a binary or a dyld shared-cache image (Window → Shared Cache).
            5. Open CodeBrowser and decompile via MCP.
            """
        case .projects:
            """
            Projects are Ghidra `.gpr` files (same on-disk format as stock). Create or open a project from the workspace picker or Project Window.
            """
        case .codeBrowser:
            """
            CodeBrowser hosts Program Trees, Symbol Tree, Data Type Manager, Listing, Decompiler, and Console — matching stock default layout.
            """
        case .mcp:
            """
            Program engine API (default http://127.0.0.1:8089) runs in-process with the GUI. GuiControl (:8091) drives the native shell for automation.
            """
        case .dsc:
            """
            File → Open Shared Cache… opens the DSC Index. Filter, then Load selected or double-click to import one module with Apple local symbols.
            """
        case .agent:
            """
            The Agent panel runs JSpace RAG discovery then optional MCP decompile/list. Tool permissions and completion sounds live in Agent Setup.
            """
        case .support:
            """
            Docs: docs/GUI.md, docs/DYLD.md, docs/GUI_TESTING.md
            Accessibility: native-ui/a11y/catalog.json
            """
        }
    }
}
