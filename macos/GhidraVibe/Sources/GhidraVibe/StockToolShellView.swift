import SwiftUI

/// Native shell for stock Tool Chest tools (Debugger / Emulator / Version Tracking).
/// Providers and toolbar ids come from `native-ui/parity/*.chrome.json` (1:1 stock).
struct StockToolShellView: View {
    @Environment(AppModel.self) private var model
    let toolMode: ToolMode

    private var chromeName: String {
        switch toolMode {
        case .debugger: "Debugger"
        case .emulator: "Emulator"
        case .versionTrackingTool: "VersionTracking"
        default: "Debugger"
        }
    }

    private var toolSlug: String {
        switch toolMode {
        case .debugger: "debugger"
        case .emulator: "emulator"
        case .versionTrackingTool: "version_tracking"
        default: "debugger"
        }
    }

    private var a11yRoot: String { "ghidra.vibe.\(toolSlug)" }

    var body: some View {
        @Bindable var model = model
        let chrome = StockToolChrome.shared(for: chromeName)
        return VStack(spacing: 0) {
            toolToolbar(chrome)
            Divider()
            HSplitView {
                providerList(chrome)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
                providerDetail(chrome)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .a11yContainerCatalog(a11yRoot)
        .onAppear {
            model.statusMessage = "\(toolMode.rawValue) — stock tool"
            if model.stockToolSelectedProvider.isEmpty {
                model.stockToolSelectedProvider = chrome.providerTitles.first ?? ""
            }
            refreshSelectedProvider()
            if toolMode == .debugger {
                model.refreshDebuggerStatus()
            }
        }
        .onChange(of: model.stockToolSelectedProvider) { _, _ in
            refreshSelectedProvider()
        }
    }

    private func toolToolbar(_ chrome: StockToolChrome) -> some View {
        LiquidGlass.Bar(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button("Project Window") { model.enterProjectWindow() }
                        .buttonStyle(.glass)
                        .help("Return to Front End / Project Window")
                        .a11yCatalog("ghidra.vibe.\(toolSlug).back_project")
                    Button("CodeBrowser") { model.openCodeBrowser() }
                        .buttonStyle(.glass)
                        .help("Open CodeBrowser")
                    Divider().frame(height: 18)
                    ForEach(chrome.toolbarGroups, id: \.self) { group in
                        let id = chrome.toolbarId(group, toolSlug: toolSlug)
                        Button(group) { model.stockToolAction(tool: toolMode, toolbar: group) }
                            .buttonStyle(.glass)
                            .font(.caption)
                            .a11yCatalog(id)
                            .help(group)
                    }
                    Spacer(minLength: 0)
                    if model.agentEnabled {
                        Button {
                            model.toggleAgentSidebar()
                        } label: {
                            Image(systemName: "sidebar.trailing")
                        }
                        .buttonStyle(.glass)
                        .help(
                            model.dockLayout.agentSidebarVisible
                                ? "Hide Agent sidebar"
                                : "Show Agent sidebar"
                        )
                        .a11yCatalog("ghidra.vibe.toolbar.agent_sidebar")
                    }
                }
                .vibeGlassBarBackground()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func providerList(_ chrome: StockToolChrome) -> some View {
        List(selection: Binding(
            get: { model.stockToolSelectedProvider },
            set: { model.stockToolSelectedProvider = $0 }
        )) {
            Section("Providers") {
                ForEach(chrome.providerTitles, id: \.self) { title in
                    Text(title)
                        .tag(title)
                        .a11yCatalog(chrome.providerId(title, toolSlug: toolSlug))
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func providerDetail(_ chrome: StockToolChrome) -> some View {
        let title = model.stockToolSelectedProvider.isEmpty
            ? (chrome.providerTitles.first ?? toolMode.rawValue)
            : model.stockToolSelectedProvider
        // Reuse CodeBrowser panes for shared stock providers; else debug-unique engine list.
        if let kind = Self.mapProvider(title) {
            ProviderView(kind: kind)
        } else {
            DebugUniqueProviderView(title: title, toolSlug: toolSlug)
        }
    }

    private func refreshSelectedProvider() {
        let title = model.stockToolSelectedProvider
        if toolMode == .versionTrackingTool {
            model.runVT(op: "status")
        } else if InProcessEngineHost.isRunning {
            let res = InProcessEngineHost.call("debugger_status")
            model.stockToolDetailText = "\(title)\n\(res.message)"
            model.debuggerStatus = res.message
        } else {
            model.stockToolDetailText = "// \(title)\n// Start program engine for TraceRmi / VT"
        }
    }

    private func detailCopy(for title: String) -> String {
        switch toolMode {
        case .debugger:
            return "Debugger provider (stock). Toolbar → TraceRmi Connect / Launch / Step."
        case .emulator:
            return "Emulator provider (stock). Toolbar → Emulate / Step / Skip / Finish."
        case .versionTrackingTool:
            return "Version Tracking provider (stock). Create session → Run correlators → Apply markup."
        default:
            return title
        }
    }

    /// Map stock tool provider titles onto shared CodeBrowser ProviderKind panes.
    private static func mapProvider(_ title: String) -> ProviderKind? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ": No Program", with: "")
            .replacingOccurrences(of: "Listing:", with: "Listing")
            .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        switch t {
        case "Listing", "Dynamic", "[Dynamic]": return .listing
        case "Decompile", "Decompiler": return .decompiler
        case "Bytes": return .bytes
        case "Program Trees", "Program Tree": return .programTree
        case "Symbol Tree": return .symbolTree
        case "Data Type Manager", "DataTypes Provider": return .dataTypes
        case "Console", "Debug Console": return .console
        case "Functions", "Functions Window": return .functions
        case "Defined Strings": return .strings
        case "Defined Data", "Data Window": return .definedData
        case "Equates Table": return .equates
        case "External Programs": return .externalPrograms
        case "Relocation Table": return .relocations
        case "Memory Map": return .memoryMap
        case "Symbol Table": return .symbolTable
        case "Symbol References": return .symbolReferences
        case "Bookmarks": return .bookmarks
        case "Script Manager": return .scriptManager
        case "Function Graph": return .functionGraph
        case "Registers", "Register Manager": return .registers
        case "Data Type Preview": return .datatypePreview
        case "Disassembled View", "Virtual Disassembler - Current Instruction": return .disassembledView
        case "Checksum Generator": return .checksum
        case "Function Tags": return .functionTags
        case "Comments": return .comments
        case "Python", "Interpreter", "Jython": return .python
        case "Version Tracking Matches",
             "Version Tracking Markup Items",
             "Version Tracking Implied Matches":
            return .versionTracking
        default:
            return nil
        }
    }
}

/// Loads toolbar + provider titles from bundled / parity chrome JSON.
struct StockToolChrome {
    let toolbarGroups: [String]
    let providerTitles: [String]

    static func shared(for name: String) -> StockToolChrome {
        if let cached = cache[name] { return cached }
        let loaded = load(name)
        cache[name] = loaded
        return loaded
    }

    nonisolated(unsafe) private static var cache: [String: StockToolChrome] = [:]

    private static func load(_ name: String) -> StockToolChrome {
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: "chrome.json"),
            Bundle.main.url(forResource: "\(name).chrome", withExtension: "json"),
        ].compactMap { $0 }
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                return fromJSON(root)
            }
        }
        switch name {
        case "Debugger":
            return StockToolChrome(
                toolbarGroups: ["Launch", "Interrupt", "Resume", "Step Into", "Step Over", "Step Out", "TraceRmi Connect", "Save"],
                providerTitles: [
                    "Connections", "Debug Console", "Model", "Dynamic", "Listing", "Decompile",
                    "Registers", "Breakpoints", "Stack", "Threads", "Watches", "Modules", "Memory",
                ]
            )
        case "Emulator":
            return StockToolChrome(
                toolbarGroups: ["Emulate", "Step", "Skip", "Finish", "Interrupt", "Save"],
                providerTitles: [
                    "Dynamic", "Listing", "Decompile", "Registers", "Stack", "Threads",
                    "Watches", "Pcode Stepper", "Objects", "Memory",
                ]
            )
        case "VersionTracking":
            return StockToolChrome(
                toolbarGroups: ["Create Session", "Run Correlators", "Apply Markup", "Save Session"],
                providerTitles: [
                    "Version Tracking Matches",
                    "Version Tracking Markup Items",
                    "Version Tracking Implied Matches",
                ]
            )
        default:
            return StockToolChrome(toolbarGroups: [], providerTitles: [])
        }
    }

    private static func fromJSON(_ root: [String: Any]) -> StockToolChrome {
        let toolbar = (root["toolbarGroups"] as? [String]) ?? []
        var titles: [String] = []
        if let providers = root["providers"] as? [[String: Any]] {
            for p in providers {
                if let t = p["title"] as? String { titles.append(t) }
            }
        }
        if titles.isEmpty {
            titles = (root["defaultActiveProviders"] as? [String]) ?? []
            titles += (root["windowMenuProviders"] as? [String]) ?? []
        }
        return StockToolChrome(toolbarGroups: toolbar, providerTitles: titles)
    }

    func toolbarId(_ group: String, toolSlug: String) -> String {
        let slug = group.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return "ghidra.vibe.\(toolSlug).toolbar.\(slug)"
    }

    /// Canonical provider slug — must match scripts/extract-stock-inventory.py PROVIDER_SLUGS.
    func providerId(_ title: String, toolSlug: String) -> String {
        let slug = Self.canonicalProviderSlug(title)
        return "ghidra.vibe.\(toolSlug).provider.\(slug)"
    }

    static func canonicalProviderSlug(_ title: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let map: [String: String] = [
            "Program Trees": "program_tree",
            "Program Tree": "program_tree",
            "Symbol Tree": "symbol_tree",
            "Data Type Manager": "data_types",
            "DataTypes Provider": "data_types",
            "Listing": "listing",
            "Decompile": "decompiler",
            "Decompiler": "decompiler",
            "Console": "console",
            "Debug Console": "console",
            "Defined Strings": "strings",
            "Functions": "functions",
            "Functions Window": "functions",
            "Memory Map": "memory_map",
            "Symbol Table": "symbol_table",
            "Bytes": "bytes",
            "Bookmarks": "bookmarks",
            "Script Manager": "script_manager",
            "Function Graph": "function_graph",
            "Defined Data": "defined_data",
            "Data Window": "defined_data",
            "Equates Table": "equates",
            "External Programs": "external_programs",
            "Relocation Table": "relocations",
            "Data Type Preview": "datatype_preview",
            "Disassembled View": "disassembled_view",
            "Virtual Disassembler - Current Instruction": "disassembled_view",
            "Register Manager": "registers",
            "Registers": "registers",
            "Symbol References": "symbol_references",
            "Checksum Generator": "checksum",
            "Function Tags": "function_tags",
            "Comments": "comments",
            "Python": "python",
            "Interpreter": "python",
            "Jython": "python",
            "Dynamic": "listing",
            "[Dynamic]": "listing",
        ]
        if let s = map[t] { return s }
        let base = t.split(separator: ":").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? t
        if let s = map[base] { return s }
        if t.hasPrefix("Bytes") { return "bytes" }
        if t.hasPrefix("Listing") { return "listing" }
        return t.lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }
}
