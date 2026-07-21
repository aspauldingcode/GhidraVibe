import Foundation

enum ToolMode: String, CaseIterable, Identifiable {
    case splash = "Starting…"
    case workspacePicker = "Select Project"
    case projectWindow = "Project Window"
    case codeBrowser = "CodeBrowser"
    case debugger = "Debugger"
    case emulator = "Emulator"
    case versionTrackingTool = "Version Tracking"
    case welcomeHelp = "Ghidra Help"

    var id: String { rawValue }

    /// Stock Tool Chest tools (Front End).
    var isStockTool: Bool {
        switch self {
        case .codeBrowser, .debugger, .emulator, .versionTrackingTool: true
        default: false
        }
    }
}

/// Mirrors every COMPONENT_INFO in CodeBrowser.tool (+ vibe + Apple RE panels).
enum ProviderKind: String, CaseIterable, Identifiable {
    case programTree = "program_tree"
    case symbolTree = "symbol_tree"
    case dataTypes = "data_types"
    case listing
    case decompiler
    case console
    case entropy
    case overview
    case bytes
    case definedData = "defined_data"
    case strings
    case equates
    case externalPrograms = "external_programs"
    case functions
    case relocations
    case datatypePreview = "datatype_preview"
    case disassembledView = "disassembled_view"
    case bookmarks
    case scriptManager = "script_manager"
    case memoryMap = "memory_map"
    case functionGraph = "function_graph"
    case registers
    case symbolTable = "symbol_table"
    case symbolReferences = "symbol_references"
    case checksum
    case functionTags = "function_tags"
    case comments
    case python
    case mcp
    case agent
    case rag
    case rules
    case dsc
    case appleBundle = "apple_bundle"
    case swiftClasses = "swift_classes"
    case codeEditor = "code_editor"
    /// Stock Front End Tool Chest — blue footprints (Version Tracking tool).
    case versionTracking = "version_tracking"

    var id: String { rawValue }

    var a11yRoot: String { "ghidra.vibe.provider.\(rawValue)" }

    var title: String {
        switch self {
        case .programTree: "Program Trees"
        case .symbolTree: "Symbol Tree"
        case .dataTypes: "Data Type Manager"
        case .listing: "Listing"
        case .decompiler: "Decompile"
        case .console: "Console"
        case .entropy: "Entropy"
        case .overview: "Overview"
        case .bytes: "Bytes"
        case .definedData: "Defined Data"
        case .strings: "Defined Strings"
        case .equates: "Equates Table"
        case .externalPrograms: "External Programs"
        case .functions: "Functions"
        case .relocations: "Relocation Table"
        case .datatypePreview: "Data Type Preview"
        case .disassembledView: "Disassembled View"
        case .bookmarks: "Bookmarks"
        case .scriptManager: "Script Manager"
        case .memoryMap: "Memory Map"
        case .functionGraph: "Function Graph"
        case .registers: "Register Manager"
        case .symbolTable: "Symbol Table"
        case .symbolReferences: "Symbol References"
        case .checksum: "Checksum Generator"
        case .functionTags: "Function Tags"
        case .comments: "Comments"
        case .python: "Python"
        case .mcp: "MCP"
        case .agent: "Agent"
        case .rag: "RAG / JSpace"
        case .rules: "Rules"
        case .dsc: "Shared Cache"
        case .appleBundle: "App Bundle"
        case .swiftClasses: "Classes"
        case .codeEditor: "Code Editor"
        case .versionTracking: "Version Tracking"
        }
    }

    static let defaultDocked: [ProviderKind] = [
        .programTree, .symbolTree, .dataTypes, .swiftClasses, .listing, .decompiler, .console,
    ]

    /// Bottom strip under listing (stock CodeBrowser.tool).
    static let bottomStrip: [ProviderKind] = [.datatypePreview, .disassembledView]

    /// Console tab stack (stock: Console + Bookmarks).
    static let consoleStack: [ProviderKind] = [.console, .bookmarks]

    /// Window menu extras (excludes default dock + bottom strip — those are listed explicitly).
    /// Agent is omitted — it is a trailing sidebar, not a modular Window provider.
    static var windowMenuOrder: [ProviderKind] {
        allCases.filter {
            !defaultDocked.contains($0)
                && !bottomStrip.contains($0)
                && $0 != .versionTracking
                && $0 != .agent
        }
    }

    /// All CodeBrowser modules shown in the leading Modules palette / Window menu.
    static var modularWindowModules: [ProviderKind] {
        allCases.filter(\.isModularDockProvider)
    }

    /// Stock CodeBrowser.tool right-stack providers (before vibe More… panes).
    static let stockRightStack: [ProviderKind] = [
        .decompiler, .bytes, .definedData, .strings, .equates, .externalPrograms,
        .functions, .relocations,
    ]

    var isCoreDocked: Bool { Self.defaultDocked.contains(self) }

    /// Dockable / floatable CodeBrowser providers (Agent is trailing-sidebar only).
    var isModularDockProvider: Bool {
        self != .agent && self != .versionTracking
    }
}
