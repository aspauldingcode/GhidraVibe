import SwiftUI

/// Native stand-in for stock “Ghidra Help” / Welcome screen (two-pane).
struct WelcomeHelpView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: HelpTopic = .welcome

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selected) { topic in
                Label(topic.title, systemImage: topic.symbol)
                    .tag(topic)
                    .accessibilityIdentifier("ghidra.vibe.help.topic.\(topic.rawValue)")
            }
            .navigationTitle("Ghidra Help")
            .a11yCatalog("ghidra.vibe.help.toc")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(selected.title)
                        .font(.largeTitle.weight(.semibold))
                    Text(selected.body)
                        .font(.body)
                        .textSelection(.enabled)
                    if selected == .welcome {
                        Button("Open Project Window") {
                            model.dismissWelcomeHelp()
                            if model.toolMode != .projectWindow {
                                model.enterProjectWindow()
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .a11yCatalog("ghidra.vibe.help.open_project")
                    }
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
            }
            .a11yCatalog("ghidra.vibe.help.content")
        }
        .a11yContainerCatalog("ghidra.vibe.help")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { model.dismissWelcomeHelp() }
                    .a11yCatalog("ghidra.vibe.help.close")
            }
        }
    }
}

enum HelpTopic: String, CaseIterable, Identifiable, Hashable {
    case welcome
    case gettingStarted
    case projects
    case codeBrowser
    case mcp
    case dsc
    case agent
    case support

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
            Ghidra: NSA Reverse Engineering Software

            Ghidra is a software reverse engineering (SRE) framework. GhidraVibe is Ghidra with a native macOS/Linux GUI — the engine runs in-process; Swing Front End is not shipped.

            What's New in this shell
            • Project Window + CodeBrowser layout mirrored from CodeBrowser.tool
            • Integrated MCP, Agent chat, JSpace RAG, and Rules
            • On-device dyld shared cache import with Apple symbols (macOS)

            The not-so-fine print: Please Read!
            Analysis uses JDK 21 embedded in the GhidraVibe process. Accept the User Agreement on first launch (native alert).
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
            Projects are Ghidra `.gpr` files (same on-disk format as stock). Create or open a project from the workspace picker or Project Window. Programs appear in the Active Project tree after import / load via MCP.
            """
        case .codeBrowser:
            """
            CodeBrowser hosts Program Trees, Symbol Tree, Data Type Manager, Listing, Decompiler, and Console — matching stock default layout. Use the Window menu for Functions, Strings, Memory Map, and vibe panels (MCP, Agent, RAG, Rules, Shared Cache).
            """
        case .mcp:
            """
            Program engine API (default http://127.0.0.1:8089) runs in-process with the GUI. Cursor/agents can use the same endpoints or true headless CLI. GuiControl (:8091) drives the native shell for automation.
            """
        case .dsc:
            """
            File → Open Shared Cache… opens the DSC Index (on-device dyld cache). Filter (e.g. AppKit), then Load selected or double-click — same as IDA: header/index open, load one module with Apple local symbols. Auto-analyze is optional afterward.
            """
        case .agent:
            """
            The Agent panel runs JSpace RAG discovery then optional MCP decompile/list. Index JSpace after a program is loaded. Rules edits the local playbook used by discovery.
            """
        case .support:
            """
            Docs: docs/GUI.md, docs/DYLD.md, docs/GUI_TESTING.md
            Accessibility: native-ui/a11y/catalog.json — automate with agent-device (id= selectors).
            Stock Swing Front End is not shipped — GhidraVibe native UI is the only GUI.
            """
        }
    }
}
