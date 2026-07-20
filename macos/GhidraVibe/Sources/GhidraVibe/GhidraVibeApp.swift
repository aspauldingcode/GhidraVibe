import AppKit
import SwiftUI

@main
struct GhidraVibeApp: App {
    @NSApplicationDelegateAdaptor(AppActivationDelegate.self) private var activation
    @State private var model = AppModel()
    @State private var showUserAgreement = UserAgreement.needsPrompt

    /// Front End / picker — stock Project Window menu bar (no CodeBrowser Analysis…Select).
    private var isFrontEndMenus: Bool {
        switch model.toolMode {
        case .projectWindow, .workspacePicker, .splash, .welcomeHelp:
            true
        case .codeBrowser, .debugger, .emulator, .versionTrackingTool:
            false
        }
    }

    var body: some Scene {
        WindowGroup("GhidraVibe") {
            ContentRootView()
                .environment(model)
                // Mode-aware mins: Project Window must shrink; CodeBrowser needs more room.
                .frame(
                    // Stock CodeBrowser.tool is ~1637×931; keep usable mins so the left dock (~234pt) never crushes.
                    minWidth: model.toolMode == .codeBrowser ? 1100 : 480,
                    minHeight: model.toolMode == .codeBrowser ? 640 : 360
                )
                .ghidraUserAgreement(
                    isPresented: $showUserAgreement,
                    onDecline: { NSApp.terminate(nil) },
                    onAccept: {
                        UserAgreement.seedGhidraPreferencesAccepted()
                        model.ensureProgramEngineRunning(loadProgram: false)
                    }
                )
                .onAppear {
                    // Native SwiftUI `.alert` only — do not launch Swing UserAgreementDialog.
                    showUserAgreement = UserAgreement.needsPrompt
                    if UserAgreement.isAccepted {
                        UserAgreement.seedGhidraPreferencesAccepted()
                    }
                    model.startControlServer()
                    if let last = UserDefaults.standard.string(forKey: "ghidra.vibe.lastProject"),
                       FileManager.default.fileExists(atPath: last)
                    {
                        model.projectPath = last
                    }
                    // Program engine is part of the app — open last project/program like stock Ghidra.
                    if UserAgreement.isAccepted {
                        model.refreshProjectPrograms()
                        model.ensureProgramEngineRunning(loadProgram: true)
                    }
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.keyWindow?.makeKeyAndOrderFront(nil)
                }
        }
        .defaultSize(width: 1637, height: 931)
        // Inject into system App / File / Edit — never CommandMenu("File"|"Edit"|"Help"|"Window")
        // (those create duplicate menus next to macOS standards).
        // CommandsBuilder max 10 groups per .commands — split across two modifiers.
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About GhidraVibe") { model.runAction(id: "about") }
                    .help("About GhidraVibe")
            }

            CommandGroup(replacing: .newItem) {
                Button("New Project…") { model.runAction(id: "new_project") }
                    .help("Create a new Ghidra project")
                Button("Open Project…") { model.runAction(id: "open_project") }
                    .keyboardShortcut("o", modifiers: [.command])
                    .help("Open an existing Ghidra project")
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Import File…") { model.runAction(id: "import_file") }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .help("Import a single Mach-O / binary into the active project")
                Button("Open Framework from Shared Cache…") {
                    model.runAction(id: "open_framework_from_dsc")
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .help("Open a macOS/iOS framework from the on-device dyld shared cache (IDA-like)")
                Button("Open App Bundle…") { model.runAction(id: "open_app_bundle") }
                    .help("Open a .app / .ipa / .framework — Program Trees, Decompile, Classes")
                Button("Analyze App Bundle…") { model.runAction(id: "import_apple") }
                    .help("Full app-bundle analysis (resources, class dump, refs) into the project")
                Button("Browse Shared Cache…") { model.runAction(id: "open_shared_cache") }
                    .help("Browse the full Shared Cache index (advanced)")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Program") { model.runAction(id: "save_program") }
                    .keyboardShortcut("s", modifiers: [.command])
                    .help("Save the current program")
            }
            CommandGroup(after: .saveItem) {
                Button("Close Program") { model.runAction(id: "close_program") }
                    .help("Close the current program")
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { model.runAction(id: "undo") }
                    .keyboardShortcut("z", modifiers: [.command])
                    .help("Undo the last edit")
                Button("Redo") { model.runAction(id: "redo") }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .help("Redo the last undone edit")
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { model.runAction(id: "edit_cut") }
                    .help("Cut selection")
                Button("Copy") { model.runAction(id: "edit_copy") }
                    .help("Copy selection")
                Button("Paste") { model.runAction(id: "edit_paste") }
                    .help("Paste clipboard")
            }

            // CodeBrowser.chrome.json: Analysis → BSim → Graph (then Navigation… in next block)
            if !isFrontEndMenus {
                CommandMenu("Analysis") {
                    Button("Auto Analyze…") { model.runAction(id: "auto_analyze") }
                        .help("Run auto-analysis on the current program via MCP")
                }
                CommandMenu("BSim") {
                    Button("BSim Search…") { model.runAction(id: "bsim_search") }
                        .help("BSim similarity search (disabled until BSim MCP is available)")
                        .disabled(true)
                    Button("BSim Overview") { model.runAction(id: "bsim_overview") }
                        .help("BSim overview (disabled until BSim MCP is available)")
                        .disabled(true)
                }
                CommandMenu("Graph") {
                    Button("Function Graph") { model.runAction(id: "show_function_graph") }
                        .help("Open the Function Graph provider")
                }
            }
        }
        .commands {
            if !isFrontEndMenus {
                CommandMenu("Navigation") {
                    Button("Go To…") { model.runAction(id: "goto") }
                        .keyboardShortcut("g", modifiers: [.command, .shift])
                        .help("Navigate to an address or label")
                    Button("Previous Location") { model.runAction(id: "nav_back") }
                        .help("Go to the previous navigation location")
                    Button("Next Location") { model.runAction(id: "nav_fwd") }
                        .help("Go to the next navigation location")
                }
                CommandMenu("Search") {
                    Button("For Strings…") { model.runAction(id: "search_strings") }
                        .help("Search program strings")
                    Button("For Functions…") { model.runAction(id: "search_functions") }
                        .help("Search program functions")
                    Button("Memory…") { model.runAction(id: "search_memory") }
                        .help("Search program memory for a byte/ASCII pattern")
                }
                CommandMenu("Select") {
                    Button("Clear Selection") { model.runAction(id: "clear_selection") }
                        .help("Clear the current listing selection")
                }
            }

            // FrontEnd.chrome.json: Project before Tools (no File dupes — New/Open stay in File).
            if isFrontEndMenus {
                CommandMenu("Project") {
                    Button("Select Project / Workspace…") { model.runAction(id: "show_workspace") }
                        .help("Choose a recent project or workspace")
                    Button("Project Window") { model.runAction(id: "show_project") }
                        .help("Show the Front End / Project Window")
                }
            }

            CommandMenu("Tools") {
                Button("Restart Program Engine") { model.runAction(id: "start_mcp") }
                    .help("Restart the local Ghidra program engine (no Cursor MCP required)")
                Button("Engine Status") { model.runAction(id: "mcp_health") }
                    .help("Check program engine status")
                if isFrontEndMenus {
                    Divider()
                    Button("CodeBrowser") { model.runAction(id: "show_codebrowser") }
                        .help("Open CodeBrowser for the current program")
                }
            }

            // System Window menu (not a second "Window" CommandMenu).
            CommandGroup(before: .windowList) {
                Button("Project Window") { model.runAction(id: "show_project") }
                    .help("Show the Front End / Project Window")
                Button("CodeBrowser") { model.runAction(id: "show_codebrowser") }
                    .help("Open CodeBrowser for the current program")
                Divider()
                ForEach(ProviderKind.defaultDocked) { kind in
                    Button(kind.title) { model.showProvider(kind) }
                        .help("Show \(kind.title)")
                }
                Divider()
                ForEach(ProviderKind.bottomStrip) { kind in
                    Button(kind.title) { model.showProvider(kind) }
                        .help("Show \(kind.title)")
                }
                Divider()
                ForEach(ProviderKind.windowMenuOrder) { kind in
                    Button(kind.title) { model.showProvider(kind) }
                        .help("Show \(kind.title)")
                }
            }

            // System Help — About lives under the app menu (HIG).
            CommandGroup(replacing: .help) {
                Button("GhidraVibe Help…") { model.runAction(id: "show_help") }
                    .help("Open Ghidra Help / Welcome")
                Button("Tip of the Day…") { model.runAction(id: "tip_of_the_day") }
                    .help("Show Tip of the Day")
                Button("Headless Help") { model.runAction(id: "headless_help") }
                    .help("How to run headless analysis MCP")
                    .a11yCatalog("ghidra.vibe.menu.help.headless")
            }
        }

        // Floating undocked providers (stock DockingWindowManager float).
        WindowGroup(id: "ghidra.vibe.floating.provider", for: String.self) { $raw in
            if let raw, let kind = ProviderKind(rawValue: raw) {
                FloatingProviderRoot(kind: kind)
                    .environment(model)
            } else {
                Text("No provider")
                    .padding()
            }
        }
        .defaultSize(width: 520, height: 420)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
