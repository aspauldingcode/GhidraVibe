import SwiftUI

/// Stable accessibility identifiers for agent-device / XCTest automation.
/// Prefer `id="…"` selectors in tests; labels are human-readable fallbacks.
enum A11yID {
    static let root = "ghidra.vibe.root"
    static let sidebar = "ghidra.vibe.sidebar"
    static let contentColumn = "ghidra.vibe.content"
    static let detailWorkspace = "ghidra.vibe.detail"
    static let statusBar = "ghidra.vibe.status.bar"
    static let statusMessage = "ghidra.vibe.status.message"
    static let mcpStatusChip = "ghidra.vibe.status.mcp"

    static let toolbarMCPHealth = "ghidra.vibe.toolbar.mcp_health"
    static let toolbarFetchFunctions = "ghidra.vibe.toolbar.fetch_functions"
    static let toolbarDecompile = "ghidra.vibe.toolbar.decompile"
    static let toolbarDyld = "ghidra.vibe.toolbar.dyld"
    static let toolbarDyldOpen = "ghidra.vibe.toolbar.dyld_open"
    static let toolbarCodeBrowser = "ghidra.vibe.toolbar.codebrowser"

    static let dyldCachePath = "ghidra.vibe.provider.dsc.cache_path"
    static let dyldImageSearch = "ghidra.vibe.provider.dsc.image_search"
    static let dyldImageList = "ghidra.vibe.provider.dsc.image_list"
    static let dyldRefresh = "ghidra.vibe.provider.dsc.refresh"

    static let agentPane = "ghidra.vibe.agent"
    static let agentWelcome = "ghidra.vibe.agent.welcome"
    static let agentWelcomeTitle = "ghidra.vibe.agent.welcome.title"
    static let agentWelcomeBody = "ghidra.vibe.agent.welcome.body"
    static let agentWelcomeStart = "ghidra.vibe.agent.welcome.start"
    static let agentWelcomeOptOut = "ghidra.vibe.agent.welcome.opt_out"
    static let agentTranscript = "ghidra.vibe.agent.transcript"
    static let agentComposer = "ghidra.vibe.agent.composer"
    static let agentSend = "ghidra.vibe.agent.send"
    static let agentApiDisabled = "ghidra.vibe.agent.api_disabled"
    static let agentApiKeyFile = "ghidra.vibe.agent.api_key_file"
    static let agentJSpaceStatus = "ghidra.vibe.agent.jspace_status"
    static let agentJSpaceIndex = "ghidra.vibe.agent.jspace_index"

    static func sidebarItem(_ item: SidebarItem) -> String {
        "ghidra.vibe.sidebar.\(item.idKey)"
    }

    static let projectsPane = "ghidra.vibe.projects"
    static let projectsExtractedPath = "ghidra.vibe.projects.extracted_path"
    static let projectsMCPURL = "ghidra.vibe.projects.mcp_url"
    static let projectsRefreshExtracted = "ghidra.vibe.projects.refresh_extracted"
    static let projectsOpenCodeBrowser = "ghidra.vibe.projects.open_codebrowser"
    static let projectsStartBridge = "ghidra.vibe.projects.start_bridge"

    static let functionsPane = "ghidra.vibe.functions"
    static let functionsSearch = "ghidra.vibe.functions.search"
    static let functionsReload = "ghidra.vibe.functions.reload"
    static let functionsList = "ghidra.vibe.functions.list"
    static func functionRow(_ id: String) -> String {
        "ghidra.vibe.functions.row.\(id)"
    }

    static let decompilerPane = "ghidra.vibe.decompiler"
    static let decompilerText = "ghidra.vibe.decompiler.text"
    static let decompilerRefresh = "ghidra.vibe.decompiler.refresh"

    static let listingPane = "ghidra.vibe.listing"
    static let listingText = "ghidra.vibe.listing.text"
    static let listingRefresh = "ghidra.vibe.listing.refresh"

    static let xrefsPane = "ghidra.vibe.xrefs"
    static let xrefsPreview = "ghidra.vibe.xrefs.preview"
    static let xrefsProbeStrings = "ghidra.vibe.xrefs.probe_strings"
    static let xrefsSelected = "ghidra.vibe.xrefs.selected"

    static let inspectorPane = "ghidra.vibe.inspector"
    static let inspectorServerURL = "ghidra.vibe.inspector.server_url"
    static let inspectorStatus = "ghidra.vibe.inspector.status"
    static let inspectorRecheck = "ghidra.vibe.inspector.recheck"

    static let detailFunctionName = "ghidra.vibe.detail.function_name"
    static let detailFunctionAddress = "ghidra.vibe.detail.function_address"
    static let detailDecompileBody = "ghidra.vibe.detail.decompile_body"

    static let settingsForm = "ghidra.vibe.settings"
    static let settingsServerURL = "ghidra.vibe.settings.server_url"
    static let alertHeadlessOK = "ghidra.vibe.alert.headless.ok"
}

extension SidebarItem {
    var idKey: String {
        switch self {
        case .projects: "projects"
        case .functions: "functions"
        case .decompiler: "decompiler"
        case .listing: "listing"
        case .xrefs: "xrefs"
        case .inspector: "inspector"
        case .agent: "agent"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .projects: "Shows workspace paths and dyld / project actions"
        case .functions: "Lists functions from the open program for search and selection"
        case .decompiler: "Shows decompiled C for the selected function"
        case .listing: "Shows disassembly listing for the selected function"
        case .xrefs: "Shows cross-references and string probes"
        case .inspector: "Shows program-engine URL, health, and tool paths"
        case .agent: "Optional in-app agent chat (Cursor MCP bridges are optional)"
        }
    }
}

extension View {
    /// Leaf control: identifier + label (+ optional hint/traits).
    /// Do not use on containers that wrap other automatable controls.
    @ViewBuilder
    func a11y(
        _ id: String,
        label: String,
        hint: String? = nil,
        traits: AccessibilityTraits = []
    ) -> some View {
        if let hint, !hint.isEmpty, !traits.isEmpty {
            self
                .accessibilityIdentifier(id)
                .accessibilityLabel(label)
                .accessibilityHint(hint)
                .accessibilityAddTraits(traits)
        } else if let hint, !hint.isEmpty {
            self
                .accessibilityIdentifier(id)
                .accessibilityLabel(label)
                .accessibilityHint(hint)
        } else if !traits.isEmpty {
            self
                .accessibilityIdentifier(id)
                .accessibilityLabel(label)
                .accessibilityAddTraits(traits)
        } else {
            self
                .accessibilityIdentifier(id)
                .accessibilityLabel(label)
        }
    }

    /// Container: keep children visible to agent-device / AX; only stamp an identifier.
    func a11yContainer(_ id: String) -> some View {
        self
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(id)
    }
}
