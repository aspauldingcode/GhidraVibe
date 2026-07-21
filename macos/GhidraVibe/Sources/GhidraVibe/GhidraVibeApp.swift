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
        // ── Splash: separate undecorated window (stock JWindow). Never morphs into Project Window.
        Window("Ghidra", id: WindowChrome.splashWindowID) {
            SplashView()
                .environment(model)
                .vibeGlobalTheme()
                .ghidraUserAgreement(
                    isPresented: $showUserAgreement,
                    onDecline: { NSApp.terminate(nil) },
                    onAccept: {
                        UserAgreement.seedGhidraPreferencesAccepted()
                        model.ensureProgramEngineRunning(loadProgram: false)
                    }
                )
                .onAppear {
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
                    if UserAgreement.isAccepted {
                        model.refreshProjectPrograms()
                        model.ensureProgramEngineRunning(loadProgram: true)
                    }
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    ThemeStore.shared.applyToApp()
                    Task { await ThemeStore.shared.refreshThemes() }
                }
        }
        .defaultSize(width: WindowChrome.splashSize.width, height: WindowChrome.splashSize.height)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.presented)
        .windowStyle(.plain)

        // ── Project Window / tools: Tahoe unified chrome from first paint (suppressed until splash ends).
        WindowGroup(id: WindowChrome.mainWindowID) {
            ContentRootView()
                .environment(model)
                .vibeGlobalTheme()
                .frame(
                    // CodeBrowser dock mins are compressible; keep floor aligned with WindowChrome.applyMain.
                    minWidth: model.toolMode == .codeBrowser ? 780 : WindowChrome.frontEndSize.width * 0.85,
                    minHeight: model.toolMode == .codeBrowser ? 560 : WindowChrome.frontEndSize.height * 0.8
                )
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.keyWindow?.makeKeyAndOrderFront(nil)
                    ThemeStore.shared.applyToApp()
                    Task { await ThemeStore.shared.refreshThemes() }
                }
                .onDisappear {
                    model.persistAgentChatNow()
                }
        }
        .defaultSize(
            width: WindowChrome.frontEndSize.width,
            height: WindowChrome.frontEndSize.height
        )
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(.suppressed)
        // Inject into system App / File / Edit — never CommandMenu("File"|"Edit"|"Help"|"Window")
        // (those create duplicate menus next to macOS standards).
        // CommandsBuilder max 10 groups per .commands — split across two modifiers.
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About GhidraVibe") { model.runAction(id: "about") }
                    .help("About GhidraVibe")
            }

            // File — Tahoe icons only on clarity actions; shortcuts right-aligned by system.
            CommandGroup(replacing: .newItem) {
                Button("New Project…", systemImage: "plus.doc") {
                    model.runAction(id: "new_project")
                }
                .help("Create a new Ghidra project")
                Button("Open Project…", systemImage: "folder") {
                    model.runAction(id: "open_project")
                }
                .keyboardShortcut("o", modifiers: [.command])
                .help("Open an existing Ghidra project")
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Import File…", systemImage: "square.and.arrow.down.on.square") {
                    model.runAction(id: "import_file")
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .help("Import a single Mach-O / binary into the active project")
                Button("Open Framework from Shared Cache…", systemImage: "internaldrive") {
                    model.runAction(id: "open_framework_from_dsc")
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .help("Open a macOS/iOS framework from the on-device dyld shared cache (IDA-like)")
                Button("Open App Bundle…", systemImage: "apple.logo") {
                    model.runAction(id: "open_app_bundle")
                }
                .help("Open a .app / .ipa / .framework — Program Trees, Decompile, Classes")
                Button("Analyze App Bundle…", systemImage: "shippingbox") {
                    model.runAction(id: "import_apple")
                }
                .help("Full app-bundle analysis (resources, class dump, refs) into the project")
                Button("Browse Shared Cache…", systemImage: "externaldrive") {
                    model.runAction(id: "open_shared_cache")
                }
                .help("Browse the full Shared Cache index (advanced)")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Program", systemImage: "square.and.arrow.down") {
                    model.runAction(id: "save_program")
                }
                .keyboardShortcut("s", modifiers: [.command])
                .help("Save the current program")
            }
            CommandGroup(after: .saveItem) {
                Button("Close Program", systemImage: "xmark.circle") {
                    model.runAction(id: "close_program")
                }
                .help("Close the current program")
            }

            // Edit — standard icons + shortcuts (must appear in menubar when bound in-app).
            CommandGroup(replacing: .undoRedo) {
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    model.runAction(id: "undo")
                }
                .keyboardShortcut("z", modifiers: [.command])
                .help("Undo the last edit")
                Button("Redo", systemImage: "arrow.uturn.forward") {
                    model.runAction(id: "redo")
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("Redo the last undone edit")
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut", systemImage: "scissors") {
                    model.runAction(id: "edit_cut")
                }
                .keyboardShortcut("x", modifiers: [.command])
                .help("Cut selection (text field when focused; else listing)")
                Button("Copy", systemImage: "doc.on.doc") {
                    model.runAction(id: "edit_copy")
                }
                .keyboardShortcut("c", modifiers: [.command])
                .help("Copy selection (text field when focused; else listing / decompile)")
                Button("Paste", systemImage: "doc.on.clipboard") {
                    model.runAction(id: "edit_paste")
                }
                .keyboardShortcut("v", modifiers: [.command])
                .help("Paste into the focused text field when possible")
            }
            CommandGroup(replacing: .textEditing) {
                Button("Select All") {
                    model.runAction(id: "edit_select_all")
                }
                .keyboardShortcut("a", modifiers: [.command])
                .help("Select all text in the focused field")
            }
            // Stock-ish Edit → Theme: configure global Ghidra Theme (also Settings / ⌘,).
            CommandGroup(after: .textEditing) {
                Menu("Theme") {
                    SettingsLink {
                        Label("Configure Theme…", systemImage: "paintpalette")
                    }
                    .help("Open Settings → Appearance (⌘,) to set the global Ghidra Theme")
                    Divider()
                    ForEach(
                        Array(ThemeStore.shared.availableThemes.prefix(16)),
                        id: \.name
                    ) { theme in
                        Button {
                            Task { @MainActor in
                                ThemeStore.shared.select(theme)
                            }
                        } label: {
                            if theme.name == ThemeStore.shared.ghidraThemeName {
                                Label(theme.name, systemImage: "checkmark")
                            } else {
                                Text(theme.name)
                            }
                        }
                    }
                }
            }

            // CodeBrowser.chrome.json: Analysis → BSim → Graph (then Navigation… in next block)
            if !isFrontEndMenus {
                CommandMenu("Analysis") {
                    Button("Auto Analyze…", systemImage: "wand.and.stars") {
                        model.runAction(id: "auto_analyze")
                    }
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
                    Button("Function Graph", systemImage: "point.3.connected.trianglepath.dotted") {
                        model.runAction(id: "show_function_graph")
                    }
                    .help("Open the Function Graph provider")
                }
            }
        }
        .commands {
            if !isFrontEndMenus {
                CommandMenu("Navigation") {
                    Button("Go To…", systemImage: "arrow.right.circle") {
                        model.runAction(id: "goto")
                    }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .help("Navigate to an address or label")
                    Button("Previous Location", systemImage: "chevron.left") {
                        model.runAction(id: "nav_back")
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [.option])
                    .help("Go to the previous navigation location")
                    Button("Next Location", systemImage: "chevron.right") {
                        model.runAction(id: "nav_fwd")
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [.option])
                    .help("Go to the next navigation location")
                }
                CommandMenu("Search") {
                    Button("For Strings…", systemImage: "textformat.abc") {
                        model.runAction(id: "search_strings")
                    }
                    .help("Search program strings")
                    Button("For Functions…", systemImage: "f.cursive") {
                        model.runAction(id: "search_functions")
                    }
                    .help("Search program functions")
                    Button("Memory…", systemImage: "magnifyingglass") {
                        model.runAction(id: "search_memory")
                    }
                    .help("Search program memory for a byte/ASCII pattern")
                }
                CommandMenu("Select") {
                    Button("Clear Selection", systemImage: "selection.pin.in.out") {
                        model.runAction(id: "clear_selection")
                    }
                    .help("Clear the current listing selection")
                }
            }

            // FrontEnd.chrome.json: Project before Tools (no File dupes — New/Open stay in File).
            if isFrontEndMenus {
                CommandMenu("Project") {
                    Button("Select Project / Workspace…", systemImage: "rectangle.3.group") {
                        model.runAction(id: "show_workspace")
                    }
                    .help("Choose a recent project or workspace")
                    Button("Project Window", systemImage: "building.columns") {
                        model.runAction(id: "show_project")
                    }
                    .help("Show the Front End / Project Window")
                }
            }

            CommandMenu("Tools") {
                Button("Restart Program Engine", systemImage: "bolt.horizontal.circle") {
                    model.runAction(id: "start_mcp")
                }
                .help("Restart the local Ghidra program engine (no Cursor MCP required)")
                Button("Engine Status", systemImage: "heart.text.square") {
                    model.runAction(id: "mcp_health")
                }
                .help("Check program engine status")
                if isFrontEndMenus {
                    Divider()
                    Button("CodeBrowser", systemImage: "flame.fill") {
                        model.runAction(id: "show_codebrowser")
                    }
                    .help("Open CodeBrowser for the current program")
                }
            }

            // System Window menu — icons on tool/sidebar rows; modules = Toggle (checkmark align).
            CommandGroup(before: .windowList) {
                Button("Project Window", systemImage: "building.columns") {
                    model.runAction(id: "show_project")
                }
                .help("Show the Front End / Project Window")
                Button("CodeBrowser", systemImage: "flame.fill") {
                    model.runAction(id: "show_codebrowser")
                }
                .help("Open CodeBrowser for the current program")
                Divider()
                Toggle(
                    "Modules",
                    systemImage: "sidebar.leading",
                    isOn: Binding(
                        get: { model.dockLayout.leftSidebarVisible },
                        set: { want in
                            if want != model.dockLayout.leftSidebarVisible {
                                model.toggleLeftSidebar()
                            }
                        }
                    )
                )
                .help("Toggle the leading Modules palette (Window providers)")
                Toggle(
                    "Agent",
                    systemImage: model.agentChromeSymbol,
                    isOn: Binding(
                        get: { model.agentChromeActive },
                        set: { model.setAgentChromeActive($0) }
                    )
                )
                .help(model.agentChromeHelp)
                Divider()
                WindowModuleToggles(model: model, kinds: ProviderKind.defaultDocked)
                Divider()
                WindowModuleToggles(model: model, kinds: ProviderKind.bottomStrip)
                Divider()
                WindowModuleToggles(model: model, kinds: Array(ProviderKind.windowMenuOrder))
            }

            // System Help — About lives under the app menu (HIG).
            CommandGroup(replacing: .help) {
                Button("GhidraVibe Help…", systemImage: "questionmark.circle") {
                    model.runAction(id: "show_help")
                }
                .help("Open Ghidra Help / Welcome")
                Button("Context Help", systemImage: "questionmark.diamond") {
                    model.runAction(id: "context_help")
                }
                .keyboardShortcut(
                    KeyEquivalent(Character(UnicodeScalar(UInt32(NSF1FunctionKey))!)),
                    modifiers: []
                )
                .help("Open Help for the focused provider (F1)")
                .a11yCatalog("ghidra.vibe.menu.help.context")
                Button("Tip of the Day…", systemImage: "lightbulb") {
                    model.runAction(id: "tip_of_the_day")
                }
                .help("Show Tip of the Day")
                Button("Headless Help", systemImage: "terminal") {
                    model.runAction(id: "headless_help")
                }
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
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(.suppressed)

        // Detached Agent chat — singular `Window` (not WindowGroup) so openWindow
        // cannot spawn hundreds of copies. Close / Cmd-W reattaches to sidebar.
        Window("Agent", id: FloatingAgentRouter.windowID) {
            FloatingAgentRoot()
                .environment(model)
                .vibeGlobalTheme()
        }
        .defaultSize(width: 560, height: 720)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .environment(model)
                .vibeGlobalTheme()
                .vibeUnifiedWindowChrome(restoreSize: NSSize(width: 520, height: 640))
        }
        .windowToolbarStyle(.unified)
    }
}
