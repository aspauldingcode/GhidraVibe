import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    var toolMode: ToolMode = .splash
    var sheetProvider: ProviderKind?
    var recentProjects: [String] = []
    var selectedRecentProject: String?
    /// Return here after closing Help.
    private var modeBeforeHelp: ToolMode = .workspacePicker
    var selectedSidebar: SidebarItem = .projects
    var extractedRoot: URL?
    var functions: [FunctionRow] = []
    var selectedFunction: FunctionRow?
    var decompiledText: String = "// Select a function after opening a program.\n"
    var listingText: String = ""
    var consoleText: String = ""
    var bytesText: String = ""
    /// Program-engine status (in-process JVM by default). Cursor MCP bridges are optional.
    var mcpStatus: String = "Engine idle"
    var mcpServerURL: String
    /// Vibe extension MCP (Malimite/dyld/rules/RAG/gap/nav) — default :8092
    var vibeMcpURL: String
    var vibeMcpExtBin: String
    var ghidraBin: String
    var headlessBin: String
    var bridgePath: String
    var mcpHeadlessBin: String
    var extractBin: String
    var dyldHelper: String
    var jspaceBin: String
    // Provider row caches (MCP-backed)
    var entropyRows: [String] = []
    var equateRows: [String] = []
    var relocationRows: [String] = []
    var registerRows: [String] = []
    var functionTagRows: [String] = []
    var definedDataRows: [String] = []
    var externalProgramRows: [String] = []
    var symbolRefRows: [String] = []
    var commentRows: [String] = []
    var checksumText: String = ""
    var scriptRows: [String] = []
    var functionGraphText: String = ""
    var functionGraphModel = FunctionGraphModel()
    var selectedGraphNodeId: String?
    var datatypePreviewText: String = ""
    var disassembledViewText: String = ""
    var overviewText: String = ""
    var pythonScriptDraft: String = ""
    var pythonScriptOutput: String = ""
    var debuggerStatus: String = "Debugger MCP idle"
    var debuggerURL: String
    var vcStatus: String = "VC idle"
    /// Selected provider title inside Debugger / Emulator / VT tool shells.
    var stockToolSelectedProvider: String = ""
    var stockToolDetailText: String = ""
    var showMemorySearchAlert = false
    var memorySearchDraft: String = ""
    // Nav / undo (mirrored to vibe MCP)
    var navCanBack: Bool = false
    var navCanForward: Bool = false
    private var localUndoNotes: [String] = []
    private var localRedoNotes: [String] = []
    var showHeadlessHelp = false
    var showGoToAlert = false
    /// First-class File → Open Framework from Shared Cache… sheet.
    var showFrameworkOpenSheet = false
    var showTipOfTheDay = false
    var goToDraft: String = ""
    var statusMessage: String = "Ready"
    var searchQuery: String = ""
    var symbolSearch: String = ""
    var dataTypeSearch: String = ""
    /// Modular CodeBrowser dock (stock DockingWindowManager stand-in).
    var dockLayout: DockLayoutState = .load()
    /// Title-bar drag in progress (drop banner + region highlights).
    var dockDragKind: ProviderKind?
    var dockDropHighlight: DockRegion?
    /// Stock CodeBrowser.tool bottom strip — derived from dock layout.
    var bottomStripVisible: Bool {
        get { dockLayout.hasVisibleBottomStrip }
        set {
            if newValue {
                for kind in ProviderKind.bottomStrip { showProvider(kind) }
            } else {
                for kind in ProviderKind.bottomStrip { closeProvider(kind) }
            }
        }
    }
    /// Console / Bookmarks stack under Listing — derived from dock layout.
    var consoleStackVisible: Bool {
        get { dockLayout.hasVisibleConsole }
        set {
            if newValue {
                showProvider(.console)
            } else {
                closeConsoleStack()
            }
        }
    }
    /// Closed modular panes (stock CodeBrowser: each provider can be dismissed).
    var hiddenProviders: Set<ProviderKind> {
        get { dockLayout.hiddenSet }
        set {
            dockLayout.hidden = newValue.map(\.rawValue)
            persistDock()
        }
    }
    /// Auto Analyze in flight (status-bar Cancel).
    var analysisBusy: Bool = false
    var analysisTask: Task<Void, Never>?
    /// Wall-clock start for the status-bar task monitor (elapsed “12s”).
    var taskMonitorStartedAt: Date?
    /// Whole-bundle Mach-O map (Open App Bundle…).
    var bundleBinaryRows: [String] = []
    var consoleScrollLocked: Bool = false
    var consoleInputDraft: String = ""
    var dyldCachePath: String?
    var dyldImages: [String] = []
    var dyldQuery: String = ""
    var selectedDyldImage: String?
    /// IDA-like: load module first; Auto Analyze is a separate step.
    var dyldRunAnalysisOnImport: Bool = false
    var dyldImportBusy: Bool = false
    var dyldListingBusy: Bool = false
    var dyldFilterTask: Task<Void, Never>?
    var agentEnabled: Bool
    var showAgentWelcome: Bool
    var agentOptedOut: Bool
    var apiKeyFilePath: String
    var agentMessages: [AgentMessage] = []
    var agentDraft: String = ""
    /// Display label: ollama | openai_compat | anemll_stub
    var agentBackend: String = "ollama"
    /// Local Ollama / OpenAI-compat base (Settings + env).
    var agentBaseURL: String = ""
    var agentModel: String = ""
    var agentUseLocalOllama: Bool = true
    var agentBusy: Bool = false
    var agentPendingEdits: [AgentPendingEdit] = []
    var agentModelPicker: [String] = []
    /// Mixture-of-experts routing (local experts + optional API escalation).
    var agentMoE: AgentMoESettings = AgentMoESettings()
    /// Last MoE route label for status / GuiControl.
    var agentMoELastRoute: String = ""
    var jspaceStatus: String = "JSpace idle"
    var ragQuery: String = ""
    var ragResult: String = ""
    var rulesText: String = ""
    var projectPath: String = ""
    var projectPrograms: [String] = []
    var selectedProjectProgram: String?
    /// Outline selection ids (NativeOutlineTree) for stock left trees.
    var selectedProgramTreeNodeId: String?
    var selectedSymbolTreeNodeId: String?
    var selectedDataTypeNodeId: String?
    var currentProgramName: String = ""
    var programTreeNodes: [String] = ["(open a program)"]
    var symbolNodes: [String] = []
    var dataTypeNodes: [String] = ["builtin", "windows", "mac"]
    var stringRows: [String] = []
    var memoryMapRows: [String] = []
    var symbolTableRows: [String] = []
    var bookmarkRows: [String] = []
    var appleHelper: String
    var appleBundlePath: String = ""
    var appleResourceRows: [String] = []
    var swiftClassRows: [String] = []
    /// ObjC class names harvested from `-[Class …]` / `+[Class …]` function names.
    var objcClassRows: [String] = []
    var codeEditorText: String = "// Code editor — load decompile or edit agent translations\n"
    // Malimite SQLite project (scripts/lib/malimite)
    var malimiteDBPath: String = ""
    var malimiteProjectDir: String = ""
    var malimiteInfoSummary: String = ""
    var malimiteStatsText: String = ""
    var malimiteClassRows: [String] = []
    var selectedMalimiteClass: String?
    var malimiteFunctionRows: [String] = []
    var selectedMalimiteFunction: String?
    var malimiteFunctionCode: String = ""
    var malimiteStringRows: [String] = []
    var malimiteEntrypointRows: [String] = []
    var malimiteRefQuery: String = ""
    var malimiteRefRows: [String] = []
    var malimiteLibraryRows: [String] = []
    var malimiteTranslateAction: String = "auto_fix"
    var malimiteTranslateLanguage: String = "Swift"
    var malimiteTranslateInput: String = ""
    var malimiteTranslateOutput: String = ""

    private var controlServer: GuiControlServer?

    var mcpBaseURL: URL? {
        URL(string: mcpServerURL)
    }

    var vibeBaseURL: URL? {
        URL(string: vibeMcpURL)
    }

    var apiBackendAvailable: Bool {
        let path = apiKeyFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return false }
        return FileManager.default.isReadableFile(atPath: path)
    }

    init() {
        let env = ProcessInfo.processInfo.environment
        mcpServerURL = env["GHIDRA_MCP_URL"] ?? env["GHIDRA_MCP_SERVER"] ?? "http://127.0.0.1:8089"
        vibeMcpURL = env["GHIDRA_VIBE_MCP_EXT_URL"] ?? "http://127.0.0.1:8092"
        vibeMcpExtBin = env["GHIDRA_VIBE_MCP_EXT"] ?? ""
        debuggerURL = env["GHIDRA_MCP_DEBUGGER_URL"] ?? "http://127.0.0.1:8099"
        ghidraBin = env["GHIDRA_VIBE_BIN"] ?? "ghidra"
        headlessBin = env["GHIDRA_VIBE_HEADLESS"] ?? "ghidra-analyzeHeadless"
        bridgePath = env["GHIDRA_VIBE_MCP_BRIDGE"] ?? ""
        mcpHeadlessBin = env["GHIDRA_VIBE_MCP_HEADLESS"] ?? ""
        extractBin = env["GHIDRA_VIBE_EXTRACT"] ?? ""
        dyldHelper = env["GHIDRA_VIBE_DYLD"] ?? ""
        appleHelper = env["GHIDRA_VIBE_APPLE"] ?? ""
        jspaceBin = env["GHIDRA_VIBE_JSPACE"] ?? ""
        apiKeyFilePath = env["GHIDRA_VIBE_API_KEY_FILE"] ?? ""
        agentBaseURL = UserDefaults.standard.string(forKey: "ghidra.vibe.agent.baseURL")
            ?? env["GHIDRA_VIBE_AI_BASE_URL"]
            ?? env["AI_LOCAL_BASE_URL"]
            ?? env["OLLAMA_HOST"]
            ?? "http://127.0.0.1:11434"
        agentModel = UserDefaults.standard.string(forKey: "ghidra.vibe.agent.model")
            ?? env["GHIDRA_VIBE_AI_MODEL"]
            ?? env["AI_LOCAL_DEFAULT_MODEL"]
            ?? "qwen2.5-coder:3b"
        if UserDefaults.standard.object(forKey: "ghidra.vibe.agent.useLocalOllama") != nil {
            agentUseLocalOllama = UserDefaults.standard.bool(forKey: "ghidra.vibe.agent.useLocalOllama")
        } else {
            agentUseLocalOllama = env["GHIDRA_VIBE_AI_CLOUD"] != "1"
        }
        let ai = env["GHIDRA_VIBE_AI"] ?? "1"
        let optedOut = UserDefaults.standard.bool(forKey: "ghidra.vibe.agent.optOut") || ai == "0"
        let enabled = !optedOut
        let welcome = enabled && !UserDefaults.standard.bool(forKey: "ghidra.vibe.agent.welcomeDismissed")
        agentOptedOut = optedOut
        agentEnabled = enabled
        showAgentWelcome = welcome
        agentMoE = AgentMoESettings.load(env: env, fallbackModel: agentModel)
        let cfg = LocalAIConfig.resolve(
            userBaseURL: agentBaseURL,
            userModel: agentModel,
            apiKeyFile: apiKeyFilePath,
            preferCloud: !agentUseLocalOllama
        )
        agentBackend = cfg.backend.rawValue
        if let install = env["GHIDRA_INSTALL_DIR"] {
            statusMessage = "Ghidra install: \(install)"
        }
        if let last = UserDefaults.standard.string(forKey: "ghidra.vibe.lastProject"),
           !last.isEmpty, FileManager.default.fileExists(atPath: last)
        {
            projectPath = last
        }
        if let lastProg = UserDefaults.standard.string(forKey: "ghidra.vibe.lastProgram"),
           !lastProg.isEmpty
        {
            selectedProjectProgram = lastProg.hasPrefix("/") ? lastProg : "/\(lastProg)"
            currentProgramName = (lastProg as NSString).lastPathComponent
        }
        // Do not auto-start the engine here — onAppear starts it with the project/program.
        // refreshMCPHealth() used to race-start an empty JVM (no --program).
        loadSampleWorkspaceHints()
        discoverDyldCache()
        refreshRecentProjects()
        if !projectPath.isEmpty {
            refreshProjectPrograms()
        }
    }

    func finishSplash() {
        // Smoke / automation: land on Project Window without Welcome/Workspace.
        // Env (when launched under nix/scripts) or one-shot defaults key from run-smoke.sh.
        let startMode = ProcessInfo.processInfo.environment["GHIDRA_VIBE_START_MODE"] ?? ""
        let smokeProject = UserDefaults.standard.bool(forKey: "ghidra.vibe.smokeStartProject")
        if startMode == "project" || smokeProject {
            UserDefaults.standard.set(false, forKey: "ghidra.vibe.smokeStartProject")
            UserDefaults.standard.set(true, forKey: "ghidra.vibe.welcomeHelpSeen")
            enterProjectWindow()
            return
        }
        // Stock order: splash → Welcome/Help (first run) → Tip of the Day → workspace / project.
        if !UserDefaults.standard.bool(forKey: "ghidra.vibe.welcomeHelpSeen") {
            modeBeforeHelp = projectPath.isEmpty ? .workspacePicker : .projectWindow
            toolMode = .welcomeHelp
            statusMessage = "Welcome"
            return
        }
        enterPostWelcomeFlow()
    }

    /// After Welcome Help (or when Welcome already seen): Tip → workspace/project.
    func enterPostWelcomeFlow() {
        if projectPath.isEmpty {
            toolMode = .workspacePicker
            statusMessage = "Select a project or workspace"
        } else {
            toolMode = .projectWindow
            statusMessage = "Project: \(URL(fileURLWithPath: projectPath).lastPathComponent)"
        }
        if TipOfTheDay.showOnStartup {
            showTipOfTheDay = true
        }
    }

    func enterProjectWindow() {
        toolMode = .projectWindow
        statusMessage = "Project Window"
        refreshProjectPrograms()
        ensureProgramEngineRunning(loadProgram: true)
    }

    func showWelcomeHelp() {
        if toolMode != .welcomeHelp {
            modeBeforeHelp = toolMode == .splash ? .workspacePicker : toolMode
        }
        toolMode = .welcomeHelp
        UserDefaults.standard.set(true, forKey: "ghidra.vibe.welcomeHelpSeen")
        statusMessage = "Ghidra Help"
    }

    func dismissWelcomeHelp() {
        UserDefaults.standard.set(true, forKey: "ghidra.vibe.welcomeHelpSeen")
        switch modeBeforeHelp {
        case .splash, .welcomeHelp:
            enterPostWelcomeFlow()
        default:
            toolMode = modeBeforeHelp
            statusMessage = toolMode.rawValue
            if TipOfTheDay.showOnStartup { showTipOfTheDay = true }
        }
    }

    func refreshRecentProjects() {
        var paths = UserDefaults.standard.stringArray(forKey: "ghidra.vibe.recentProjects") ?? []
        if let last = UserDefaults.standard.string(forKey: "ghidra.vibe.lastProject"), !last.isEmpty {
            paths.insert(last, at: 0)
        }
        // Discover projects under repo default folder
        let cwd = FileManager.default.currentDirectoryPath
        let root = URL(fileURLWithPath: cwd).appendingPathComponent("ghidra-vibe-projects")
        if let en = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in en where url.pathExtension == "gpr" {
                paths.append(url.path)
            }
        }
        var seen = Set<String>()
        recentProjects = paths.filter { path in
            guard !seen.contains(path), FileManager.default.fileExists(atPath: path) else { return false }
            seen.insert(path)
            return true
        }
        recentProjects = Array(recentProjects.prefix(20))
    }

    func rememberProject(_ path: String) {
        projectPath = path
        UserDefaults.standard.set(path, forKey: "ghidra.vibe.lastProject")
        var recent = UserDefaults.standard.stringArray(forKey: "ghidra.vibe.recentProjects") ?? []
        recent.removeAll { $0 == path }
        recent.insert(path, at: 0)
        UserDefaults.standard.set(Array(recent.prefix(20)), forKey: "ghidra.vibe.recentProjects")
        refreshRecentProjects()
    }

    func openSelectedRecentProject() {
        guard let path = selectedRecentProject else { return }
        rememberProject(path)
        refreshProjectPrograms()
        enterProjectWindow()
        statusMessage = "Opened \(URL(fileURLWithPath: path).lastPathComponent)"
    }

    func startControlServer() {
        let env = ProcessInfo.processInfo.environment
        let url = env["GHIDRA_VIBE_GUI_URL"] ?? "http://127.0.0.1:8091"
        let port = UInt16(URL(string: url)?.port ?? 8091)
        let server = GuiControlServer(port: port)
        server.start(model: self)
        controlServer = server
    }

    var filteredFunctions: [FunctionRow] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return functions }
        return functions.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.address.localizedCaseInsensitiveContains(q)
        }
    }

    var filteredSymbols: [String] {
        let q = symbolSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = symbolNodes.isEmpty ? functions.map(\.name) : symbolNodes
        guard !q.isEmpty else { return Array(base.prefix(500)) }
        return Array(base.filter { $0.localizedCaseInsensitiveContains(q) }.prefix(500))
    }

    var         headlessHelpText: String {
        """
        GUI: Ghidra engine runs in-process — that is normal use, not “connect MCP”.
        Greyed provider buttons mean that control is not wired yet; Listing / Decompile / Functions still work.
        Headless CLI (agents/batch): ghidra-vibe-mcp-headless. Cursor bridges optional (GHIDRA_VIBE_CURSOR_BRIDGE=1).
        """
    }

    func controlState() -> [String: Any] {
        [
            "ok": true,
            "toolMode": toolMode.rawValue,
            "sheetProvider": sheetProvider?.rawValue ?? "",
            "sidebar": selectedSidebar.idKey,
            "searchQuery": searchQuery,
            "statusMessage": statusMessage,
            "mcpStatus": mcpStatus,
            "projectPath": projectPath,
            "currentProgram": currentProgramName,
            "functionCount": functions.count,
            "selectedFunction": selectedFunction?.name ?? "",
            "selectedAddress": selectedFunction?.address ?? "",
            "dyldCache": dyldCachePath ?? "",
            "dyldImportBusy": dyldImportBusy,
            "dyldRunAnalysisOnImport": dyldRunAnalysisOnImport,
            "analysisBusy": analysisBusy,
            "taskMonitorActive": taskMonitorActive,
            "taskMonitorTitle": taskMonitorTitle,
            "taskMonitorElapsedSeconds": Int(taskMonitorElapsed),
            "agentEnabled": agentEnabled,
            "agentSidebarVisible": dockLayout.agentSidebarVisible,
            "agentBusy": agentBusy,
            "agentBackend": agentBackend,
            "agentModel": agentModel,
            "agentBaseURL": agentBaseURL,
            "agentMoE": agentMoE.enabled,
            "agentMoERoute": agentMoELastRoute,
            "apiBackendAvailable": apiBackendAvailable,
            "jspaceStatus": jspaceStatus,
            "agentPendingEditCount": agentPendingEdits.count,
            // Long enough for GuiControl smokes to assert real C (e.g. whoami entry).
            "decompilePreview": String(decompiledText.prefix(4000)),
            "functionGraphFunction": functionGraphModel.function,
            "functionGraphNodeCount": functionGraphModel.nodes.count,
            "functionGraphEdgeCount": functionGraphModel.edges.count,
            "functionGraphEntry": functionGraphModel.entry,
            "functionGraphPreview": String(functionGraphText.prefix(2000)),
            "dockFloating": dockLayout.floating,
            "dockHiddenCount": dockLayout.hidden.count,
            "classCount": objcClassRows.count + swiftClassRows.filter { !$0.hasPrefix("(") }.count,
            "objcClassCount": objcClassRows.count,
            "objcClassPreview": Array(objcClassRows.prefix(60)),
            "swiftClassPreview": Array(swiftClassRows.prefix(40)),
            "symbolPreview": Array(symbolNodes.prefix(40)),
        ]
    }

    func navigate(pane: String) {
        let key = pane.lowercased().replacingOccurrences(of: " ", with: "_")
        if key.contains("workspace") || key.contains("picker") {
            toolMode = .workspacePicker
            statusMessage = "Select Project"
            return
        }
        if key.contains("help") || key.contains("welcome") {
            showWelcomeHelp()
            return
        }
        if key.contains("project") {
            toolMode = .projectWindow
            statusMessage = "Project Window"
            return
        }
        if key.contains("codebrowser") || key == "browser" {
            toolMode = .codeBrowser
            statusMessage = "CodeBrowser"
            return
        }
        if let kind = ProviderKind.allCases.first(where: {
            $0.rawValue == key || $0.title.lowercased() == pane.lowercased()
        }) {
            showProvider(kind)
            return
        }
        if let item = SidebarItem.allCases.first(where: { $0.idKey == key || $0.rawValue.lowercased() == key }) {
            selectedSidebar = item
            mapLegacySidebar(item)
            statusMessage = "Navigated to \(item.rawValue)"
        }
    }

    private func mapLegacySidebar(_ item: SidebarItem) {
        switch item {
        case .projects: toolMode = .projectWindow
        case .functions: showProvider(.functions)
        case .decompiler: toolMode = .codeBrowser; sheetProvider = nil
        case .listing: toolMode = .codeBrowser
        case .xrefs: showProvider(.strings)
        case .inspector: showProvider(.mcp)
        case .agent: showProvider(.agent)
        }
    }

    func isProviderVisible(_ kind: ProviderKind) -> Bool {
        dockLayout.isDockVisible(kind)
    }

    var hasVisibleLeftDock: Bool {
        dockLayout.hasVisibleLeft
    }

    var showDecompilerPane: Bool {
        dockLayout.hasVisibleRight
    }

    /// Stock-like bottom task monitor: analysis, DSC import, engine boot, long jobs.
    var taskMonitorActive: Bool {
        if analysisBusy || dyldImportBusy || dyldListingBusy { return true }
        let s = statusMessage.lowercased()
        let m = mcpStatus.lowercased()
        if m.contains("starting") { return true }
        if s.contains("analyz") && (s.contains("…") || s.contains("...")) { return true }
        if s.hasPrefix("decompiling") { return true }
        if s.hasPrefix("building function graph") { return true }
        if s.contains("importing") || s.contains("extracting") { return true }
        return false
    }

    var taskMonitorTitle: String {
        if analysisBusy { return "Auto Analysis" }
        if dyldImportBusy { return "DSC Import" }
        if dyldListingBusy { return "DSC Listing" }
        let s = statusMessage.lowercased()
        let m = mcpStatus.lowercased()
        if m.contains("starting") { return "Starting Engine" }
        if s.hasPrefix("decompiling") { return "Decompile" }
        if s.hasPrefix("building function graph") { return "Function Graph" }
        if s.contains("import") { return "Import" }
        if s.contains("analyz") { return "Analysis" }
        return "Working"
    }

    var taskMonitorElapsed: TimeInterval {
        guard let start = taskMonitorStartedAt else { return 0 }
        return max(0, Date().timeIntervalSince(start))
    }

    var taskMonitorElapsedLabel: String {
        let secs = Int(taskMonitorElapsed)
        if secs < 60 { return "\(secs)s" }
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    func beginTaskMonitor() {
        if taskMonitorStartedAt == nil {
            taskMonitorStartedAt = Date()
        }
    }

    func endTaskMonitor() {
        taskMonitorStartedAt = nil
    }

    func persistDock() {
        dockLayout.save()
    }

    func selectDockTab(_ kind: ProviderKind, in region: DockRegion) {
        dockLayout.setActive(kind, in: region)
        if region == .right {
            sheetProvider = kind == .decompiler ? nil : kind
        }
        persistDock()
        statusMessage = "Showing \(kind.title)"
    }

    func moveProvider(_ kind: ProviderKind, to region: DockRegion) {
        toolMode = .codeBrowser
        dockLayout.move(kind, to: region, activate: true)
        if region == .right {
            sheetProvider = kind == .decompiler ? nil : kind
        } else if kind == sheetProvider {
            sheetProvider = nil
        }
        persistDock()
        statusMessage = "Docked \(kind.title) to \(region.title)"
    }

    func floatProvider(_ kind: ProviderKind) {
        toolMode = .codeBrowser
        dockLayout.float(kind)
        if kind == sheetProvider { sheetProvider = nil }
        persistDock()
        statusMessage = "Floating \(kind.title)"
        NotificationCenter.default.post(
            name: .ghidraVibeFloatProvider,
            object: nil,
            userInfo: ["kind": kind.rawValue]
        )
    }

    func reattachProvider(_ kind: ProviderKind) {
        toolMode = .codeBrowser
        dockLayout.reattach(kind)
        if dockLayout.homeRegion(for: kind) == .right {
            sheetProvider = kind == .decompiler ? nil : kind
        }
        persistDock()
        statusMessage = "Reattached \(kind.title)"
        NotificationCenter.default.post(
            name: .ghidraVibeUnfloatProvider,
            object: nil,
            userInfo: ["kind": kind.rawValue]
        )
    }

    func resetDockLayoutToStock() {
        dockLayout = .stockDefault()
        sheetProvider = nil
        persistDock()
        statusMessage = "Reset dock layout to stock CodeBrowser"
    }

    func showProvider(_ kind: ProviderKind) {
        toolMode = .codeBrowser
        ensureProgramEngineRunning(loadProgram: false)
        if dockLayout.isFloating(kind) {
            reattachProvider(kind)
            return
        }
        dockLayout.show(kind)
        let region = dockLayout.region(containing: kind) ?? dockLayout.homeRegion(for: kind)
        if region == .right {
            sheetProvider = kind == .decompiler ? nil : kind
        }
        persistDock()
        statusMessage = "Showing \(kind.title)"
    }

    func closeProvider(_ kind: ProviderKind) {
        let wasFloating = dockLayout.isFloating(kind)
        dockLayout.close(kind)
        if kind == sheetProvider {
            sheetProvider = nil
        }
        persistDock()
        if wasFloating {
            NotificationCenter.default.post(
                name: .ghidraVibeUnfloatProvider,
                object: nil,
                userInfo: ["kind": kind.rawValue]
            )
        }
        statusMessage = "Closed \(kind.title) — Window → \(kind.title) to reopen"
    }

    func closeConsoleStack() {
        closeProvider(.console)
    }

    func beginProviderDockDrag(_ kind: ProviderKind) {
        dockDragKind = kind
        statusMessage = "Dragging \(kind.title) — drop on a dock region"
    }

    /// Stock provider local-toolbar actions (inventory / chrome.json ids).
    func providerChromeAction(id: String, kind: ProviderKind) {
        switch id {
        case "ghidra.vibe.provider.decompiler.refresh":
            decompileSelected()
        case "ghidra.vibe.provider.listing.goto_field":
            promptGoTo()
        case "ghidra.vibe.provider.symbol_tree.snapshot",
             "ghidra.vibe.provider.symbol_tree.filter_go":
            refreshSymbolTable()
        case "ghidra.vibe.provider.data_types.open_archive",
             "ghidra.vibe.provider.data_types.filter_go":
            refreshDataTypes()
        case "ghidra.vibe.provider.console.lock":
            consoleScrollLocked.toggle()
            statusMessage = consoleScrollLocked ? "Console scroll locked" : "Console scroll unlocked"
        case "ghidra.vibe.provider.console.clear":
            clearConsole()
        case "ghidra.vibe.provider.console.copy":
            copyConsoleToClipboard()
        case "ghidra.vibe.provider.decompiler.export":
            agentDraft = decompiledText
            statusMessage = "Decompile copied toward Agent / clipboard path"
        case "ghidra.vibe.provider.program_tree.create_tree",
             "ghidra.vibe.provider.program_tree.create_folder",
             "ghidra.vibe.provider.program_tree.create_fragment",
             "ghidra.vibe.provider.symbol_tree.create_namespace",
             "ghidra.vibe.provider.symbol_tree.create_class",
             "ghidra.vibe.provider.symbol_tree.create_symbol",
             "ghidra.vibe.provider.data_types.create":
            runProviderCreate(id)
        case "ghidra.vibe.provider.data_types.back":
            statusMessage = "Previous data type"
            refreshDataTypes()
        case "ghidra.vibe.provider.data_types.forward":
            statusMessage = "Next data type"
            refreshDataTypes()
        case "ghidra.vibe.provider.data_types.settings",
             "ghidra.vibe.provider.listing.settings",
             "ghidra.vibe.provider.decompiler.options":
            statusMessage = "\(kind.title) options — use provider pane controls"
            consoleAppend("Opened \(id) settings surface")
        case "ghidra.vibe.provider.listing.marker":
            runListingWrite("listing_add_bookmark")
        default:
            let tip = A11yCatalog.hoverTip(for: id, fallback: kind.title)
            statusMessage = "\(tip) — not wired yet"
        }
    }

    func runProviderCreate(_ id: String) {
        ensureVibeMCP()
        let tool = id.split(separator: ".").last.map(String.init) ?? id
        statusMessage = "\(tool)…"
        Task {
            let resp = await self.vibePost("provider_create", body: [
                "op": tool,
                "address": self.selectedFunction?.address ?? self.goToDraft,
                "name": self.selectedFunction?.name ?? "",
            ])
            await MainActor.run {
                self.consoleAppend("\(tool): \(resp.text.prefix(240))")
                self.statusMessage = resp.ok ? "\(tool) OK" : "\(tool) pending"
                if tool.contains("symbol") { self.refreshSymbolTable() }
                if tool.contains("data") { self.refreshDataTypes() }
            }
        }
    }

    func selectFunction(name: String?, address: String?, id: String?) {
        if let id, let row = functions.first(where: { $0.id == id }) {
            selectedFunction = row
        } else if let address {
            let want = Self.normalizeAddressKey(address)
            if let row = functions.first(where: { Self.normalizeAddressKey($0.address) == want }) {
                selectedFunction = row
            } else if !want.isEmpty {
                // Address may be outside the loaded function page — still decompile it.
                let label = (name?.isEmpty == false) ? name! : "FUN_\(want)"
                selectedFunction = FunctionRow(id: "addr-\(want)", name: label, address: address)
            }
        } else if let name, let row = functions.first(where: {
            $0.name == name || $0.name.hasSuffix(name) || name.hasSuffix($0.name)
        }) {
            selectedFunction = row
        }
        if selectedFunction != nil {
            decompileSelected()
            fetchListing()
        }
    }

    private static func normalizeAddressKey(_ address: String) -> String {
        var s = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        // Drop leading zeros for comparison (keep at least one digit).
        while s.count > 1 && s.first == "0" { s.removeFirst() }
        return s
    }

    private static func isUsableDecompileText(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        let lower = t.lowercased()
        if lower.contains("\"error\"") { return false }
        if lower.contains("<html") || lower.contains("404 not found") { return false }
        if t == "// No Function" || t.contains("Select a function") { return false }
        return true
    }

    func runAction(id: String) {
        switch id {
        case "mcp_health": refreshMCPHealth()
        case "fetch_functions": fetchFunctionsViaMCP()
        case "decompile": decompileSelected()
        case "open_framework_from_dsc", "open_framework", "framework_open":
            presentFrameworkOpenSheet()
        case "dyld_open", "dyld_discover", "show_dsc", "open_shared_cache":
            // Advanced: full Shared Cache index provider (same engine as Framework Open).
            showProvider(.dsc)
            openDyldCache()
        case "codebrowser", "show_codebrowser": toolMode = .codeBrowser
        case "show_project": enterProjectWindow()
        case "show_workspace": toolMode = .workspacePicker
        case "show_help", "welcome_help": showWelcomeHelp()
        case "extract": runDyldExtract()
        case "start_bridge", "start_mcp": startMCPBridge()
        case "rag_index", "jspace_index": indexJSpace()
        case "rag_init", "jspace_init": initJSpacePlaybook()
        case "import_file": importFilePicker()
        case "open_project": openProjectPicker()
        case "new_project": newProject()
        case "save_program": saveProgram()
        case "close_program": closeProgram()
        case "auto_analyze": autoAnalyze()
        case "cancel_analyze", "cancel_auto_analyze": cancelAutoAnalyze()
        case "dyld_analyze_on":
            dyldRunAnalysisOnImport = true
            statusMessage = "DSC import will auto-analyze after load"
        case "dyld_analyze_off":
            dyldRunAnalysisOnImport = false
            statusMessage = "DSC import will skip auto-analyze"
        case "refresh_classes", "refresh_objc_classes":
            refreshObjcClassesFromFunctions()
            refreshSwiftClasses()
        case "refresh_symbols":
            refreshSymbolTable()
        case "goto": promptGoTo()
        case "undo": undoAction()
        case "redo": redoAction()
        case "nav_back": navBack()
        case "nav_fwd", "nav_forward": navForward()
        case "clear_selection": clearSelection()
        case "refresh_debugger": refreshDebuggerStatus()
        case "refresh_vc": refreshVCStatus()
        case "search_strings": showProvider(.strings); probeStrings()
        case "search_functions": showProvider(.functions); fetchFunctionsViaMCP()
        case "show_listing": showProvider(.listing)
        case "show_decompiler": showProvider(.decompiler)
        case "show_program_tree": showProvider(.programTree)
        case "show_symbol_tree": showProvider(.symbolTree)
        case "show_data_types": showProvider(.dataTypes)
        case "show_console": showProvider(.console)
        case "show_functions": showProvider(.functions)
        case "show_strings": showProvider(.strings)
        case "show_memory_map": showProvider(.memoryMap)
        case "show_symbol_table": showProvider(.symbolTable)
        case "show_bytes": showProvider(.bytes)
        case "show_bookmarks": showProvider(.bookmarks)
        case "show_script_manager": showProvider(.scriptManager)
        case "show_function_graph": showProvider(.functionGraph)
        case "refresh_function_graph", "function_graph_refresh":
            showProvider(.functionGraph)
            refreshFunctionGraph()
        case "show_entropy": showProvider(.entropy)
        case "show_overview": showProvider(.overview)
        case "show_defined_data": showProvider(.definedData)
        case "show_equates": showProvider(.equates)
        case "show_external_programs": showProvider(.externalPrograms)
        case "show_relocations": showProvider(.relocations)
        case "show_datatype_preview": showProvider(.datatypePreview)
        case "show_disassembled_view": showProvider(.disassembledView)
        case "show_registers": showProvider(.registers)
        case "show_symbol_references": showProvider(.symbolReferences)
        case "show_checksum": showProvider(.checksum)
        case "show_function_tags": showProvider(.functionTags)
        case "show_comments": showProvider(.comments)
        case "show_python": showProvider(.python)
        case "show_mcp": showProvider(.mcp)
        case "show_agent":
            enableAgentSidebar()
            dockLayout.agentSidebarVisible = true
            persistDock()
            showProvider(.agent)
        case "toggle_agent_sidebar", "agent_sidebar":
            toggleAgentSidebar()
        case "agent_playbook", "autonomous_re":
            runAutonomousREPlaybook()
        case "show_rag": showProvider(.rag)
        case "show_rules": showProvider(.rules)
        case "show_apple", "show_apple_bundle": showProvider(.appleBundle)
        case "show_swift_classes":
            showProvider(.swiftClasses)
            refreshObjcClassesFromFunctions()
            refreshSwiftClasses()
        case "show_code_editor": showProvider(.codeEditor)
        case "show_version_tracking", "version_tracking": openVersionTracking()
        case "import_apple": pickAppleBundle(); runMalimiteAnalyze(binOnly: false)
        case "open_app_bundle": openAppBundlePicker()
        case "tip_of_the_day": showTipOfTheDay = true
        case "about": statusMessage = "GhidraVibe — native Apple RE (engine + DSC + Swift/ObjC)"
        case "headless_help": showHeadlessHelp = true
        case "bsim_search", "bsim_overview":
            openBSim()
        case "edit_cut":
            runListingWrite("listing_clear_code")
            copyListingOrDecompileToClipboard()
            statusMessage = "Cut — cleared code bytes + copied to clipboard"
        case "edit_copy":
            copyListingOrDecompileToClipboard()
            statusMessage = "Copied listing / decompile to clipboard"
        case "edit_paste":
            if let s = NSPasteboard.general.string(forType: .string), !s.isEmpty {
                goToDraft = s.trimmingCharacters(in: .whitespacesAndNewlines)
                statusMessage = "Paste — clipboard text in Go To field (apply with Listing tools)"
            } else {
                statusMessage = "Clipboard empty"
            }
        case "search_memory":
            showMemorySearchAlert = true
        case "listing_disassemble", "listing_define_data", "listing_clear_code",
             "listing_create_label", "listing_create_function", "listing_add_bookmark",
             "listing_create_structure":
            runListingWrite(id)
        case "open_debugger", "show_debugger":
            openDebugger()
        case "open_emulator", "show_emulator":
            openEmulator()
        case "vc_add", "vc_checkout", "vc_update", "vc_checkin", "vc_undo", "vc_find":
            runVCAction(id)
        default: statusMessage = "Unknown action: \(id)"
        }
    }

    func copyListingOrDecompileToClipboard() {
        let text = listingText.isEmpty ? decompiledText : listingText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func performMemorySearch() {
        showMemorySearchAlert = false
        let pattern = memorySearchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            statusMessage = "Memory search — empty pattern"
            return
        }
        statusMessage = "Searching memory…"
        showProvider(.bytes)
        if InProcessEngineHost.isRunning {
            let res = InProcessEngineHost.call("search_memory", args: [
                "pattern": pattern,
                "address": selectedFunction?.address ?? goToDraft,
            ])
            consoleAppend("search_memory: \(res.message)")
            if res.ok {
                if let addrs = res.json["addresses"] as? [Any] {
                    bytesText = addrs.map { "\($0)" }.joined(separator: "\n")
                } else {
                    bytesText = res.message
                }
                statusMessage = "Memory search: \(res.json["count"] ?? "?") hit(s)"
            } else {
                statusMessage = "Memory search failed: \(res.message)"
            }
            return
        }
        ensureVibeMCP()
        Task {
            let resp = await self.vibePost("search_memory", body: [
                "pattern": pattern,
                "address": self.selectedFunction?.address ?? self.goToDraft,
            ])
            await MainActor.run {
                self.consoleAppend("search_memory: \(resp.text.prefix(400))")
                let pending = (resp.json as? [String: Any])?["pending"] as? Bool ?? false
                if resp.ok && !pending {
                    self.bytesText = String(resp.text.prefix(8000))
                    self.statusMessage = "Memory search complete"
                } else {
                    self.statusMessage = "Memory search failed (engine required)"
                }
            }
        }
    }

    func runListingWrite(_ tool: String) {
        let addr = selectedFunction?.address ?? goToDraft
        statusMessage = "\(tool)…"
        let args: [String: Any] = ["address": addr, "name": selectedFunction?.name ?? ""]
        if InProcessEngineHost.isRunning {
            let res = InProcessEngineHost.call(tool, args: args)
            consoleAppend("\(tool): \(res.message)")
            statusMessage = res.ok ? "\(tool) OK" : "\(tool) failed: \(res.message)"
            if res.ok {
                decompileSelected()
                fetchListing()
            }
            return
        }
        ensureVibeMCP()
        Task {
            let resp = await self.vibePost(tool, body: args)
            await MainActor.run {
                self.consoleAppend("\(tool): \(resp.text.prefix(240))")
                let pending = (resp.json as? [String: Any])?["pending"] as? Bool ?? false
                self.statusMessage = (resp.ok && !pending) ? "\(tool) OK" : "\(tool) failed"
                if resp.ok && !pending { self.decompileSelected(); self.fetchListing() }
            }
        }
    }

    func runVCAction(_ id: String) {
        // Stock: VC toolbar is present but greyed without a shared repository.
        let op = id.hasPrefix("vc_") ? id : "vc_\(id)"
        if InProcessEngineHost.isRunning {
            let st = InProcessEngineHost.call("vc_status")
            vcStatus = st.message
            let res = InProcessEngineHost.call("vc_op", args: ["op": op])
            statusMessage = res.message
            consoleAppend("VC \(op): \(res.message)")
            return
        }
        refreshVCStatus()
        vcStatus = "No shared repository (local project)"
        statusMessage = "VC \(op) — greyed (no shared repository)"
        consoleAppend("VC \(op): stock-grey without Ghidra Server repository")
    }

    func openBSim() {
        showProvider(.functions)
        if InProcessEngineHost.isRunning {
            let res = InProcessEngineHost.call("bsim_status")
            statusMessage = res.message
            consoleAppend("BSim: \(res.message)")
            stockToolDetailText = res.message
        } else {
            statusMessage = "BSim — configure a BSim database (Feature present; engine idle)"
            consoleAppend("BSim: engine Feature available when program engine is running")
        }
    }

    func refreshFunctionGraph() {
        let name = selectedFunction?.name ?? ""
        let addr = selectedFunction?.address ?? goToDraft
        statusMessage = "Building function graph…"
        if addr.isEmpty && name.isEmpty {
            functionGraphModel = FunctionGraphModel()
            functionGraphText = "// Select a function, then Refresh Graph"
            statusMessage = "Function Graph: no function selected"
            return
        }
        if InProcessEngineHost.isRunning {
            let res = InProcessEngineHost.call(
                "function_graph",
                args: addr.isEmpty ? ["name": name] : ["address": addr]
            )
            if res.ok, let model = FunctionGraphModel.parse(from: res.json) {
                applyFunctionGraph(model, rawJSON: res.json)
                return
            }
            if res.ok {
                // Engine returned ok but unparsable — keep diagnostic text.
                if let data = try? JSONSerialization.data(withJSONObject: res.json, options: [.prettyPrinted]),
                   let text = String(data: data, encoding: .utf8)
                {
                    functionGraphText = text
                } else {
                    functionGraphText = res.message
                }
            }
        }
        Task {
            // Headless analyze_control_flow requires `function_name` (not address).
            var resp = MCPClient.Response(ok: false, text: "", json: nil, statusCode: 0)
            if !name.isEmpty {
                resp = await self.mcpGet("analyze_control_flow", query: ["function_name": name])
            }
            if !resp.ok, !addr.isEmpty {
                // Some builds accept address via get_function_by_address then retry by name.
                let meta = await self.mcpGet("get_function_by_address", query: ["address": addr])
                if let resolved = Self.functionNameFromMeta(meta.text), !resolved.isEmpty {
                    resp = await self.mcpGet("analyze_control_flow", query: ["function_name": resolved])
                }
            }
            if !resp.ok {
                // Call-graph is different semantics; still better than a raw error pane.
                var q: [String: String] = [:]
                if !addr.isEmpty { q["address"] = addr }
                if !name.isEmpty { q["name"] = name }
                resp = await self.mcpGet("get_function_call_graph", query: q)
            }
            await MainActor.run {
                if let obj = resp.json as? [String: Any], let model = FunctionGraphModel.parse(from: obj) {
                    self.applyFunctionGraph(model, rawJSON: obj)
                } else if !resp.text.isEmpty, let data = resp.text.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let model = FunctionGraphModel.parse(from: obj)
                {
                    self.applyFunctionGraph(model, rawJSON: obj)
                } else {
                    self.functionGraphModel = FunctionGraphModel()
                    let err = (resp.json as? [String: Any])?["error"] as? String
                    self.functionGraphText = err
                        ?? (resp.text.isEmpty
                            ? (InProcessEngineHost.isRunning
                                ? "// no CFG — select a function and Refresh"
                                : "// Engine not in-process — CFG edges need GHIDRA_VIBE_ENGINE=inprocess")
                            : resp.text)
                    self.statusMessage = "Function Graph: \(err ?? "text fallback")"
                }
            }
        }
    }

    private static func functionNameFromMeta(_ text: String) -> String? {
        // "Function: name at addr"
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            if s.hasPrefix("Function: ") {
                let rest = s.dropFirst("Function: ".count)
                if let at = rest.range(of: " at ") {
                    return String(rest[..<at.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                return String(rest).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func applyFunctionGraph(_ model: FunctionGraphModel, rawJSON: [String: Any]) {
        functionGraphModel = model
        selectedGraphNodeId = model.entry.isEmpty ? model.nodes.first?.id : model.entry
        if let data = try? JSONSerialization.data(withJSONObject: rawJSON, options: [.prettyPrinted]),
           let text = String(data: data, encoding: .utf8)
        {
            functionGraphText = text
        }
        let edgeN = model.edges.count
        let nodeN = model.nodes.count
        statusMessage = "Function Graph: \(model.function) — \(nodeN) blocks, \(edgeN) edges"
    }

    func selectGraphNode(address: String) {
        if let node = functionGraphModel.nodes.first(where: {
            $0.addr == address || $0.id == address
        }) {
            selectedGraphNodeId = node.id
        }
        goToAddressViaMCP(address)
        if let fn = functions.first(where: {
            $0.address == address || address.localizedCaseInsensitiveContains($0.address)
        }) {
            selectedFunction = fn
        }
        fetchListing()
        decompileSelected()
    }

    func openAppBundlePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Choose a whole .app, .ipa, or .framework bundle (not a single Mach-O)"
        panel.prompt = "Open Bundle"
        if let appType = UTType(filenameExtension: "app"),
           let ipa = UTType(filenameExtension: "ipa"),
           let fw = UTType(filenameExtension: "framework")
        {
            panel.allowedContentTypes = [appType, ipa, fw]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openAppBundle(at: url.path)
    }

    func openAppBundle(at path: String) {
        appleBundlePath = path
        ensureVibeMCP()
        statusMessage = "Opening app bundle…"
        consoleAppend("Open App Bundle \(path)")
        showProvider(.appleBundle)
        Task {
            let listed = await self.vibeGet("malimite_list_bundle_binaries", query: ["path": path])
            let projectDir = self.projectPath.isEmpty
                ? FileManager.default.currentDirectoryPath + "/ghidra-vibe-projects/AppBundle"
                : self.projectPath.replacingOccurrences(of: ".gpr", with: "")
            let opened = await self.vibePost("malimite_open_bundle", body: [
                "path": path,
                "project": projectDir,
            ])
            var rows: [String] = []
            let rootObj = listed.json as? [String: Any]
            let data = (rootObj?["data"] as? [String: Any]) ?? rootObj
            if let bins = data?["binaries"] as? [[String: Any]] {
                rows = bins.compactMap { b in
                    guard let p = b["path"] as? String else { return nil }
                    let role = b["role"] as? String ?? "binary"
                    return "[\(role)] \(p)"
                }
            } else {
                rows = MCPClient.lines(from: listed)
            }
            let bundleName = URL(fileURLWithPath: path).lastPathComponent
            var programName = ""
            if let first = rows.first {
                let main = rows.first(where: { $0.contains("[main]") || $0.contains("[macos]") }) ?? first
                let pathPart = main.split(separator: "]").last.map {
                    String($0).trimmingCharacters(in: .whitespaces)
                } ?? ""
                if !pathPart.isEmpty {
                    programName = URL(fileURLWithPath: pathPart).lastPathComponent
                }
            }
            self.bundleBinaryRows = rows
            if !rows.isEmpty {
                self.programTreeNodes = ["App Bundle", "Contents/MacOS"] + rows
            }
            self.refreshProjectPrograms()
            self.refreshMalimiteDB()
            self.consoleAppend("Bundle binaries: \(rows.count) — \(opened.text.prefix(200))")
            if !programName.isEmpty {
                self.currentProgramName = programName
                self.selectedProjectProgram = "/\(programName)"
            }
            self.toolMode = .codeBrowser
            if !programName.isEmpty {
                let prog = programName.hasPrefix("/") ? programName : "/\(programName)"
                _ = await self.openProgramViaMCP(prog)
            }
            await self.prepareOpenProgramForReverseEngineering(label: bundleName)
        }
    }

    func promptGoTo() { showGoToAlert = true }

    func performGoTo() {
        let target = goToDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        showGoToAlert = false
        consoleAppend("Go To \(target)")
        navPush(target)
        if let fn = functions.first(where: {
            $0.name == target || $0.address.localizedCaseInsensitiveContains(target)
        }) {
            selectedFunction = fn
            decompileSelected()
            fetchListing()
            refreshBytes()
            return
        }
        goToAddressViaMCP(target)
        refreshBytes()
    }

    func autoAnalyze() {
        guard !analysisBusy else {
            statusMessage = "Auto Analyze already running — Cancel in the status bar to abort"
            return
        }
        statusMessage = "Auto analyzing…"
        consoleAppend("Auto Analyze → POST /run_analysis")
        guard mcpBaseURL != nil else { return }
        analysisBusy = true
        beginTaskMonitor()
        analysisTask?.cancel()
        analysisTask = Task { @MainActor in
            // Keep the stock-style task monitor “alive” with elapsed time while MCP runs.
            let ticker = Task { @MainActor in
                while !Task.isCancelled, self.analysisBusy {
                    let elapsed = self.taskMonitorElapsedLabel
                    self.statusMessage = "Auto analyzing… \(elapsed) — analyzers running (stock Task Monitor)"
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            let resp = await self.mcpPost("run_analysis", body: [:])
            ticker.cancel()
            guard !Task.isCancelled else {
                self.analysisBusy = false
                self.endTaskMonitor()
                self.statusMessage = "Auto Analyze cancelled"
                return
            }
            self.analysisBusy = false
            self.analysisTask = nil
            self.endTaskMonitor()
            self.consoleAppend(String(resp.text.prefix(800)))
            self.statusMessage = resp.ok ? "Analysis completed" : "run_analysis: \(resp.text.prefix(120))"
            if resp.ok {
                self.fetchFunctionsViaMCP()
                self.refreshSymbolTable()
                self.refreshObjcClassesFromFunctions()
            }
        }
    }

    func cancelAutoAnalyze() {
        analysisTask?.cancel()
        analysisTask = nil
        analysisBusy = false
        endTaskMonitor()
        // Headless MCP has no cancel_analysis endpoint — abort local wait / UI busy state.
        statusMessage = "Cancel Auto Analysis — stopped waiting on MCP"
        consoleAppend("Cancel Auto Analysis (status bar)")
    }

    // MARK: - MCP helpers

    func mcpGet(_ path: String, query: [String: String] = [:]) async -> MCPClient.Response {
        guard let base = mcpBaseURL else {
            return MCPClient.Response(ok: false, text: "no mcp url", json: nil, statusCode: 0)
        }
        return await MCPClient.get(base: base, path: path, query: query)
    }

    func mcpPost(_ path: String, body: [String: Any] = [:]) async -> MCPClient.Response {
        guard let base = mcpBaseURL else {
            return MCPClient.Response(ok: false, text: "no mcp url", json: nil, statusCode: 0)
        }
        let data = try? JSONSerialization.data(withJSONObject: body)
        return await MCPClient.postData(base: base, path: path, bodyData: data)
    }

    func vibeGet(_ path: String, query: [String: String] = [:]) async -> MCPClient.Response {
        guard let base = vibeBaseURL else {
            return MCPClient.Response(ok: false, text: "no vibe url", json: nil, statusCode: 0)
        }
        return await MCPClient.get(base: base, path: path, query: query)
    }

    func vibePost(_ path: String, body: [String: Any] = [:]) async -> MCPClient.Response {
        guard let base = vibeBaseURL else {
            return MCPClient.Response(ok: false, text: "no vibe url", json: nil, statusCode: 0)
        }
        let data = try? JSONSerialization.data(withJSONObject: body)
        return await MCPClient.postData(base: base, path: path, bodyData: data)
    }

    func ensureVibeMCP() {
        Task {
            if let base = vibeBaseURL, await Self.mcpReachable(base: base) { return }
            let bin = resolveVibeExtBin()
            if let bin {
                runDetached(bin, arguments: [])
                consoleAppend("Started vibe MCP ext → \(vibeMcpURL)")
            }
        }
    }

    private func resolveVibeExtBin() -> String? {
        let candidates = [
            vibeMcpExtBin,
            ProcessInfo.processInfo.environment["GHIDRA_VIBE_MCP_EXT"] ?? "",
            FileManager.default.currentDirectoryPath + "/scripts/ghidra-vibe-mcp-ext",
        ]
        return candidates.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }

    func newProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Create Project Here"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let name = "VibeProject"
        let gpr = dir.appendingPathComponent("\(name).gpr")
        rememberProject(gpr.path)
        projectPrograms = []
        enterProjectWindow()
        statusMessage = "Project path set: \(projectPath) — engine will open it when ready"
        consoleAppend("New project → \(projectPath)")
    }

    func openProjectPicker() {
        let panel = NSOpenPanel()
        if let gpr = UTType(filenameExtension: "gpr") {
            panel.allowedContentTypes = [gpr]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rememberProject(url.path)
        refreshProjectPrograms()
        enterProjectWindow()
        statusMessage = "Opened project \(url.lastPathComponent)"
    }

    func importFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        consoleAppend("Import requested: \(url.path)")
        let path = url.path
        let lower = path.lowercased()
        if lower.hasSuffix(".ipa") || lower.hasSuffix(".app") || lower.hasSuffix(".framework")
            || FileManager.default.fileExists(atPath: path + "/Contents/Info.plist")
            || FileManager.default.fileExists(atPath: path + "/Info.plist")
        {
            openAppBundle(at: path)
        } else if !dyldHelper.isEmpty, path.contains("dyld") {
            importDyldImage(path)
        } else if !appleHelper.isEmpty {
            appleBundlePath = path
            importAppleBundle(binOnly: true)
        } else {
            statusMessage = "Set GHIDRA_VIBE_APPLE / DYLD helpers for import"
        }
    }

    func pickAppleBundle() {
        openAppBundlePicker()
    }

    func importAppleBundle(binOnly: Bool = false) {
        runMalimiteAnalyze(binOnly: binOnly)
    }

    func runMalimiteAnalyze(binOnly: Bool = false) {
        guard !appleBundlePath.isEmpty else {
            statusMessage = "Pick an IPA / .app first"
            return
        }
        ensureVibeMCP()
        let project = projectPath.isEmpty
            ? FileManager.default.currentDirectoryPath + "/ghidra-vibe-projects/MalimiteImport"
            : projectPath.replacingOccurrences(of: ".gpr", with: "")
        malimiteProjectDir = project
        malimiteDBPath = project + "/malimite.db"
        statusMessage = "Malimite analyze via vibe MCP…"
        consoleAppend("malimite_analyze path=\(appleBundlePath) project=\(project) binOnly=\(binOnly)")
        let path = appleBundlePath
        let db = malimiteDBPath
        Task {
            let resp = await self.vibePost("malimite_analyze", body: [
                "path": path,
                "project": project,
                "db": db,
            ])
            await MainActor.run {
                self.consoleAppend(String(resp.text.suffix(2500)))
                self.statusMessage = resp.ok ? "Malimite analyze OK" : "Malimite analyze failed"
                self.malimiteProjectDir = project
                self.malimiteDBPath = db
                if resp.ok {
                    self.rememberProject(project.hasSuffix(".gpr") ? project : project + "/ghidra/MalimiteAnalyze.gpr")
                    self.refreshMalimiteDB()
                    self.refreshSwiftClasses()
                    self.listAppleResources()
                }
            }
        }
    }

    func refreshMalimiteDB() {
        guard !malimiteDBPath.isEmpty else { return }
        ensureVibeMCP()
        let db = malimiteDBPath
        Task {
            let stats = await self.vibePost("malimite_db_stats", body: ["db": db])
            await MainActor.run {
                self.malimiteStatsText = stats.text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.refreshMalimiteClasses()
                self.refreshMalimiteEntrypoints()
                self.refreshMalimiteStrings()
                if let data = try? Data(contentsOf: URL(fileURLWithPath: self.malimiteProjectDir + "/info.json")),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                {
                    let exe = obj["CFBundleExecutable"] as? String ?? ""
                    let bid = obj["CFBundleIdentifier"] as? String ?? ""
                    self.malimiteInfoSummary = "\(bid) · \(exe)"
                }
            }
        }
    }

    func refreshMalimiteClasses() {
        guard !malimiteDBPath.isEmpty else { return }
        let db = malimiteDBPath
        Task {
            let resp = await self.vibePost("malimite_list_classes", body: ["db": db])
            await MainActor.run {
                if let d = resp.json as? [String: Any], let obj = d["data"] as? [String: Any] {
                    self.malimiteClassRows = obj.keys.sorted().map { key in
                        let n = (obj[key] as? [Any])?.count ?? 0
                        return "\(key) (\(n))"
                    }
                } else {
                    self.malimiteClassRows = MCPClient.lines(from: resp)
                }
                if let sel = self.selectedMalimiteClass {
                    self.loadMalimiteClassFunctions(sel)
                }
            }
        }
    }

    func loadMalimiteClassFunctions(_ classRow: String) {
        let className = classRow.components(separatedBy: " (").first ?? classRow
        selectedMalimiteClass = classRow
        guard !malimiteDBPath.isEmpty else { return }
        let db = malimiteDBPath
        Task {
            let resp = await self.vibePost("malimite_list_functions", body: [
                "db": db, "class": className, "limit": 500,
            ])
            await MainActor.run {
                if let d = resp.json as? [String: Any], let arr = d["data"] as? [[String: Any]] {
                    self.malimiteFunctionRows = arr.compactMap {
                        $0["FunctionName"] as? String ?? $0["functionName"] as? String
                    }
                } else {
                    self.malimiteFunctionRows = MCPClient.lines(from: resp)
                }
            }
        }
    }

    func loadMalimiteFunctionCode(_ name: String) {
        selectedMalimiteFunction = name
        guard !malimiteDBPath.isEmpty else { return }
        let cls = (selectedMalimiteClass ?? "").components(separatedBy: " (").first ?? ""
        let db = malimiteDBPath
        Task {
            let resp = await self.vibePost("malimite_get_decompile", body: [
                "db": db, "function": name, "class": cls,
            ])
            await MainActor.run {
                if let d = resp.json as? [String: Any],
                   let row = d["data"] as? [String: Any]
                {
                    self.malimiteFunctionCode = (row["DecompilationCode"] as? String)
                        ?? (row["DecompiledCode"] as? String)
                        ?? ""
                } else {
                    self.malimiteFunctionCode = resp.text
                }
                if !self.malimiteFunctionCode.isEmpty {
                    self.decompiledText = self.malimiteFunctionCode
                    self.codeEditorText = self.malimiteFunctionCode
                }
            }
        }
    }

    func refreshMalimiteStrings() {
        guard !malimiteDBPath.isEmpty else { return }
        let db = malimiteDBPath
        Task {
            let resp = await self.vibePost("malimite_search", body: ["db": db, "query": ""])
            // Prefer resource/string listing via classes harvest — search empty may fail; use list via analyze dump
            let harvest = await self.vibePost("malimite_db_stats", body: ["db": db])
            await MainActor.run {
                self.malimiteStringRows = MCPClient.lines(from: resp)
                if self.malimiteStringRows.isEmpty {
                    self.malimiteStringRows = ["(strings in DB — \(harvest.text.prefix(80)))"]
                }
            }
        }
    }

    func refreshMalimiteEntrypoints() {
        guard !malimiteDBPath.isEmpty else { return }
        let db = malimiteDBPath
        let project = malimiteProjectDir
        Task {
            let resp = await self.vibePost("malimite_list_entrypoints", body: [
                "db": db, "project": project,
            ])
            await MainActor.run {
                if let d = resp.json as? [String: Any],
                   let data = d["data"] as? [String: Any],
                   let eps = data["entrypoints"] as? [[String: Any]]
                {
                    self.malimiteEntrypointRows = eps.map { e in
                        let n = e["name"] as? String ?? ""
                        let a = e["address"] as? String ?? ""
                        return "\(n) @ \(a)"
                    }
                } else {
                    self.malimiteEntrypointRows = MCPClient.lines(from: resp)
                }
            }
        }
    }

    func refreshMalimiteRefs() {
        guard !malimiteDBPath.isEmpty else { return }
        let q = malimiteRefQuery.isEmpty ? (selectedMalimiteFunction ?? "main") : malimiteRefQuery
        let db = malimiteDBPath
        Task {
            let resp = await self.vibePost("malimite_list_refs", body: ["db": db, "function": q])
            await MainActor.run {
                self.malimiteRefRows = MCPClient.lines(from: resp)
            }
        }
    }

    func refreshMalimiteLibraries() {
        Task {
            let resp = await self.vibePost("malimite_libraries_list", body: [:])
            await MainActor.run {
                self.malimiteLibraryRows = MCPClient.lines(from: resp)
            }
        }
    }

    func resetMalimiteLibraries() {
        Task {
            _ = await self.vibePost("malimite_libraries_reset", body: [:])
            await MainActor.run { self.refreshMalimiteLibraries() }
        }
    }

    func runMalimiteTranslate() {
        statusMessage = "Malimite translate…"
        let code = malimiteTranslateInput
        let action = malimiteTranslateAction
        let language = malimiteTranslateLanguage
        Task {
            let resp = await self.vibePost("malimite_translate", body: [
                "action": action, "code": code, "language": language,
            ])
            await MainActor.run {
                if let d = resp.json as? [String: Any],
                   let data = d["data"] as? [String: Any],
                   let text = data["text"] as? String
                {
                    self.malimiteTranslateOutput = text
                    self.codeEditorText = text
                } else {
                    self.malimiteTranslateOutput = resp.text
                }
                self.statusMessage = resp.ok ? "Translate done" : "Translate failed"
            }
        }
    }

    private static func jsonLinesOrRows(_ text: String) -> [String] {
        if let data = text.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [Any]
        {
            return arr.map { item -> String in
                if let s = item as? String { return s }
                if let d = item as? [String: Any] {
                    if let v = d["value"] as? String { return v }
                    if let n = d["FunctionName"] as? String { return n }
                    return String(describing: d)
                }
                return String(describing: item)
            }
        }
        return text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }

    nonisolated private static func runHelper(_ helper: String, args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        if helper.hasPrefix("/") {
            p.executableURL = URL(fileURLWithPath: helper)
            p.arguments = args
        } else if let resolved = Self.which(helper) {
            p.executableURL = URL(fileURLWithPath: resolved)
            p.arguments = args
        } else {
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = ["-lc", ([helper] + args).map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: " ")]
        }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return (1, "failed to launch \(helper): \(error)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    nonisolated private static func which(_ name: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        p.arguments = [name]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }

    func listAppleResources() {
        guard !appleBundlePath.isEmpty else { return }
        ensureVibeMCP()
        let root = appleBundlePath
        Task {
            let resp = await self.vibePost("malimite_list_resources", body: ["root": root, "app": root])
            await MainActor.run {
                let rows = MCPClient.lines(from: resp)
                self.appleResourceRows = rows.isEmpty ? ["(no resources — unpack IPA or pick .app)"] : rows
            }
        }
    }

    func refreshSwiftClasses() {
        ensureVibeMCP()
        Task {
            let resp = await self.vibeGet("swift_list_namespaces")
            await MainActor.run {
                var rows = MCPClient.lines(from: resp)
                if rows.isEmpty {
                    let demangled = self.symbolNodes.filter {
                        $0.contains("$s") || $0.contains("_$s") || $0.contains("Swift") || $0.contains(".")
                    }
                    rows.append(contentsOf: demangled.prefix(200))
                }
                if rows.isEmpty {
                    // Fall back to ObjC class harvest so AppKit GUI smokes still see classes.
                    if self.objcClassRows.isEmpty {
                        self.refreshObjcClassesFromFunctions()
                    }
                    rows = self.objcClassRows.isEmpty
                        ? ["(open a Swift/ObjC program — or Dump via headless)"]
                        : self.objcClassRows.map { "\($0) (ObjC)" }
                }
                self.swiftClassRows = rows
                self.statusMessage = "Classes: \(rows.count) rows (ObjC \(self.objcClassRows.count))"
            }
        }
    }

    /// Parse ObjC runtime method names into unique class names for GuiControl assertions.
    func refreshObjcClassesFromFunctions() {
        applyObjcClassHarvest(from: functions.map(\.name) + symbolNodes + symbolTableRows)
        // Also scrape a wider MCP page — AppKit ObjC methods are rarely in the first 100.
        guard let base = mcpBaseURL else { return }
        Task { @MainActor in
            var comps = URLComponents(url: base.appendingPathComponent("list_functions"), resolvingAgainstBaseURL: false)
            comps?.queryItems = [
                URLQueryItem(name: "offset", value: "0"),
                URLQueryItem(name: "limit", value: "20000"),
            ]
            guard let url = comps?.url,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let text = String(data: data, encoding: .utf8)
            else { return }
            let names = Self.parseFunctionList(text).map(\.name)
            self.applyObjcClassHarvest(from: names + self.symbolNodes)
        }
    }

    private func applyObjcClassHarvest(from patterns: [String]) {
        var counts: [String: Int] = [:]
        for raw in patterns {
            guard let cls = Self.objcClassName(from: raw) else { continue }
            counts[cls, default: 0] += 1
        }
        guard !counts.isEmpty else { return }
        objcClassRows = counts.keys.sorted { a, b in
            let ca = counts[a] ?? 0
            let cb = counts[b] ?? 0
            if ca != cb { return ca > cb }
            return a < b
        }
        statusMessage = "ObjC classes: \(objcClassRows.count)"
    }

    nonisolated private static func objcClassName(from symbol: String) -> String? {
        // -[NSApplication sharedApplication] / +[NSWindow alloc]
        let s = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count > 3 else { return nil }
        let body: String
        if s.hasPrefix("-[") || s.hasPrefix("+[") {
            body = String(s.dropFirst(2))
        } else if s.hasPrefix("[") {
            body = String(s.dropFirst())
        } else {
            return nil
        }
        guard let end = body.firstIndex(of: " ") ?? body.firstIndex(of: "]") else { return nil }
        let name = String(body[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "Global" else { return nil }
        return name
    }

    func dumpSwiftNamespaces() {
        let helper = appleHelper.isEmpty ? "ghidra-vibe-apple" : appleHelper
        guard !projectPath.isEmpty, !currentProgramName.isEmpty else {
            statusMessage = "Open a project + program first"
            return
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghidra-vibe-swift-ns.json").path
        Task.detached { [helper, projectPath, currentProgramName, out] in
            let result = Self.runHelper(helper, args: [
                "dump-ns", "--project", projectPath, "--program", currentProgramName, "--out", out,
            ])
            let text = (try? String(contentsOfFile: out, encoding: .utf8)) ?? result.output
            await MainActor.run {
                self.consoleAppend("dump-ns → \(out)")
                if let classes = Self.parseSwiftClassNames(from: text) {
                    self.swiftClassRows = classes
                }
                self.statusMessage = result.status == 0 ? "Swift namespaces dumped" : "dump-ns failed"
            }
        }
    }

    nonisolated private static func parseSwiftClassNames(from json: String) -> [String]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let classes = obj["classes"] as? [[String: Any]]
        else { return nil }
        return classes.compactMap { c in
            guard let name = c["ClassName"] as? String else { return nil }
            let n = (c["Functions"] as? [Any])?.count ?? 0
            return "\(name) (\(n))"
        }
    }

    func openSelectedProgram() {
        guard let name = selectedProjectProgram else {
            statusMessage = "Select a program in the project tree"
            return
        }
        let path = name.hasPrefix("/") ? name : "/\(name)"
        rememberProgram(path)
        toolMode = .codeBrowser
        Task { @MainActor in
            if await Self.mcpReachable(base: mcpBaseURL) {
                await ensureWorkspaceLoaded(program: path)
            } else {
                ensureProgramEngineRunning(loadProgram: true)
            }
        }
    }

    func saveProgram() {
        statusMessage = "Saving program…"
        if InProcessEngineHost.isRunning {
            let res = InProcessEngineHost.call("save_program")
            consoleAppend("save_program: \(res.message)")
            statusMessage = res.ok ? "Saved" : "Save failed: \(res.message)"
            return
        }
        ensureVibeMCP()
        Task {
            let resp = await self.vibePost("vibe_proxy_analysis", body: [
                "path": "save_program",
                "method": "POST",
                "body": ["program": self.currentProgramName],
            ])
            await MainActor.run {
                self.consoleAppend("save_program: \(resp.text.prefix(200))")
                self.statusMessage = resp.ok
                    ? "Save requested"
                    : "Save — programs persist in the Ghidra project on headless exit"
            }
        }
    }

    func closeProgram() {
        currentProgramName = ""
        functions = []
        selectedFunction = nil
        decompiledText = "// No program\n"
        listingText = ""
        statusMessage = "Program closed (UI)"
    }

    func refreshProjectPrograms() {
        let local = discoverProgramsInProject(projectPath)
        if !local.isEmpty {
            projectPrograms = local
        } else if !currentProgramName.isEmpty {
            projectPrograms = [currentProgramName]
        }
        if selectedProjectProgram == nil, let first = local.first {
            selectedProjectProgram = first.hasPrefix("/") ? first : "/\(first)"
        }
        Task {
            if InProcessEngineHost.isRunning {
                let res = InProcessEngineHost.call("list_project_programs")
                if let arr = res.json["data"] as? [String], !arr.isEmpty {
                    await MainActor.run {
                        self.projectPrograms = arr.map {
                            $0.hasPrefix("/") ? $0 : "/\($0)"
                        }
                    }
                    return
                }
            }
            guard let base = mcpBaseURL else { return }
            let info = await MCPClient.get(base: base, path: "get_project_info")
            if let obj = info.json as? [String: Any] {
                var names: [String] = []
                if let files = obj["files"] as? [[String: Any]] {
                    names = files.compactMap { f in
                        (f["path"] as? String) ?? (f["name"] as? String)
                    }
                }
                if names.isEmpty, let arr = obj["programs"] as? [String] {
                    names = arr
                }
                if !names.isEmpty {
                    await MainActor.run {
                        self.projectPrograms = names.map {
                            $0.hasPrefix("/") ? $0 : "/\($0)"
                        }
                    }
                }
            }
        }
    }

    /// Scan Ghidra `.rep/idata/**/*.prp` for program names (works offline).
    private func discoverProgramsInProject(_ gprPath: String) -> [String] {
        guard !gprPath.isEmpty else { return [] }
        let gpr = URL(fileURLWithPath: gprPath)
        let baseName = gpr.deletingPathExtension().lastPathComponent
        let dir = gpr.deletingLastPathComponent()
        let rep = dir.appendingPathComponent("\(baseName).rep/idata")
        guard let en = FileManager.default.enumerator(
            at: rep, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var names: [String] = []
        for case let url as URL in en where url.pathExtension == "prp" {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  text.contains("VALUE=\"Program\"")
            else { continue }
            for line in text.split(whereSeparator: \.isNewline) {
                let s = String(line)
                guard s.contains("NAME=\"NAME\""), s.contains("VALUE=\"") else { continue }
                guard let start = s.range(of: "VALUE=\"")?.upperBound,
                      let end = s[start...].firstIndex(of: "\"")
                else { continue }
                let name = String(s[start ..< end])
                if !name.isEmpty { names.append("/\(name)") }
            }
        }
        return Array(Set(names)).sorted()
    }

    private func rememberProgram(_ path: String) {
        let normalized = path.hasPrefix("/") ? path : "/\(path)"
        selectedProjectProgram = normalized
        currentProgramName = (normalized as NSString).lastPathComponent
        UserDefaults.standard.set(normalized, forKey: "ghidra.vibe.lastProgram")
    }

    func clearConsole() {
        consoleText = ""
        statusMessage = "Console cleared"
    }

    func copyConsoleToClipboard() {
        let text = consoleText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = text.isEmpty ? "Console empty" : "Copied console (\(text.count) chars)"
    }

    func submitConsoleInput() {
        let line = consoleInputDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        consoleAppend("> \(line)")
        consoleInputDraft = ""
        // Best-effort: run as ghidra script name or echo
        if line.hasPrefix("!") {
            runSelectedScript(String(line.dropFirst()))
        } else {
            statusMessage = "Console: \(line)"
        }
    }

    func consoleAppend(_ line: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        consoleText += "[\(ts)] \(line)\n"
        if consoleText.count > 50_000 {
            consoleText = String(consoleText.suffix(40_000))
        }
    }

    func goToAddressViaMCP(_ address: String) {
        let raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, mcpBaseURL != nil else { return }
        Task {
            var target = raw
            // Symbols like `_objc_msgSend` are not hex addresses. Headless
            // get_function_by_address resolves them when passed as `address`.
            if !Self.looksLikeAddress(raw) {
                let meta = await self.mcpGet("get_function_by_address", query: ["address": raw])
                if let resolved = Self.addressFromFunctionMeta(meta.text) {
                    target = resolved
                } else {
                    let byName = await self.mcpGet("disassemble_function", query: ["name": raw])
                    let byNameErr = (byName.json as? [String: Any])?["error"] as? String
                    if byName.ok, byNameErr == nil, !byName.text.hasPrefix("{\"error\"") {
                        await MainActor.run {
                            self.listingText = byName.text
                            self.bytesText = String(byName.text.prefix(2000))
                            self.statusMessage = "Listing \(raw)"
                        }
                        return
                    }
                }
            }
            let resp = await self.mcpGet("disassemble_function", query: ["address": target])
            await MainActor.run {
                if resp.ok {
                    self.listingText = resp.text
                    self.bytesText = String(resp.text.prefix(2000))
                    self.statusMessage = "Listing @ \(target)"
                } else {
                    let err = (resp.json as? [String: Any])?["error"] as? String ?? resp.text
                    self.listingText = err
                    self.statusMessage = "Listing failed: \(err.prefix(80))"
                }
            }
        }
    }

    private static func addressFromFunctionMeta(_ text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            if s.hasPrefix("Entry: ") {
                let addr = String(s.dropFirst("Entry: ".count)).trimmingCharacters(in: .whitespaces)
                if looksLikeAddress(addr) { return addr }
            }
            if s.hasPrefix("Function: "), let at = s.range(of: " at ", options: .backwards) {
                let addr = String(s[at.upperBound]).trimmingCharacters(in: .whitespaces)
                if looksLikeAddress(addr) { return addr }
            }
        }
        return nil
    }

    private static func looksLikeAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        if t.contains("::") || t.contains("[") || t.contains(" ") { return false }
        if t.hasPrefix("ram:") || t.hasPrefix("REGISTER:") { return true }
        // hex with optional 0x
        let hex = t.lowercased().hasPrefix("0x") ? String(t.dropFirst(2)) : t
        guard !hex.isEmpty, hex.count <= 16 else { return false }
        return hex.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdef").contains($0) }
    }

    private func loadProgramViaMCPPath(_ path: String) {
        Task { await loadProgramViaMCP(path) }
    }

    func probeStrings() {
        guard let base = mcpBaseURL else { return }
        let url = base.appendingPathComponent("list_strings")
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let text = String(data: data, encoding: .utf8)
            {
                let rows = text.split(whereSeparator: \.isNewline).map { String($0) }.prefix(500).map { String($0) }
                await MainActor.run {
                    self.stringRows = Array(rows)
                    self.statusMessage = "Loaded \(rows.count) strings"
                }
            }
        }
    }

    func refreshMemoryMap() {
        memoryMapRows = ["(loading list_segments…)"]
        Task {
            let resp = await self.mcpGet("list_segments")
            await MainActor.run {
                let rows = MCPClient.lines(from: resp)
                self.memoryMapRows = rows.isEmpty ? ["(no segments — load a program)"] : Array(rows.prefix(500))
                self.statusMessage = "Memory map (\(self.memoryMapRows.count))"
            }
        }
    }

    func refreshSymbolTable() {
        Task {
            var rows: [String] = []
            for path in ["list_exports", "list_imports", "list_globals"] {
                let resp = await self.mcpGet(path)
                rows.append(contentsOf: MCPClient.lines(from: resp).prefix(200).map { "[\(path)] \($0)" })
            }
            let ns = await self.mcpGet("list_namespaces")
            await MainActor.run {
                self.symbolTableRows = rows.isEmpty
                    ? self.functions.prefix(200).map { "\($0.address)\t\($0.name)" }
                    : rows
                self.symbolNodes = MCPClient.lines(from: ns)
                if self.symbolNodes.isEmpty {
                    self.symbolNodes = self.functions.map(\.name)
                }
                // Promote NS*/objc-looking namespaces into the class preview for GUI smokes.
                let nsClasses = self.symbolNodes.filter { name in
                    let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return n.hasPrefix("NS") || n.hasPrefix("NSObject") || n.contains("View") || n.contains("Cell")
                }
                if !nsClasses.isEmpty {
                    var merged = Set(self.objcClassRows)
                    nsClasses.forEach { merged.insert($0) }
                    self.objcClassRows = Array(merged).sorted()
                    self.statusMessage = "ObjC/NS classes: \(self.objcClassRows.count)"
                }
            }
        }
    }

    func refreshBookmarks() {
        Task {
            let resp = await self.mcpGet("list_bookmarks")
            await MainActor.run {
                self.bookmarkRows = MCPClient.lines(from: resp)
                if self.bookmarkRows.isEmpty {
                    self.bookmarkRows = ["(no bookmarks)"]
                }
            }
        }
    }

    func refreshBytes() {
        let addr = selectedFunction?.address ?? goToDraft
        guard !addr.isEmpty else {
            bytesText = "// Select address for bytes"
            return
        }
        Task {
            let resp = await self.mcpGet("read_memory", query: ["address": addr, "length": "256"])
            let alt = resp.ok ? resp : await self.mcpGet("inspect_memory_content", query: ["address": addr])
            await MainActor.run {
                self.bytesText = alt.text.isEmpty ? "// no bytes" : alt.text
            }
        }
    }

    func refreshScripts() {
        Task {
            let resp = await self.mcpGet("list_ghidra_scripts")
            await MainActor.run {
                self.scriptRows = MCPClient.lines(from: resp)
                if self.scriptRows.isEmpty {
                    self.scriptRows = ["(enable GHIDRA_MCP_ALLOW_SCRIPTS=1 or load program)"]
                }
            }
        }
    }

    func runSelectedScript(_ name: String) {
        Task {
            let resp = await self.mcpPost("run_ghidra_script", body: ["script": name])
            await MainActor.run {
                self.consoleAppend(String(resp.text.prefix(2000)))
                self.statusMessage = resp.ok ? "Script OK" : "Script failed"
            }
        }
    }

    func refreshEntropy() {
        Task {
            let resp = await self.vibeGet("vibe_list_entropy")
            await MainActor.run {
                self.entropyRows = MCPClient.lines(from: resp)
                self.overviewText = resp.text
            }
        }
    }

    func refreshEquates() {
        Task {
            let resp = await self.vibeGet("vibe_list_equates")
            await MainActor.run { self.equateRows = MCPClient.lines(from: resp) }
        }
    }

    func refreshRelocations() {
        Task {
            let resp = await self.vibeGet("vibe_list_relocations")
            await MainActor.run { self.relocationRows = MCPClient.lines(from: resp) }
        }
    }

    func refreshRegisters() {
        let addr = selectedFunction?.address ?? goToDraft
        Task {
            let resp = await self.vibePost("vibe_list_registers", body: ["address": addr])
            await MainActor.run { self.registerRows = MCPClient.lines(from: resp) }
        }
    }

    func refreshFunctionTags() {
        Task {
            let resp = await self.vibeGet("vibe_list_function_tags")
            await MainActor.run { self.functionTagRows = MCPClient.lines(from: resp) }
        }
    }

    func refreshDefinedData() {
        Task {
            let resp = await self.mcpGet("list_data_items")
            await MainActor.run { self.definedDataRows = MCPClient.lines(from: resp) }
        }
    }

    func refreshExternals() {
        Task {
            let resp = await self.mcpGet("list_external_locations")
            await MainActor.run { self.externalProgramRows = MCPClient.lines(from: resp) }
        }
    }

    func refreshSymbolReferences() {
        let addr = selectedFunction?.address ?? goToDraft
        guard !addr.isEmpty else {
            symbolRefRows = ["(select function for xrefs)"]
            return
        }
        Task {
            let to = await self.mcpGet("get_xrefs_to", query: ["address": addr])
            let from = await self.mcpGet("get_xrefs_from", query: ["address": addr])
            await MainActor.run {
                self.symbolRefRows =
                    MCPClient.lines(from: to).map { "→ \($0)" }
                    + MCPClient.lines(from: from).map { "← \($0)" }
            }
        }
    }

    func refreshComments() {
        let addr = selectedFunction?.address ?? goToDraft
        Task {
            let resp = await self.mcpGet("get_comments", query: addr.isEmpty ? [:] : ["address": addr])
            await MainActor.run {
                self.commentRows = MCPClient.lines(from: resp)
                if self.commentRows.isEmpty { self.commentRows = ["(no comments)"] }
            }
        }
    }

    func refreshChecksum() {
        let addr = selectedFunction?.address ?? ""
        Task {
            let resp = await self.mcpGet("get_function_hash", query: addr.isEmpty ? [:] : ["address": addr])
            await MainActor.run { self.checksumText = resp.text }
        }
    }

    func refreshDataTypes() {
        Task {
            let resp = await self.mcpGet("list_data_types")
            await MainActor.run {
                let rows = MCPClient.lines(from: resp)
                self.dataTypeNodes = rows.isEmpty ? ["builtin", "windows", "mac"] : rows
            }
        }
    }

    func refreshDatatypePreview() {
        Task {
            if InProcessEngineHost.isRunning {
                let st = InProcessEngineHost.call("current_program")
                let name = (st.json["name"] as? String) ?? (st.json["program"] as? String) ?? ""
                let layout = await self.mcpGet("get_struct_layout")
                await MainActor.run {
                    let body = layout.text.isEmpty ? "(select a type in Data Type Manager)" : layout.text
                    self.datatypePreviewText = name.isEmpty
                        ? body
                        : "Program: \(name)\n\(body)"
                }
                return
            }
            let resp = await self.mcpGet("get_struct_layout")
            await MainActor.run {
                self.datatypePreviewText = resp.text.isEmpty ? "(select a type)" : resp.text
            }
        }
    }

    func refreshDisassembledView() {
        let addr = selectedFunction?.address ?? goToDraft
        guard !addr.isEmpty else {
            if InProcessEngineHost.isRunning {
                let fns = InProcessEngineHost.call("list_functions", args: ["limit": 1])
                if let arr = fns.json["functions"] as? [[String: Any]],
                   let first = arr.first,
                   let a = first["address"] as? String {
                    goToDraft = a
                    refreshDisassembledView()
                    return
                }
            }
            disassembledViewText = "// Go To or select a function — listing probe empty"
            return
        }
        Task {
            if InProcessEngineHost.isRunning {
                let probe = InProcessEngineHost.call("status")
                let resp = await self.mcpGet("disassemble_function", query: ["address": addr])
                await MainActor.run {
                    let body = resp.text.isEmpty ? "// no instructions @ \(addr)" : resp.text
                    self.disassembledViewText = "Address: \(addr)\n\(probe.message)\n\(body)"
                }
                return
            }
            let resp = await self.mcpGet("disassemble_function", query: ["address": addr])
            await MainActor.run { self.disassembledViewText = resp.text }
        }
    }

    func runPythonScript() {
        let draft = pythonScriptDraft
        Task {
            let resp = await self.mcpPost("run_ghidra_script", body: [
                "script": "python",
                "code": draft,
            ])
            await MainActor.run {
                self.pythonScriptOutput = resp.text
                self.consoleAppend(String(resp.text.prefix(1500)))
            }
        }
    }

    // MARK: - Nav / undo (vibe MCP)

    func navPush(_ address: String) {
        Task {
            let resp = await self.vibePost("vibe_nav_push", body: ["address": address])
            await MainActor.run { self.applyNav(resp) }
        }
    }

    func navBack() {
        Task {
            let resp = await self.vibePost("vibe_nav_back", body: [:])
            await MainActor.run {
                self.applyNav(resp)
                if let addr = (resp.json as? [String: Any])?["address"] as? String {
                    self.goToDraft = addr
                    self.goToAddressViaMCP(addr)
                }
            }
        }
    }

    func navForward() {
        Task {
            let resp = await self.vibePost("vibe_nav_forward", body: [:])
            await MainActor.run {
                self.applyNav(resp)
                if let addr = (resp.json as? [String: Any])?["address"] as? String {
                    self.goToDraft = addr
                    self.goToAddressViaMCP(addr)
                }
            }
        }
    }

    func clearSelection() {
        selectedFunction = nil
        Task { _ = await self.vibePost("vibe_clear_selection", body: [:]) }
        statusMessage = "Selection cleared"
    }

    func undoAction() {
        Task {
            let resp = await self.vibePost("vibe_undo", body: [:])
            await MainActor.run {
                self.consoleAppend("undo: \(resp.text.prefix(200))")
                self.statusMessage = resp.ok ? "Undo" : "Nothing to undo"
            }
        }
    }

    func redoAction() {
        Task {
            let resp = await self.vibePost("vibe_redo", body: [:])
            await MainActor.run {
                self.consoleAppend("redo: \(resp.text.prefix(200))")
                self.statusMessage = resp.ok ? "Redo" : "Nothing to redo"
            }
        }
    }

    private func applyNav(_ resp: MCPClient.Response) {
        if let d = resp.json as? [String: Any] {
            navCanBack = d["can_back"] as? Bool ?? false
            navCanForward = d["can_forward"] as? Bool ?? false
        }
    }

    // MARK: - VC / Debugger

    func refreshDebuggerStatus() {
        guard let url = URL(string: debuggerURL) else { return }
        Task {
            let ok = await Self.mcpReachable(base: url)
            await MainActor.run {
                self.debuggerStatus = ok
                    ? "Debugger MCP reachable at \(self.debuggerURL)"
                    : "Debugger MCP down at \(self.debuggerURL) (TraceRmi)"
            }
        }
    }

    func refreshVCStatus() {
        Task {
            let resp = await self.mcpGet("checkout_file")
            await MainActor.run {
                // Probe: if endpoint exists we're connected enough to show status
                self.vcStatus = resp.statusCode == 404
                    ? "VC tools unavailable (no Ghidra Server)"
                    : "VC MCP: \(resp.text.prefix(80))"
            }
        }
    }

    func runRAGDiscover() {
        let q = ragQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        ensureVibeMCP()
        jspaceStatus = "Discover via vibe MCP…"
        Task {
            var body: [String: Any] = ["query": q]
            if let fn = selectedFunction?.name { body["function"] = fn }
            let resp = await self.vibePost("rag_discover", body: body)
            await MainActor.run {
                if let d = resp.json as? [String: Any],
                   let data = d["data"] as? [String: Any]
                {
                    let disc = data["discovery"] as? String ?? String(describing: data["discovery"] ?? "")
                    let rules = data["rules"] as? String ?? ""
                    self.ragResult = disc + (rules.isEmpty ? "" : "\n\n## Rules\n\(rules)")
                } else {
                    self.ragResult = resp.text
                }
                self.jspaceStatus = "Discover done"
            }
        }
    }

    func loadRules() {
        ensureVibeMCP()
        Task {
            let resp = await self.vibeGet("rules_get")
            await MainActor.run {
                if let d = resp.json as? [String: Any],
                   let data = d["data"] as? [String: Any],
                   let text = data["text"] as? String
                {
                    self.rulesText = text
                } else if !resp.text.isEmpty {
                    self.rulesText = resp.text
                }
            }
        }
    }

    func saveRules() {
        let text = rulesText
        Task {
            let resp = await self.vibePost("rules_set", body: ["text": text])
            await MainActor.run {
                self.statusMessage = resp.ok ? "Rules saved via MCP" : "Rules save failed"
                self.consoleAppend("rules_set: \(resp.ok)")
            }
        }
    }

    func loadSampleWorkspaceHints() {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let dyld = cwd.appendingPathComponent("dyld-extracted")
        if FileManager.default.fileExists(atPath: dyld.path) {
            extractedRoot = dyld
        }
    }

    func dyldCachePaths() -> [String] {
        let candidates = [
            "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e",
            "/System/Library/dyld/dyld_shared_cache_arm64e",
            "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_x86_64",
            "/System/Library/dyld/dyld_shared_cache_x86_64",
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0) }
    }

    func discoverDyldCache() {
        dyldCachePath = dyldCachePaths().first
        if let dyldCachePath {
            statusMessage = "DSC open (on-device): \(dyldCachePath)"
        } else {
            statusMessage = "No dyld shared cache found"
        }
    }

    /// Writable projects root — GUI launch often has cwd=/ (read-only).
    func vibeProjectsRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/GhidraVibe/projects", isDirectory: true)
    }

    /// Prefer the open CodeBrowser project; else ~/Documents/GhidraVibe/projects/dsc.
    func dscImportTarget() -> (dir: String, name: String, gpr: String) {
        if !projectPath.isEmpty {
            let gprURL = URL(fileURLWithPath: projectPath)
            if projectPath.hasSuffix(".gpr") {
                let dir = gprURL.deletingLastPathComponent().path
                let name = gprURL.deletingPathExtension().lastPathComponent
                if dir != "/", !dir.isEmpty {
                    return (dir, name.isEmpty ? "VibeDSC" : name, projectPath)
                }
            } else {
                let dir = projectPath
                if dir != "/", !dir.isEmpty {
                    return (dir, "VibeDSC", (dir as NSString).appendingPathComponent("VibeDSC.gpr"))
                }
            }
        }
        let dir = vibeProjectsRoot().appendingPathComponent("dsc", isDirectory: true).path
        let gpr = (dir as NSString).appendingPathComponent("VibeDSC.gpr")
        return (dir, "VibeDSC", gpr)
    }

    /// File / toolbar entry: simple framework picker (not a side-pane “addon”).
    func presentFrameworkOpenSheet(query: String? = nil) {
        if let query {
            dyldQuery = query
        }
        ensureVibeMCP()
        discoverDyldCache()
        showFrameworkOpenSheet = true
        statusMessage = "Shared Cache — pick a framework to open"
        refreshDyldImagesAsync(query: dyldQuery)
    }

    /// IDA-like: open on-device cache and populate Shared Cache index provider.
    func openDyldCache() {
        discoverDyldCache()
        showProvider(.dsc)
        statusMessage = "Scanning Shared Cache index…"
        refreshDyldImagesAsync(query: dyldQuery)
    }

    /// Debounced filter — same role as IDA’s DSC Index search box.
    func scheduleDyldFilter(_ query: String) {
        dyldQuery = query
        dyldFilterTask?.cancel()
        dyldFilterTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            refreshDyldImagesAsync(query: query)
        }
    }

    @discardableResult
    func listDyldImages(query: String) -> [String] {
        dyldQuery = query
        // Kick async refresh; return current cache so GUI control doesn't block.
        refreshDyldImagesAsync(query: query)
        return dyldImages
    }

    func refreshDyldImagesAsync(query: String) {
        ensureVibeMCP()
        dyldListingBusy = true
        beginTaskMonitor()
        statusMessage = "Listing DSC images via vibe MCP…"
        var body: [String: Any] = [:]
        if let dyldCachePath { body["cache"] = dyldCachePath }
        if !query.isEmpty { body["query"] = query }
        Task {
            // Prefer vibe MCP; fallback to CLI helper
            var resp = await self.vibePost("dyld_list_images", body: body)
            if !resp.ok, !self.dyldHelper.isEmpty {
                var args = ["list"]
                if let path = self.dyldCachePath { args += ["--cache", path] }
                if !query.isEmpty { args += ["--query", query] }
                let out = await Self.runCaptureOffMain(self.dyldHelper, arguments: args) ?? ""
                resp = MCPClient.Response(ok: !out.isEmpty, text: out, json: nil, statusCode: 200)
            }
            await MainActor.run {
                self.dyldImages = Array(MCPClient.lines(from: resp).prefix(5000))
                self.dyldListingBusy = false
                self.endTaskMonitor()
                self.statusMessage = self.dyldImages.isEmpty
                    ? "DSC list empty / failed — is vibe MCP up?"
                    : "DSC Index: \(self.dyldImages.count) images\(query.isEmpty ? "" : " matching “\(query)”")"
            }
        }
    }

    /// IDA-like: load selected DSC module into the open project (or Documents/GhidraVibe).
    func importDyldImage(_ image: String) {
        guard !dyldImportBusy else { return }
        let short = (image as NSString).lastPathComponent
        let target = dscImportTarget()
        statusMessage =
            "Loading \(short) into \(target.name) (DyldCacheFileSystem, Apple symbols)…"
        showProvider(.dsc)
        ensureVibeMCP()
        dyldImportBusy = true
        beginTaskMonitor()
        var body: [String: Any] = [
            "image": image,
            "project": target.dir,
            "project_name": target.name,
            "analyze": dyldRunAnalysisOnImport,
            "apple_symbols": true,
            "rag_index": false,
        ]
        if let dyldCachePath { body["cache"] = dyldCachePath }
        Task {
            var resp = await self.vibePost("dyld_import_image", body: body)
            if !resp.ok, !self.dyldHelper.isEmpty {
                var args = [
                    "import", "--image", image,
                    "--project", target.dir,
                    "--project-name", target.name,
                ]
                args += self.dyldRunAnalysisOnImport ? ["--analyze", "1"] : ["--no-analyze"]
                if let path = self.dyldCachePath { args += ["--cache", path] }
                let out = await Self.runCaptureOffMain(self.dyldHelper, arguments: args) ?? ""
                resp = MCPClient.Response(ok: out.contains("OK:"), text: out, json: nil, statusCode: 200)
            }
            await MainActor.run {
                self.dyldImportBusy = false
                self.endTaskMonitor()
                self.consoleAppend(String(resp.text.prefix(800)))
                guard resp.ok else {
                    self.statusMessage = "DSC import failed: \(Self.dscFailureSummary(resp.text))"
                    return
                }
                let meta = Self.parseDyldImportMeta(resp)
                let program = meta["program"] ?? short
                let gpr = meta["project_gpr"] ?? target.gpr
                self.rememberProject(gpr)
                self.currentProgramName = program
                self.selectedProjectProgram = "/\(program)"
                self.projectPrograms = Array(Set(self.projectPrograms + [program])).sorted()
                self.statusMessage =
                    "Imported \(program) → opening in CodeBrowser…"
                self.toolMode = .codeBrowser
                self.sheetProvider = nil
                self.activateImportedDSCProgram(programPath: program.hasPrefix("/") ? program : "/\(program)")
            }
        }
    }

    /// After DyldCacheFileSystem import: open program and ready CodeBrowser like stock Ghidra.
    private func activateImportedDSCProgram(programPath: String) {
        Task { @MainActor in
            statusMessage = "Opening \(programPath)…"
            if !(await Self.mcpReachable(base: mcpBaseURL)) {
                startMCPBridge()
                for _ in 0 ..< 40 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if await Self.mcpReachable(base: mcpBaseURL) { break }
                }
            }
            let opened = await openProgramViaMCP(programPath)
            guard opened else {
                statusMessage =
                    "Import saved \(programPath), but engine open failed — Engine Status / Restart Engine, then open again"
                consoleAppend("open_program failed for \(programPath)")
                return
            }
            programTreeNodes = ["Shared Cache", programPath]
            currentProgramName = (programPath as NSString).lastPathComponent
            selectedProjectProgram = programPath
            consoleAppend("Opened \(programPath) from Shared Cache")
            await prepareOpenProgramForReverseEngineering(label: programPath)
        }
    }

    /// Stock-like “program is open” ready state: Listing + Decompile + Graph + Classes.
    func prepareOpenProgramForReverseEngineering(label: String) async {
        showProvider(.listing)
        showProvider(.decompiler)
        showProvider(.functions)
        showProvider(.functionGraph)
        showProvider(.swiftClasses)
        statusMessage = "Opened \(label) — loading functions…"
        fetchFunctionsViaMCP()
        fetchListing()
        refreshSymbolTable()
        refreshMemoryMap()
        refreshObjcClassesFromFunctions()
        refreshSwiftClasses()

        // Wait briefly for function list, then pick a sensible entry and decompile + graph.
        for _ in 0 ..< 20 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !functions.isEmpty { break }
        }
        if selectedFunction == nil {
            let preferred = functions.first(where: {
                let n = $0.name
                return n == "entry" || n == "_main" || n == "main"
                    || n.hasPrefix("-[") || n.hasPrefix("+[")
                    || n.contains("SwiftUI") || n.hasPrefix("$s")
            }) ?? functions.first
            if let preferred {
                selectFunction(name: preferred.name, address: preferred.address, id: preferred.id)
            }
        }
        decompileSelected()
        refreshFunctionGraph()
        statusMessage =
            "\(label) ready — Decompile / Functions / Graph / Classes"
    }

    /// Prefer the actionable FAIL/ERROR line over the long "DSC open:…" header.
    private static func dscFailureSummary(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let hit = lines.last(where: {
            let u = $0.uppercased()
            return u.contains("FAIL:") || u.contains("ERROR") || u.contains("SCRIPT NOT FOUND")
                || u.contains("INVALID SCRIPT") || u.contains("HEAP SPACE")
        })
        let raw = hit ?? String(text.suffix(280))
        return String(raw.prefix(280))
    }

    private static func parseDyldImportMeta(_ resp: MCPClient.Response) -> [String: String] {
        var meta: [String: String] = [:]
        if let d = resp.json as? [String: Any] {
            if let data = d["data"] as? [String: Any] {
                for (k, v) in data {
                    if let s = v as? String { meta[k] = s }
                    if let b = v as? Bool { meta[k] = b ? "true" : "false" }
                }
            }
        }
        for line in resp.text.split(whereSeparator: \.isNewline).map(String.init) {
            guard line.hasPrefix("OK:"), line.contains("project=") else { continue }
            let payload = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            for part in payload.split(separator: " ") {
                let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { meta[kv[0]] = kv[1] }
            }
        }
        return meta
    }

    func openSharedCachePickerDefaults() {
        openDyldCache()
    }

    func openCodeBrowser() {
        toolMode = .codeBrowser
        statusMessage = "CodeBrowser"
        refreshProjectPrograms()
        Task { @MainActor in
            if await Self.mcpReachable(base: mcpBaseURL) {
                await ensureWorkspaceLoaded(program: resolveMcpProgramPath())
            } else {
                ensureProgramEngineRunning(loadProgram: true)
            }
        }
    }

    /// Stock Tool Chest footprints — Version Tracking tool (not Ghidra Server VC toolbar).
    func openVersionTracking() {
        // Do not call showProvider — that forces CodeBrowser toolMode.
        toolMode = .versionTrackingTool
        stockToolSelectedProvider = "Version Tracking Matches"
        stockToolDetailText = ""
        statusMessage = "Version Tracking"
        consoleAppend("Opened Version Tracking tool (Tool Chest)")
    }

    func openDebugger() {
        toolMode = .debugger
        stockToolSelectedProvider = "Connections"
        stockToolDetailText = ""
        statusMessage = "Debugger"
        consoleAppend("Opened Debugger tool (Tool Chest)")
        refreshDebuggerStatus()
    }

    func openEmulator() {
        toolMode = .emulator
        stockToolSelectedProvider = "Dynamic"
        stockToolDetailText = ""
        statusMessage = "Emulator"
        consoleAppend("Opened Emulator tool (Tool Chest)")
    }

    func stockToolAction(tool: ToolMode, toolbar: String) {
        switch (tool, toolbar) {
        case (.debugger, "Save"), (.emulator, "Save"):
            saveProgram()
        case (.debugger, _), (.emulator, _):
            let op = toolbar
            ensureProgramEngineRunning(loadProgram: true)
            if InProcessEngineHost.isRunning {
                let res = InProcessEngineHost.call("debugger_control", args: ["op": op])
                debuggerStatus = res.message
                stockToolDetailText = res.message
                statusMessage = "\(tool.rawValue): \(op) — \(res.ok ? "OK" : "failed")"
                consoleAppend("\(tool.rawValue) \(op): \(res.message)")
            } else {
                refreshDebuggerStatus()
                statusMessage = "\(tool.rawValue) \(op) — engine not running"
            }
        case (.versionTrackingTool, "Create Session"):
            runVT(op: "create")
        case (.versionTrackingTool, "Run Correlators"):
            runVT(op: "correlators")
        case (.versionTrackingTool, "Apply Markup"):
            runVT(op: "apply")
        case (.versionTrackingTool, "Save Session"):
            runVT(op: "save")
        default:
            statusMessage = "\(tool.rawValue) — \(toolbar)"
            consoleAppend("\(tool.rawValue) toolbar: \(toolbar)")
        }
    }

    func runVT(op: String) {
        ensureProgramEngineRunning(loadProgram: true)
        if InProcessEngineHost.isRunning {
            let res = InProcessEngineHost.call("vt_session", args: [
                "op": op,
                "name": "VibeVTSession",
            ])
            stockToolDetailText = res.message
            statusMessage = "VT \(op): \(res.ok ? "OK" : res.message)"
            consoleAppend("VT \(op): \(res.message)")
        } else {
            statusMessage = "VT \(op) — start program engine first"
        }
    }

    func runDyldExtract() {
        // Discouraged: IDA-like path uses on-device DyldCacheFileSystem, not ipsw.
        statusMessage =
            "ipsw extract is discouraged — use Open Shared Cache → select image (on-device DSC)"
        guard !extractBin.isEmpty, ProcessInfo.processInfo.environment["GHIDRA_VIBE_FORCE_EXTRACT"] == "1"
        else { return }
        statusMessage = "Force extract (GHIDRA_VIBE_FORCE_EXTRACT=1)…"
        runDetached(extractBin, arguments: [])
    }

    /// Start the local program engine. Default: in-process JVM (normal Ghidra).
    /// `GHIDRA_VIBE_ENGINE=sidecar` forces the true-headless helper process (agents/debug).
    /// Cursor’s optional Python bridge starts only when `GHIDRA_VIBE_CURSOR_BRIDGE=1`.
    func ensureProgramEngineRunning(loadProgram: Bool = true) {
        startProgramEngine(loadProgram: loadProgram)
    }

    /// Legacy action id — same as ensureProgramEngineRunning.
    func startMCPBridge() {
        startProgramEngine(loadProgram: true)
    }

    private var engineMode: String {
        let env = ProcessInfo.processInfo.environment
        let mode = (env["GHIDRA_VIBE_ENGINE"] ?? "inprocess").lowercased()
        if mode == "sidecar" || mode == "headless" || mode == "process" {
            return "sidecar"
        }
        return "inprocess"
    }

    private func startProgramEngine(loadProgram: Bool) {
        statusMessage = "Starting program engine…"
        ensureVibeMCP()
        refreshProjectPrograms()
        Task { @MainActor in
            if await Self.mcpReachable(base: mcpBaseURL) {
                mcpStatus = InProcessEngineHost.isRunning
                    ? "Engine ready (in-process)"
                    : "Engine ready (headless API)"
                statusMessage = mcpStatus
                if !InProcessEngineHost.isRunning {
                    consoleAppend(
                        "Engine: reusing \(mcpServerURL) — CFG with edges needs a fresh in-process start (quit other GhidraVibe/MCP on :8089)"
                    )
                }
                if loadProgram {
                    await ensureWorkspaceLoaded(program: resolveMcpProgramPath())
                }
                maybeStartCursorBridge()
                return
            }

            if engineMode == "inprocess", InProcessEngineHost.isAvailable {
                await startInProcessEngine(loadProgram: loadProgram)
                return
            }
            if engineMode == "inprocess" {
                consoleAppend(
                    "Engine: in-process bridge unavailable — falling back to headless sidecar"
                )
            }
            await startSidecarEngine(loadProgram: loadProgram)
        }
    }

    private func startInProcessEngine(loadProgram: Bool) async {
        mcpStatus = "Engine starting (in-process)…"
        statusMessage = mcpStatus
        consoleAppend("Engine: embedding JVM in GhidraVibe process")
        // Always open project + program at JVM boot when known (HTTP open_* is unreliable).
        let project = resolveMcpProjectPath()
        let program = resolveMcpProgramPath()
        if let project {
            consoleAppend("Engine: project \(project)")
        }
        if let program {
            consoleAppend("Engine: program \(program)")
        } else {
            consoleAppend("Engine: no program resolved yet — will open after discovery")
        }
        let result = InProcessEngineHost.start(
            port: mcpPort,
            project: project,
            program: program
        )
        if !result.ok {
            mcpStatus = "Engine failed to start"
            statusMessage = mcpStatus
            consoleAppend("In-process engine: \(result.message)")
            consoleAppend("Falling back to headless sidecar…")
            await startSidecarEngine(loadProgram: loadProgram)
            return
        }
        consoleAppend("In-process engine: \(result.message)")
        for _ in 0 ..< 60 {
            if await Self.mcpReachable(base: mcpBaseURL) {
                mcpStatus = "Engine ready (in-process)"
                statusMessage = mcpStatus
                // Always hydrate — covers “already started” empty JVM and boot without --program.
                await ensureWorkspaceLoaded(program: program ?? resolveMcpProgramPath())
                maybeStartCursorBridge()
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        mcpStatus = "Engine failed to start"
        statusMessage = mcpStatus
        consoleAppend("In-process engine started but API not reachable on \(mcpServerURL)")
    }

    private func startSidecarEngine(loadProgram: Bool) async {
        guard let engineBin = resolveMcpHeadlessBin() else {
            mcpStatus = "Engine helper missing (GHIDRA_VIBE_MCP_HEADLESS)"
            statusMessage = mcpStatus
            consoleAppend("Engine: set GHIDRA_VIBE_MCP_HEADLESS (nix run passes this)")
            return
        }
        var args = ["--port", "\(mcpPort)"]
        if let project = resolveMcpProjectPath() {
            args += ["--project", project]
            if loadProgram, let program = resolveMcpProgramPath() {
                args += ["--program", program]
            }
        }
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghidra-vibe-engine.log")
        runDetached(engineBin, arguments: args, logFile: logURL)
        mcpStatus = "Engine starting (headless sidecar)…"
        statusMessage = mcpStatus
        consoleAppend("Engine: launching headless \(engineBin)")
        for _ in 0 ..< 60 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if await Self.mcpReachable(base: mcpBaseURL) {
                mcpStatus = "Engine ready (sidecar)"
                statusMessage = mcpStatus
                if loadProgram {
                    await ensureWorkspaceLoaded(program: resolveMcpProgramPath())
                }
                maybeStartCursorBridge()
                return
            }
        }
        let tail = (try? String(contentsOf: logURL, encoding: .utf8))
            .map { String($0.suffix(1200)) } ?? "(no engine log)"
        mcpStatus = "Engine failed to start"
        statusMessage = mcpStatus
        consoleAppend("Engine failed to start. Log:\n\(tail)")
        maybeStartCursorBridge()
    }

    /// Open project/program (JNI preferred) then fill CodeBrowser panes.
    /// Caller must ensure the engine is already reachable (or starting with loadProgram).
    private func ensureWorkspaceLoaded(program: String?) async {
        if let project = resolveMcpProjectPath(), InProcessEngineHost.isRunning {
            let st = InProcessEngineHost.call("status")
            let hasProject = (st.json["has_project"] as? Bool) ?? false
            if !hasProject {
                let opened = InProcessEngineHost.call("open_project", args: ["project": project])
                consoleAppend("open_project: \(opened.message)")
            }
        }
        let prog = program ?? resolveMcpProgramPath()
        if let prog {
            rememberProgram(prog)
            let opened = await openProgramViaMCP(prog)
            if !opened {
                consoleAppend("Failed to open program \(prog)")
                statusMessage = "Engine ready — open a program from the Project Window"
                return
            }
            statusMessage = "Opened \(currentProgramName)"
            fetchFunctionsViaMCP()
            fetchListing()
            refreshSymbolTable()
            refreshMemoryMap()
            probeStrings()
            refreshProjectPrograms()
        } else {
            statusMessage = "Engine ready — select a program in the Project Window"
            refreshProjectPrograms()
        }
    }

    private func maybeStartCursorBridge() {
        let wantCursor =
            ProcessInfo.processInfo.environment["GHIDRA_VIBE_CURSOR_BRIDGE"] == "1"
        if wantCursor, !bridgePath.isEmpty {
            runDetached("/usr/bin/env", arguments: [
                "python3", bridgePath, "--ghidra-server", mcpServerURL,
            ])
        }
    }

    func refreshMCPHealth() {
        guard let base = mcpBaseURL else {
            mcpStatus = "Invalid engine URL"
            return
        }
        Task { @MainActor in
            if await Self.mcpReachable(base: base) {
                mcpStatus = InProcessEngineHost.isRunning
                    ? "Engine ready (in-process)" : "Engine ready"
                // Recover empty sessions — engine up but no program open.
                if resolveMcpProgramPath() != nil {
                    let open = await MCPClient.get(base: base, path: "list_open_programs")
                    let count = (open.json as? [String: Any])?["count"] as? Int ?? 0
                    if count == 0 {
                        await ensureWorkspaceLoaded(program: resolveMcpProgramPath())
                    }
                }
            } else {
                mcpStatus = "Engine offline — restarting…"
                ensureProgramEngineRunning(loadProgram: true)
            }
        }
    }

    private var mcpPort: Int {
        URL(string: mcpServerURL)?.port ?? 8089
    }

    private func resolveMcpHeadlessBin() -> String? {
        let candidates = [
            mcpHeadlessBin,
            ProcessInfo.processInfo.environment["GHIDRA_VIBE_MCP_HEADLESS"] ?? "",
            FileManager.default.currentDirectoryPath + "/scripts/ghidra-vibe-mcp-headless",
        ]
        return candidates.first {
            !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private func resolveMcpProjectPath() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let p = env["GHIDRA_VIBE_PROJECT"], !p.isEmpty, FileManager.default.fileExists(atPath: p) {
            return p
        }
        if let p = UserDefaults.standard.string(forKey: "ghidra.vibe.lastProject"),
           !p.isEmpty, FileManager.default.fileExists(atPath: p)
        {
            return p
        }
        // Do not hardcode repo DSC/AppKit projects — that races GUI smokes (whoami, CapSmoke).
        return nil
    }

    private func resolveMcpProgramPath() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let p = env["GHIDRA_VIBE_PROGRAM"], !p.isEmpty {
            return p.hasPrefix("/") ? p : "/\(p)"
        }
        if let prog = selectedProjectProgram, !prog.isEmpty {
            return prog.hasPrefix("/") ? prog : "/\(prog)"
        }
        if let last = UserDefaults.standard.string(forKey: "ghidra.vibe.lastProgram"), !last.isEmpty {
            return last.hasPrefix("/") ? last : "/\(last)"
        }
        if !currentProgramName.isEmpty {
            return currentProgramName.hasPrefix("/") ? currentProgramName : "/\(currentProgramName)"
        }
        // Prefer first program discovered in the .gpr/.rep tree.
        if let first = discoverProgramsInProject(resolveMcpProjectPath() ?? projectPath).first {
            return first
        }
        return nil
    }

    /// Open a program: JNI in-process first (reliable), then HTTP fallbacks.
    @discardableResult
    private func openProgramViaMCP(_ path: String) async -> Bool {
        let normalized = path.hasPrefix("/") ? path : "/\(path)"
        if InProcessEngineHost.isRunning {
            let res = InProcessEngineHost.call("open_program", args: ["program": normalized])
            if res.ok {
                consoleAppend("Opened \(normalized) (in-process)")
                return true
            }
            consoleAppend("in-process open_program: \(res.message)")
        }
        guard let base = mcpBaseURL else { return false }
        // Already loaded at JVM boot?
        let cur = await MCPClient.get(base: base, path: "list_open_programs")
        if let obj = cur.json as? [String: Any] {
            let current = (obj["current_program"] as? String) ?? ""
            let programs = (obj["programs"] as? [String]) ?? []
            let leaf = (normalized as NSString).lastPathComponent
            if current == leaf || current == normalized
                || programs.contains(where: { $0 == leaf || $0 == normalized || $0.hasSuffix(leaf) })
            {
                return true
            }
            if let count = obj["count"] as? Int, count > 0, current.lowercased().contains(leaf.lowercased()) {
                return true
            }
        }
        // HTTP open_program(path=) is GUI-only in this MCP build; try load_program_from_project.
        for (pathName, queryKey) in [
            ("load_program_from_project", "programPath"),
            ("load_program_from_project", "path"),
            ("open_program", "path"),
            ("open_program", "program"),
        ] {
            let resp = await MCPClient.get(base: base, path: pathName, query: [queryKey: normalized])
            if resp.ok {
                let text = resp.text.lowercased()
                if text.contains("error") { continue }
                if text.contains("success") || text.contains("loaded") || text.contains("opened") {
                    return true
                }
            }
        }
        return false
    }

    private func loadProgramViaMCP(_ path: String) async {
        _ = await openProgramViaMCP(path)
    }

    private static func mcpReachable(base: URL?) async -> Bool {
        guard let base else { return false }
        let candidates = ["check_connection", "check", "health", ""].map {
            base.appendingPathComponent($0)
        }
        for url in candidates {
            var req = URLRequest(url: url)
            req.timeoutInterval = 2
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse,
               (200 ..< 500).contains(http.statusCode)
            {
                let text = String(data: data, encoding: .utf8) ?? ""
                if url.lastPathComponent == "check_connection" || text.contains("OK")
                    || http.statusCode == 200
                {
                    return true
                }
            }
        }
        return false
    }

    func fetchFunctionsViaMCP() {
        guard let base = mcpBaseURL else { return }
        // Headless GhidraMCP uses list_methods / list_functions; /methods is 404.
        var comps = URLComponents(url: base.appendingPathComponent("list_functions"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "500"),
        ]
        guard let url = comps?.url else { return }
        statusMessage = "Fetching functions via MCP…"
        Task { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let text = String(data: data, encoding: .utf8) ?? ""
                if text.contains("404") || text.lowercased().contains("not found") {
                    let alt = base.appendingPathComponent("list_methods")
                    let (data2, _) = try await URLSession.shared.data(from: alt)
                    let text2 = String(data: data2, encoding: .utf8) ?? ""
                    let rows = Self.parseFunctionList(text2)
                    functions = rows
                    statusMessage = "Loaded \(rows.count) functions"
                } else {
                    let rows = Self.parseFunctionList(text)
                    functions = rows
                    statusMessage = "Loaded \(rows.count) functions"
                }
                if selectedFunction == nil {
                    selectedFunction = functions.first
                }
                refreshObjcClassesFromFunctions()
            } catch {
                statusMessage = "MCP methods failed: \(error.localizedDescription)"
            }
        }
    }

    func decompileSelected() {
        guard let fn = selectedFunction, let base = mcpBaseURL else { return }
        statusMessage = "Decompiling \(fn.name)…"
        let name = fn.name
        let addr = fn.address
        Task { @MainActor in
            // Prefer address — headless decompile_function requires it.
            // Try a few address spellings (0x / bare / uppercase).
            var addrCandidates: [String] = []
            if !addr.isEmpty {
                let raw = addr.hasPrefix("0x") || addr.hasPrefix("0X") ? String(addr.dropFirst(2)) : addr
                addrCandidates = [addr, "0x\(raw)", raw, raw.uppercased(), "0x\(raw.uppercased())"]
            }
            for candidate in addrCandidates {
                var comps = URLComponents(
                    url: base.appendingPathComponent("decompile_function"),
                    resolvingAgainstBaseURL: false
                )
                comps?.queryItems = [URLQueryItem(name: "address", value: candidate)]
                if let url = comps?.url,
                   let (data, _) = try? await URLSession.shared.data(from: url),
                   let text = String(data: data, encoding: .utf8),
                   Self.isUsableDecompileText(text)
                {
                    decompiledText = text
                    statusMessage = "Decompiled \(name)"
                    return
                }
            }
            for path in ["decompile_function", "decompile"] {
                var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
                comps?.queryItems = [URLQueryItem(name: "name", value: name)]
                if let url = comps?.url,
                   let (data, _) = try? await URLSession.shared.data(from: url),
                   let text = String(data: data, encoding: .utf8),
                   Self.isUsableDecompileText(text)
                {
                    decompiledText = text
                    statusMessage = "Decompiled \(name)"
                    return
                }
            }
            statusMessage = "Decompile failed for \(name)"
        }
    }

    func fetchListing() {
        guard let fn = selectedFunction, mcpBaseURL != nil else { return }
        Task { @MainActor in
            // Prefer hex address — ObjC names confuse disassemble_function's address field.
            var resp = await self.mcpGet("disassemble_function", query: ["address": fn.address])
            if !resp.ok {
                resp = await self.mcpGet("disassemble_function", query: ["name": fn.name])
            }
            if resp.ok {
                listingText = resp.text
            } else {
                listingText = (resp.json as? [String: Any])?["error"] as? String ?? resp.text
            }
        }
    }

    func optOutAgent() {
        agentOptedOut = true
        agentEnabled = false
        showAgentWelcome = false
        dockLayout.agentSidebarVisible = false
        persistDock()
        UserDefaults.standard.set(true, forKey: "ghidra.vibe.agent.optOut")
        UserDefaults.standard.set(true, forKey: "ghidra.vibe.agent.welcomeDismissed")
    }

    func dismissAgentWelcome() {
        showAgentWelcome = false
        UserDefaults.standard.set(true, forKey: "ghidra.vibe.agent.welcomeDismissed")
    }

    func enableAgentSidebar() {
        agentOptedOut = false
        agentEnabled = true
        UserDefaults.standard.set(false, forKey: "ghidra.vibe.agent.optOut")
    }

    func toggleAgentSidebar() {
        if !agentEnabled {
            enableAgentSidebar()
            dockLayout.agentSidebarVisible = true
        } else {
            dockLayout.agentSidebarVisible.toggle()
        }
        persistDock()
        statusMessage = dockLayout.agentSidebarVisible ? "Agent sidebar shown" : "Agent sidebar hidden"
    }

    func persistAgentAISettings() {
        UserDefaults.standard.set(agentBaseURL, forKey: "ghidra.vibe.agent.baseURL")
        UserDefaults.standard.set(agentModel, forKey: "ghidra.vibe.agent.model")
        UserDefaults.standard.set(agentUseLocalOllama, forKey: "ghidra.vibe.agent.useLocalOllama")
        agentMoE.save()
        let cfg = currentLocalAIConfig()
        agentBackend = cfg.backend.rawValue
    }

    func currentLocalAIConfig() -> LocalAIConfig {
        LocalAIConfig.resolve(
            userBaseURL: agentBaseURL,
            userModel: agentModel,
            apiKeyFile: apiKeyFilePath,
            preferCloud: !agentUseLocalOllama
        )
    }

    /// MoE route for a prompt — local expert model, optional cloud escalation.
    func routeAgentMoE(
        userText: String,
        force: AgentExpertRole? = nil
    ) -> AgentMoERoute {
        let base = currentLocalAIConfig()
        // Inject api key into base for escalation even when using Ollama.
        var keyed = base
        if keyed.apiKey == nil {
            let path = apiKeyFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, let data = try? String(contentsOfFile: path, encoding: .utf8) {
                let k = data.trimmingCharacters(in: .whitespacesAndNewlines)
                if !k.isEmpty { keyed.apiKey = k }
            }
        }
        let route = AgentMoERouter.route(
            userText: userText,
            moe: agentMoE,
            base: keyed,
            selectedFunctionName: selectedFunction?.name,
            force: force,
            preferCloud: !agentUseLocalOllama
        )
        agentMoELastRoute =
            "\(route.role.rawValue):\(route.config.model)\(route.escalatedToCloud ? "@cloud" : "") (\(route.reason))"
        agentBackend = route.config.backend.rawValue
        return route
    }

    func refreshAgentModels() {
        let cfg = currentLocalAIConfig()
        Task {
            let models = await LocalAIClient.listModels(config: cfg)
            await MainActor.run {
                self.agentModelPicker = models
                if self.agentModel.isEmpty, let first = models.first {
                    self.agentModel = first
                }
                self.statusMessage = models.isEmpty
                    ? "No local models (is Ollama running at \(cfg.baseURL.absoluteString)?)"
                    : "Ollama models: \(models.prefix(6).joined(separator: ", "))"
            }
        }
    }

    func resolveJSpaceBin() -> String? {
        if !jspaceBin.isEmpty, FileManager.default.isExecutableFile(atPath: jspaceBin) {
            return jspaceBin
        }
        let candidates = [
            FileManager.default.currentDirectoryPath + "/scripts/ghidra-vibe-jspace",
            (ProcessInfo.processInfo.environment["GHIDRA_VIBE_JSPACE"] ?? ""),
        ]
        return candidates.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }

    func initJSpacePlaybook() {
        guard let bin = resolveJSpaceBin() else {
            jspaceStatus = "JSpace CLI missing (GHIDRA_VIBE_JSPACE)"
            return
        }
        Task {
            let out = await Self.runCaptureOffMain(bin, arguments: ["init"]) ?? ""
            await MainActor.run {
                self.jspaceStatus = out.contains("playbook") ? "JSpace playbook ready" : String(out.prefix(160))
                self.statusMessage = self.jspaceStatus
            }
        }
    }

    func indexJSpace() {
        ensureVibeMCP()
        jspaceStatus = "Indexing via vibe MCP (rag_index)…"
        Task {
            let resp = await self.vibePost("rag_index", body: [
                "limit": 120, "decompile_top": 24,
            ])
            await MainActor.run {
                self.jspaceStatus = resp.ok ? "JSpace indexed" : "JSpace index: \(resp.text.prefix(200))"
                self.statusMessage = self.jspaceStatus
            }
        }
    }

    /// JSpace discovery pack — RE mental model before tool calls.
    func jspaceDiscover(_ query: String) -> String {
        // Sync path kept for agent reply assembly; prefer async callers for UI.
        guard let bin = resolveJSpaceBin() else {
            return "JSpace unavailable — install scripts/ghidra-vibe-jspace"
        }
        var args = ["discover", query, "--top", "8"]
        if let fn = selectedFunction?.name {
            args += ["--function", fn]
        }
        // Blocking only when already off-main (sendAgentMessage uses Task).
        return runCapture(bin, arguments: args) ?? "(empty JSpace response)"
    }

    /// Agent tool loop: JSpace discover → LLM with tools → execute → reply.
    func sendAgentMessage() {
        let text = agentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        agentMessages.append(AgentMessage(role: .user, text: text))
        agentDraft = ""
        let lower = text.lowercased()
        if lower.contains("autonomous") && (lower.contains("re") || lower.contains("reverse")) {
            runAutonomousREPlaybook()
            return
        }
        runAgentToolLoop(userText: text)
    }

    func runAgentToolLoop(userText: String) {
        guard !agentBusy else {
            statusMessage = "Agent busy"
            return
        }
        agentBusy = true
        beginTaskMonitor()
        ensureVibeMCP()
        let route = routeAgentMoE(userText: userText)
        var cfg = route.config
        statusMessage = "Agent (\(route.role.title))…"
        let fnName = selectedFunction?.name
        let fnAddr = selectedFunction?.address
        let decompPreview = String(decompiledText.prefix(2500))
        let moeLabel = agentMoELastRoute

        Task {
            defer {
                Task { @MainActor in
                    self.agentBusy = false
                    self.endTaskMonitor()
                }
            }

            var discovery = ""
            var body: [String: Any] = ["query": userText]
            if let fnName { body["function"] = fnName }
            let discResp = await self.vibePost("rag_discover", body: body)
            if let d = discResp.json as? [String: Any],
               let data = d["data"] as? [String: Any]
            {
                discovery = (data["discovery"] as? String)
                    ?? String(describing: data["discovery"] ?? "")
                if let rules = data["rules"] as? String, !rules.isEmpty {
                    discovery += "\n\n## Active rules\n\(rules.prefix(1500))"
                }
            } else {
                discovery = discResp.text
            }
            await MainActor.run {
                self.jspaceStatus = "JSpace pack ready (\(discovery.split(separator: "\n").count) lines)"
            }

            var messages: [LocalAIChatMessage] = [
                LocalAIChatMessage(role: "system", content: AgentTools.systemPrompt),
                LocalAIChatMessage(
                    role: "user",
                    content: """
                    ## JSpace discovery
                    \(String(discovery.prefix(4000)))

                    ## Context
                    selected_function=\(fnName ?? "(none)") address=\(fnAddr ?? "")
                    moe_expert=\(route.role.rawValue)
                    decompile_preview:
                    \(decompPreview.isEmpty ? "(empty)" : decompPreview)

                    ## User
                    \(userText)
                    """
                ),
            ]

            var finalText = ""
            var usedTools: [String] = []
            let maxRounds = 6
            do {
                for _ in 0 ..< maxRounds {
                    let result: LocalAIChatResult
                    do {
                        result = try await LocalAIClient.chat(
                            config: cfg,
                            messages: messages,
                            tools: AgentTools.openAITools
                        )
                    } catch {
                        // Local failed — optional proprietary API escalation.
                        if let cloud = AgentMoERouter.cloudFallback(
                            moe: await MainActor.run { self.agentMoE },
                            role: route.role,
                            local: cfg
                        ) {
                            cfg = cloud
                            await MainActor.run {
                                self.agentMoELastRoute =
                                    "\(route.role.rawValue):\(cloud.model)@cloud (fallback)"
                                self.agentBackend = cloud.backend.rawValue
                                self.statusMessage = "Agent escalate → cloud…"
                            }
                            result = try await LocalAIClient.chat(
                                config: cfg,
                                messages: messages,
                                tools: AgentTools.openAITools
                            )
                        } else {
                            throw error
                        }
                    }
                    if result.toolCalls.isEmpty {
                        finalText = result.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        break
                    }
                    messages.append(LocalAIChatMessage(
                        role: "assistant",
                        content: result.content,
                        toolCalls: result.toolCalls
                    ))
                    for call in result.toolCalls {
                        usedTools.append(call.name)
                        let args = AgentTools.parseArgs(call.argumentsJSON)
                        let toolOut = await self.executeAgentTool(name: call.name, args: args)
                        messages.append(LocalAIChatMessage(
                            role: "tool",
                            content: toolOut,
                            toolCallId: call.id,
                            name: call.name
                        ))
                    }
                }
                if finalText.isEmpty {
                    // Last assistant content or constrained rename-table fallback.
                    let last = messages.last(where: { $0.role == "assistant" })?.content ?? ""
                    finalText = last.trimmingCharacters(in: .whitespacesAndNewlines)
                    if finalText.isEmpty {
                        finalText = "Tools ran: \(usedTools.joined(separator: ", ")). Ask a follow-up or Apply pending edits."
                    }
                    let renames = AgentTools.parseRenameTable(from: finalText)
                    if !renames.isEmpty {
                        await MainActor.run {
                            for pair in renames.prefix(12) {
                                let addr = self.functions.first(where: { $0.name == pair.old })?.address
                                    ?? self.selectedFunction?.address
                                    ?? ""
                                guard !addr.isEmpty else { continue }
                                self.agentPendingEdits.append(AgentPendingEdit(
                                    kind: .rename,
                                    address: addr,
                                    oldName: pair.old,
                                    newName: pair.new,
                                    comment: "",
                                    commentKind: "plate"
                                ))
                            }
                        }
                    }
                }
            } catch {
                finalText = """
                LLM call failed (\(cfg.backend.rawValue) @ \(cfg.baseURL.absoluteString)): \(error.localizedDescription)

                ## JSpace discovery (offline fallback)
                \(String(discovery.prefix(2500)))

                Tip: start Metal Ollama (`ollama serve`) or set a cloud key file in Settings.
                """
            }

            await MainActor.run {
                let footer = """

                — moe=\(moeLabel)
                backend=\(cfg.backend.rawValue) model=\(cfg.model)
                tools=\(usedTools.isEmpty ? "none" : usedTools.joined(separator: ", "))
                pending_edits=\(self.agentPendingEdits.count)
                """
                self.agentMessages.append(AgentMessage(role: .assistant, text: finalText + footer))
                self.statusMessage = "Agent reply (\(route.role.title))"
            }
        }
    }

    /// Execute one Agent tool (GuiControl + analysis/vibe MCP + engine writes).
    func executeAgentTool(name: String, args: [String: Any]) async -> String {
        switch name {
        case "gui_state":
            return await MainActor.run {
                let data = (try? JSONSerialization.data(withJSONObject: self.controlState(), options: [.sortedKeys])) ?? Data()
                return String(data: data, encoding: .utf8) ?? "{}"
            }
        case "gui_navigate":
            let pane = (args["pane"] as? String) ?? ""
            await MainActor.run { self.navigate(pane: pane) }
            return #"{"ok":true,"pane":"\#(pane)"}"#
        case "gui_select_function":
            await MainActor.run {
                self.selectFunction(
                    name: args["name"] as? String,
                    address: args["address"] as? String,
                    id: args["id"] as? String
                )
            }
            return #"{"ok":true}"#
        case "gui_action":
            let id = (args["id"] as? String) ?? ""
            await MainActor.run { self.runAction(id: id) }
            return #"{"ok":true,"id":"\#(id)"}"#
        case "list_functions":
            let limit = (args["limit"] as? Int) ?? 80
            await MainActor.run { self.fetchFunctionsViaMCP() }
            let resp = await mcpGet("list_methods", query: ["limit": "\(limit)"])
            if !resp.ok {
                let alt = await mcpGet("list_functions", query: ["limit": "\(limit)"])
                return alt.text
            }
            return String(resp.text.prefix(6000))
        case "decompile_function":
            await MainActor.run {
                if let name = args["name"] as? String, !name.isEmpty {
                    self.selectFunction(name: name, address: args["address"] as? String, id: nil)
                } else if let addr = args["address"] as? String, !addr.isEmpty {
                    self.selectFunction(name: nil, address: addr, id: nil)
                }
                self.decompileSelected()
            }
            // Give decompile a moment to land.
            try? await Task.sleep(nanoseconds: 400_000_000)
            return await MainActor.run { String(self.decompiledText.prefix(5000)) }
        case "get_xrefs":
            let addr = (args["address"] as? String)
                ?? (args["name"] as? String)
                ?? selectedFunction?.address
                ?? ""
            var resp = await mcpGet("get_xrefs_to", query: ["address": addr])
            if !resp.ok {
                resp = await mcpGet("list_xrefs", query: ["address": addr, "name": addr])
            }
            return String(resp.text.prefix(4000))
        case "rename_function":
            let newName = (args["new_name"] as? String) ?? (args["newName"] as? String) ?? ""
            let address = (args["address"] as? String) ?? selectedFunction?.address ?? ""
            let old = (args["name"] as? String) ?? selectedFunction?.name ?? ""
            let result = await MainActor.run {
                self.renameFunction(address: address, oldName: old, newName: newName, apply: true)
            }
            return result
        case "set_comment":
            let address = (args["address"] as? String) ?? selectedFunction?.address ?? ""
            let comment = (args["comment"] as? String) ?? ""
            let kind = (args["kind"] as? String) ?? "plate"
            let result = await MainActor.run {
                self.setFunctionComment(address: address, comment: comment, kind: kind, apply: true)
            }
            return result
        case "rag_discover":
            let q = (args["query"] as? String) ?? ""
            let resp = await vibePost("rag_discover", body: ["query": q])
            return String(resp.text.prefix(4000))
        case "rag_index":
            let limit = (args["limit"] as? Int) ?? 120
            let top = (args["decompile_top"] as? Int) ?? 24
            let resp = await vibePost("rag_index", body: ["limit": limit, "decompile_top": top])
            await MainActor.run {
                self.jspaceStatus = resp.ok ? "JSpace indexed" : "JSpace index failed"
            }
            return String(resp.text.prefix(2000))
        case "improve_decompile":
            return await improveDecompileTool(args: args)
        case "autonomous_re":
            let budget = (args["budget"] as? Int) ?? 8
            let apply = (args["apply"] as? Bool) ?? true
            await MainActor.run {
                self.runAutonomousREPlaybook(budget: budget, apply: apply)
            }
            return #"{"ok":true,"started":true,"budget":\#(budget)}"#
        default:
            return #"{"ok":false,"error":"unknown tool \#(name)"}"#
        }
    }

    @discardableResult
    func renameFunction(address: String, oldName: String, newName: String, apply: Bool) -> String {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return #"{"ok":false,"error":"new_name required"}"# }
        let addr = address.isEmpty ? (selectedFunction?.address ?? "") : address
        guard !addr.isEmpty else { return #"{"ok":false,"error":"address required"}"# }
        if !apply {
            agentPendingEdits.append(AgentPendingEdit(
                kind: .rename, address: addr, oldName: oldName, newName: trimmed,
                comment: "", commentKind: "plate"
            ))
            return #"{"ok":true,"pending":true,"new_name":"\#(trimmed)"}"#
        }
        if InProcessEngineHost.isRunning {
            let res = InProcessEngineHost.call("rename_function", args: [
                "address": addr,
                "name": oldName,
                "new_name": trimmed,
            ])
            consoleAppend("rename_function: \(res.message)")
            if res.ok {
                fetchFunctionsViaMCP()
                decompileSelected()
                statusMessage = "Renamed → \(trimmed)"
            }
            return res.ok
                ? #"{"ok":true,"applied":true,"new_name":"\#(trimmed)","address":"\#(addr)"}"#
                : #"{"ok":false,"error":"\#(res.message.replacingOccurrences(of: "\"", with: "'"))"}"#
        }
        // Fallback: vibe MCP (may proxy analysis / note engine required).
        ensureVibeMCP()
        Task {
            let resp = await self.vibePost("rename_function", body: [
                "address": addr, "name": oldName, "new_name": trimmed,
            ])
            await MainActor.run {
                self.consoleAppend("rename_function: \(resp.text.prefix(200))")
                if resp.ok {
                    self.fetchFunctionsViaMCP()
                    self.decompileSelected()
                }
            }
        }
        return #"{"ok":true,"queued":true,"new_name":"\#(trimmed)"}"#
    }

    @discardableResult
    func setFunctionComment(address: String, comment: String, kind: String, apply: Bool) -> String {
        let addr = address.isEmpty ? (selectedFunction?.address ?? "") : address
        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addr.isEmpty, !text.isEmpty else {
            return #"{"ok":false,"error":"address and comment required"}"#
        }
        let k = kind.lowercased().contains("eol") ? "eol" : "plate"
        if !apply {
            agentPendingEdits.append(AgentPendingEdit(
                kind: .comment, address: addr, oldName: "", newName: "",
                comment: text, commentKind: k
            ))
            return #"{"ok":true,"pending":true}"#
        }
        if InProcessEngineHost.isRunning {
            let method = k == "eol" ? "set_eol_comment" : "set_plate_comment"
            let res = InProcessEngineHost.call(method, args: [
                "address": addr,
                "comment": text,
            ])
            consoleAppend("\(method): \(res.message)")
            if res.ok {
                decompileSelected()
                statusMessage = "Comment set (\(k))"
            }
            return res.ok
                ? #"{"ok":true,"applied":true,"kind":"\#(k)"}"#
                : #"{"ok":false,"error":"\#(res.message.replacingOccurrences(of: "\"", with: "'"))"}"#
        }
        ensureVibeMCP()
        Task {
            let resp = await self.vibePost("set_comment", body: [
                "address": addr, "comment": text, "kind": k,
            ])
            await MainActor.run {
                self.consoleAppend("set_comment: \(resp.text.prefix(200))")
                if resp.ok { self.decompileSelected() }
            }
        }
        return #"{"ok":true,"queued":true,"kind":"\#(k)"}"#
    }

    func applyAgentPendingEdits() {
        let edits = agentPendingEdits
        agentPendingEdits.removeAll()
        for edit in edits {
            switch edit.kind {
            case .rename:
                _ = renameFunction(
                    address: edit.address,
                    oldName: edit.oldName,
                    newName: edit.newName,
                    apply: true
                )
            case .comment:
                _ = setFunctionComment(
                    address: edit.address,
                    comment: edit.comment,
                    kind: edit.commentKind,
                    apply: true
                )
            }
        }
        fetchFunctionsViaMCP()
        decompileSelected()
        agentMessages.append(AgentMessage(
            role: .assistant,
            text: "Applied \(edits.count) pending edit(s). Functions/Decompile refreshed."
        ))
    }

    func clearAgentPendingEdits() {
        agentPendingEdits.removeAll()
    }

    func queueImproveDecompile(name: String?, address: String?, apply: Bool) {
        Task {
            let out = await self.improveDecompileTool(args: [
                "name": name ?? "",
                "address": address ?? "",
                "apply": apply,
            ])
            await MainActor.run {
                self.agentMessages.append(AgentMessage(role: .assistant, text: out))
                self.statusMessage = "improve_decompile done"
            }
        }
    }

    private func improveDecompileTool(args: [String: Any]) async -> String {
        await MainActor.run {
            if let name = args["name"] as? String, !name.isEmpty {
                self.selectFunction(name: name, address: args["address"] as? String, id: nil)
            }
            self.decompileSelected()
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        let before = await MainActor.run { self.decompiledText }
        let apply = (args["apply"] as? Bool) ?? false
        let fn = await MainActor.run { self.selectedFunction }
        let route = await MainActor.run {
            self.routeAgentMoE(
                userText: "improve decompile readability \(fn?.name ?? "")",
                force: .decompile
            )
        }
        var cfg = route.config
        let prompt = """
        Improve readability of this Ghidra decompile by proposing:
        1) a better function name (if FUN_/sub_/thunk_)
        2) a short plate comment summary
        Reply as lines: `old` → `new` for renames, and COMMENT: ... for the plate comment.
        Do not invent source code.

        Function: \(fn?.name ?? "?") @ \(fn?.address ?? "?")
        ```
        \(String(before.prefix(4500)))
        ```
        """
        do {
            let result: LocalAIChatResult
            do {
                result = try await LocalAIClient.chat(
                    config: cfg,
                    messages: [
                        LocalAIChatMessage(role: "system", content: AgentTools.systemPrompt),
                        LocalAIChatMessage(role: "user", content: prompt),
                    ],
                    tools: []
                )
            } catch {
                if let cloud = AgentMoERouter.cloudFallback(
                    moe: await MainActor.run { self.agentMoE },
                    role: .decompile,
                    local: cfg
                ) {
                    cfg = cloud
                    result = try await LocalAIClient.chat(
                        config: cfg,
                        messages: [
                            LocalAIChatMessage(role: "system", content: AgentTools.systemPrompt),
                            LocalAIChatMessage(role: "user", content: prompt),
                        ],
                        tools: []
                    )
                } else {
                    throw error
                }
            }
            let text = result.content ?? ""
            let renames = AgentTools.parseRenameTable(from: text)
            var comment = ""
            for line in text.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.uppercased().hasPrefix("COMMENT:") {
                    comment = String(t.dropFirst("COMMENT:".count)).trimmingCharacters(in: .whitespaces)
                }
            }
            await MainActor.run {
                let addr = fn?.address ?? ""
                for pair in renames.prefix(8) {
                    if apply {
                        _ = self.renameFunction(
                            address: addr, oldName: pair.old, newName: pair.new, apply: true
                        )
                    } else {
                        self.agentPendingEdits.append(AgentPendingEdit(
                            kind: .rename, address: addr, oldName: pair.old, newName: pair.new,
                            comment: "", commentKind: "plate"
                        ))
                    }
                }
                if !comment.isEmpty {
                    if apply {
                        _ = self.setFunctionComment(
                            address: addr, comment: comment, kind: "plate", apply: true
                        )
                    } else {
                        self.agentPendingEdits.append(AgentPendingEdit(
                            kind: .comment, address: addr, oldName: "", newName: "",
                            comment: comment, commentKind: "plate"
                        ))
                    }
                }
                self.decompileSelected()
            }
            let after = await MainActor.run { String(self.decompiledText.prefix(2000)) }
            return """
            ## Before
            \(String(before.prefix(1500)))

            ## Proposal
            \(text.prefix(2000))

            ## After preview
            \(after)
            apply=\(apply) pending=\(await MainActor.run { self.agentPendingEdits.count })
            """
        } catch {
            return #"{"ok":false,"error":"\#(error.localizedDescription)"}"#
        }
    }

    /// Autonomous RE playbook — budgeted rename/comment pass with Task Monitor + session report.
    func runAutonomousREPlaybook(budget: Int = 8, apply: Bool = true) {
        guard !agentBusy else {
            statusMessage = "Agent busy"
            return
        }
        agentBusy = true
        beginTaskMonitor()
        statusMessage = "Autonomous RE…"
        ensureVibeMCP()
        let route = routeAgentMoE(userText: "autonomous RE playbook", force: .plan)
        agentMessages.append(AgentMessage(
            role: .assistant,
            text: "Starting Autonomous RE (budget=\(budget), apply=\(apply), expert=\(route.role.title) / \(route.config.model))…"
        ))

        Task {
            var report: [String] = []
            report.append("# Autonomous RE session")
            report.append("moe=\(route.role.rawValue) backend=\(route.config.backend.rawValue) model=\(route.config.model)")

            // 1) Index JSpace if empty-ish
            let stats = await self.vibeGet("rag_stats")
            let needIndex = !stats.ok || stats.text.lowercased().contains("empty")
                || stats.text.contains("\"count\":0")
            if needIndex {
                report.append("- indexing JSpace…")
                _ = await self.vibePost("rag_index", body: ["limit": 100, "decompile_top": 20])
            } else {
                report.append("- JSpace index present")
            }

            // 2) Rank interesting functions
            await MainActor.run { self.fetchFunctionsViaMCP() }
            try? await Task.sleep(nanoseconds: 300_000_000)
            let targets = await MainActor.run { () -> [FunctionRow] in
                let scored = self.functions.map { fn -> (Int, FunctionRow) in
                    var score = 0
                    let n = fn.name
                    if n == "entry" || n == "_main" || n == "main" || n.hasPrefix("start") { score += 50 }
                    if n.hasPrefix("FUN_") || n.hasPrefix("sub_") || n.hasPrefix("thunk_") { score += 30 }
                    if n.contains(" ") || n.hasPrefix("-[") || n.hasPrefix("+[") { score += 20 }
                    if n.count > 24 { score += 5 }
                    return (score, fn)
                }
                return scored.sorted { $0.0 > $1.0 }.prefix(budget).map(\.1)
            }
            report.append("- targets: \(targets.map(\.name).joined(separator: ", "))")

            var renamed = 0
            var commented = 0
            for fn in targets {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.selectFunction(name: fn.name, address: fn.address, id: fn.id)
                    self.decompileSelected()
                    self.statusMessage = "Autonomous RE: \(fn.name)"
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
                let out = await self.improveDecompileTool(args: [
                    "name": fn.name,
                    "address": fn.address,
                    "apply": apply,
                ])
                if out.contains("→") || out.lowercased().contains("renamed") || out.contains("Proposal") {
                    renamed += 1
                }
                if out.uppercased().contains("COMMENT:") { commented += 1 }
                report.append("### \(fn.name) @ \(fn.address)\n\(String(out.prefix(800)))")
            }

            report.append("")
            report.append("## Summary")
            report.append("- functions processed: \(targets.count)")
            report.append("- rename/comment passes: \(renamed)")
            report.append("- comment hits: \(commented)")
            report.append("- pending edits: \(await MainActor.run { self.agentPendingEdits.count })")

            let text = report.joined(separator: "\n")
            await MainActor.run {
                self.consoleAppend("Autonomous RE complete\n\(text.prefix(2000))")
                self.agentMessages.append(AgentMessage(role: .assistant, text: text))
                self.fetchFunctionsViaMCP()
                self.decompileSelected()
                self.agentBusy = false
                self.endTaskMonitor()
                self.statusMessage = "Autonomous RE done (\(targets.count) functions)"
            }
        }
    }

    private func runDetached(
        _ launchPath: String,
        arguments: [String],
        logFile: URL? = nil
    ) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        // Ensure engine script can find detect-maxmem when launched from the .app.
        if env["GHIDRA_VIBE_LIB"] == nil || env["GHIDRA_VIBE_LIB"]?.isEmpty == true {
            // GHIDRA_INSTALL_DIR is …/lib/ghidra → lib helpers at …/share/ghidra-vibe/lib
            var candidates: [String] = []
            if let install = env["GHIDRA_INSTALL_DIR"], !install.isEmpty {
                let root = ((install as NSString)
                    .deletingLastPathComponent as NSString) // …/lib
                    .deletingLastPathComponent // …/package root
                candidates.append(root + "/share/ghidra-vibe/lib")
            }
            candidates.append(Bundle.main.bundlePath + "/Contents/Resources/lib")
            for path in candidates {
                if FileManager.default.fileExists(atPath: path + "/detect-maxmem.sh") {
                    env["GHIDRA_VIBE_LIB"] = path
                    break
                }
            }
        }
        proc.environment = env
        if let logFile {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
            if let fh = try? FileHandle(forWritingTo: logFile) {
                proc.standardOutput = fh
                proc.standardError = fh
            } else {
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
            }
        } else {
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
        }
        do {
            try proc.run()
        } catch {
            statusMessage = "Launch failed: \(error.localizedDescription)"
            consoleAppend("Launch failed: \(launchPath) — \(error.localizedDescription)")
        }
    }

    private func runCapture(_ launchPath: String, arguments: [String]) -> String? {
        // Prefer runCaptureOffMain from UI paths — this sync form blocks the caller.
        Self.runCaptureSync(launchPath, arguments: arguments)
    }

    /// Run helpers off the main actor so DSC import / jspace never beach-ball the UI.
    private nonisolated static func runCaptureOffMain(
        _ launchPath: String, arguments: [String]
    ) async -> String? {
        await Task.detached(priority: .userInitiated) {
            runCaptureSync(launchPath, arguments: arguments)
        }.value
    }

    private nonisolated static func runCaptureSync(
        _ launchPath: String, arguments: [String]
    ) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private nonisolated static func parseFunctionList(_ text: String) -> [FunctionRow] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        if trimmed.contains("\"error\""), !trimmed.contains("\"name\"") {
            return []
        }
        // JSON object with data: [{name,address}, ...] or data: ["name at addr", ...]
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data)
        {
            var items: [Any] = []
            if let arr = json as? [Any] {
                items = arr
            } else if let obj = json as? [String: Any] {
                if obj["error"] != nil, obj["data"] == nil { return [] }
                items = (obj["data"] as? [Any])
                    ?? (obj["functions"] as? [Any])
                    ?? (obj["methods"] as? [Any])
                    ?? []
            }
            return items.prefix(5000).enumerated().compactMap { idx, item in
                if let dict = item as? [String: Any] {
                    let name = (dict["name"] as? String) ?? ""
                    let addr = (dict["address"] as? String)
                        ?? (dict["addr"] as? String)
                        ?? ""
                    guard !name.isEmpty else { return nil }
                    return FunctionRow(id: "\(idx)-\(name)-\(addr)", name: name, address: addr)
                }
                if let line = item as? String {
                    return parseFunctionLine(idx, line)
                }
                return nil
            }
        }
        return trimmed
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { !$0.contains("\"error\"") }
            .prefix(5000)
            .enumerated()
            .compactMap { parseFunctionLine($0.offset, $0.element) }
    }

    private nonisolated static func parseFunctionLine(_ idx: Int, _ line: String) -> FunctionRow? {
        let line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.contains("\"error\"") else { return nil }
        if let at = line.range(of: " at ") ?? line.range(of: " @ ") {
            let name = String(line[..<at.lowerBound]).trimmingCharacters(in: .whitespaces)
            let addr = String(line[at.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return FunctionRow(id: "\(idx)-\(name)", name: name, address: addr)
        }
        if line.contains(",") {
            let parts = line.split(separator: ",", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                return FunctionRow(id: "\(idx)-\(parts[1])", name: parts[1], address: parts[0])
            }
        }
        return FunctionRow(id: "\(idx)-\(line)", name: line, address: "")
    }
}

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case projects = "Projects"
    case functions = "Functions"
    case decompiler = "Decompiler"
    case listing = "Listing"
    case xrefs = "Xrefs / Strings"
    case inspector = "Inspector"
    case agent = "Agent"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .projects: "folder"
        case .functions: "function"
        case .decompiler: "chevron.left.forwardslash.chevron.right"
        case .listing: "list.bullet.rectangle"
        case .xrefs: "arrow.left.arrow.right"
        case .inspector: "sidebar.trailing"
        case .agent: "bubble.left.and.bubble.right"
        }
    }
}

struct FunctionRow: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var address: String
}

struct AgentMessage: Identifiable, Hashable {
    enum Role: String { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
}
