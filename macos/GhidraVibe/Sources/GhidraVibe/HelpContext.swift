import Foundation

/// Stock JavaHelp `mapID` resolution for F1 / context Help.
enum HelpContext {
    /// Default article when no specific map id matches.
    static let fallbackMapId = "Misc_Help_Contents"

    /// Provider → primary stock mapID (must exist in packaged `map.json`).
    static func mapId(for provider: ProviderKind) -> String {
        switch provider {
        case .listing: "CodeBrowserPlugin_CodeBrowser"
        case .decompiler: "DecompilePlugin_DecompilerIntro"
        case .programTree: "ProgramTreePlugin_Program_Tree"
        case .symbolTree: "SymbolTreePlugin_Symbol_Tree"
        case .dataTypes: "DataTypeManagerPlugin_data_type_manager_window"
        case .console: "ConsolePlugin_ConsolePlugin"
        case .bytes: "ByteViewerPlugin_The_Byte_Viewer"
        case .functions: "FunctionWindowPlugin_function_window"
        case .strings: "DefinedStringsPlugin_DefinedStringsPlugin"
        case .memoryMap: "MemoryMapPlugin_Memory_Map"
        case .bookmarks: "BookmarkPlugin_Bookmarks"
        case .functionGraph: "FunctionGraphPlugin_FunctionGraphPlugin"
        case .equates: "EquatePlugin_Display_Equates_Table"
        case .relocations: "RelocationTablePlugin_Relocation_Table"
        case .registers: "RegisterPlugin_Register_Manager"
        case .symbolTable: "SymbolTablePlugin_Symbol_Table"
        case .scriptManager: "GhidraScriptMgrPlugin_Script_Manager"
        case .comments: "CommentsPlugin_Comments"
        case .entropy: "OverviewPlugin_EntropyOverviewBar"
        case .overview: "OverviewPlugin_EntropyOverviewBar"
        case .python: "PyGhidra_PyGhidra"
        case .versionTracking: "VersionTrackingPlugin_Version_Tracking_Intro"
        case .mcp: "GhidraVibe_vibe_mcp"
        case .agent: "GhidraVibe_vibe_agent"
        case .rag: "GhidraVibe_vibe_agent"
        case .rules: "GhidraVibe_vibe_agent"
        case .dsc: "GhidraVibe_vibe_dsc"
        case .appleBundle: "GhidraVibe_vibe_welcome"
        case .swiftClasses: "GhidraVibe_vibe_welcome"
        case .codeEditor: "GhidraVibe_vibe_welcome"
        default: fallbackMapId
        }
    }

    /// Menu / GuiControl action id → mapID.
    static func mapId(forAction actionId: String) -> String? {
        switch actionId {
        case "show_help", "welcome_help", "context_help":
            return fallbackMapId
        case "tip_of_the_day":
            return "Tool_Tip_Of_The_Day"
        case "show_project", "open_project", "new_project":
            return "FrontEndPlugin_Project_Window"
        case "codebrowser", "show_codebrowser":
            return "CodeBrowserPlugin_CodeBrowser"
        case "open_shared_cache", "show_dsc", "dyld_open":
            return "GhidraVibe_vibe_dsc"
        case "auto_analyze", "analyze":
            return "AutoAnalysisPlugin_AutoAnalysis"
        default:
            if actionId.hasPrefix("show_"),
               let kind = ProviderKind(rawValue: String(actionId.dropFirst("show_".count)))
            {
                return mapId(for: kind)
            }
            return nil
        }
    }

    /// Resolve mapID against the live catalog (falls back if missing).
    static func resolve(_ mapId: String, catalog: HelpCatalog? = HelpCatalog.load()) -> String {
        guard let catalog else { return fallbackMapId }
        if catalog.map[mapId] != nil { return mapId }
        // Soft aliases / stem match
        if let hit = catalog.map.keys.first(where: { $0 == mapId || $0.hasSuffix("_\(mapId)") }) {
            return hit
        }
        return fallbackMapId
    }
}
