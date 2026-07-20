import SwiftUI

/// Default CodeBrowser.tool spatial layout — modular dock regions (stock DockingWindowManager).
/// Navigation chrome uses Liquid Glass; listing/decompiler stay opaque content.
struct CodeBrowserDockView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var showHeaderStrip = false

    private static let chromeToolbar: [(String, String, String)] = [
        ("ghidra.vibe.toolbar.nav_back", "chevron.left", "Previous Location"),
        ("ghidra.vibe.toolbar.nav_fwd", "chevron.right", "Next Location"),
        ("ghidra.vibe.toolbar.save", "square.and.arrow.down", "Save Program"),
        ("ghidra.vibe.toolbar.undo", "arrow.uturn.backward", "Undo"),
        ("ghidra.vibe.toolbar.redo", "arrow.uturn.forward", "Redo"),
        ("ghidra.vibe.toolbar.goto", "arrow.right.circle", "Go To"),
        ("ghidra.vibe.toolbar.analyze", "wand.and.stars", "Auto Analyze"),
        ("ghidra.vibe.toolbar.mcp_health", "heart.text.square", "Engine Status"),
        ("ghidra.vibe.toolbar.start_mcp", "bolt.horizontal.circle", "Restart Engine"),
        ("ghidra.vibe.toolbar.dsc", "internaldrive", "Framework…"),
        ("ghidra.vibe.toolbar.apple", "apple.logo", "App Bundle…"),
    ]

    private static let listingMnemonics: [(String, String, String, String)] = [
        ("ghidra.vibe.toolbar.listing_i", "I", "Disassemble", "listing_disassemble"),
        ("ghidra.vibe.toolbar.listing_d", "D", "Define Data", "listing_define_data"),
        ("ghidra.vibe.toolbar.listing_u", "U", "Clear Code Bytes", "listing_clear_code"),
        ("ghidra.vibe.toolbar.listing_l", "L", "Create Label", "listing_create_label"),
        ("ghidra.vibe.toolbar.listing_f", "F", "Create Function", "listing_create_function"),
        ("ghidra.vibe.toolbar.listing_v", "V", "Create Structure / Array", "listing_create_structure"),
        ("ghidra.vibe.toolbar.listing_b", "B", "Add Bookmark", "listing_add_bookmark"),
    ]

    var body: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            codeBrowserToolbar
            Divider()
            if showHeaderStrip || model.dockLayout.hasVisibleHeader {
                headerInactiveStrip
                Divider()
            }
            DockWorkspaceView()
        }
        .onChange(of: model.sheetProvider) { _, kind in
            if kind == .entropy || kind == .overview {
                showHeaderStrip = true
            }
        }
        .onAppear {
            model.refreshProjectPrograms()
            model.refreshMemoryMap()
            model.refreshSymbolTable()
            model.refreshDataTypes()
            // Re-open any persisted floating providers.
            for kind in model.dockLayout.floatingSet {
                openWindow(id: "ghidra.vibe.floating.provider", value: kind.rawValue)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ghidraVibeFloatProvider)) { note in
            guard let raw = note.userInfo?["kind"] as? String else { return }
            openWindow(id: "ghidra.vibe.floating.provider", value: raw)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ghidraVibeUnfloatProvider)) { note in
            guard let raw = note.userInfo?["kind"] as? String else { return }
            dismissWindow(id: "ghidra.vibe.floating.provider", value: raw)
        }
    }

    private var codeBrowserToolbar: some View {
        LiquidGlass.Bar(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.chromeToolbar.prefix(5), id: \.0) { id, symbol, label in
                        GlassToolbarButton(id: id, systemImage: symbol, label: label) {
                            toolbarAction(id)
                        }
                    }
                    Divider().frame(height: 18)
                    ForEach(Self.listingMnemonics, id: \.0) { id, letter, label, action in
                        GlassMnemonicButton(
                            id: id,
                            letter: letter,
                            label: label,
                            enabled: true
                        ) {
                            model.runAction(id: action)
                        }
                    }
                    Divider().frame(height: 18)
                    ForEach(Self.chromeToolbar.dropFirst(5), id: \.0) { id, symbol, label in
                        GlassToolbarButton(id: id, systemImage: symbol, label: label) {
                            toolbarAction(id)
                        }
                    }
                    Menu {
                        Button("Fetch Functions") { model.fetchFunctionsViaMCP() }
                            .help("Reload function list from the program engine")
                        Button("Decompile") { model.decompileSelected() }
                            .help("Decompile the selected function")
                        Button("Classes") {
                            model.showProvider(.swiftClasses)
                            model.refreshObjcClassesFromFunctions()
                            model.refreshSwiftClasses()
                        }
                        .help("ObjC / Swift class browser (left dock)")
                        Button("Open Framework…") { model.presentFrameworkOpenSheet() }
                            .help("Open a framework from the dyld shared cache")
                        Divider()
                        Button(showHeaderStrip ? "Hide Entropy / Overview" : "Show Entropy / Overview") {
                            showHeaderStrip.toggle()
                            if showHeaderStrip {
                                model.showProvider(.entropy)
                                model.showProvider(.overview)
                            } else {
                                model.closeProvider(.entropy)
                                model.closeProvider(.overview)
                            }
                        }
                        .help("Toggle inactive header stack (Entropy / Overview)")
                        Button(model.bottomStripVisible ? "Hide Bottom Strip" : "Show Bottom Strip") {
                            model.bottomStripVisible.toggle()
                        }
                        .help("Toggle Data Type Preview / Disassembled View")
                        Button(model.consoleStackVisible ? "Hide Console" : "Show Console") {
                            if model.consoleStackVisible {
                                model.closeConsoleStack()
                            } else {
                                model.showProvider(.console)
                            }
                        }
                        .help("Toggle Console / Bookmarks stack")
                        Divider()
                        Button("Reset Dock Layout") { model.resetDockLayoutToStock() }
                            .help("Restore stock CodeBrowser dock regions")
                        Button("Project Window") { model.enterProjectWindow() }
                            .help("Return to Front End / Project Window")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.glass)
                    .help("More CodeBrowser tools")
                    .accessibilityIdentifier("ghidra.vibe.toolbar.more")
                    Spacer(minLength: 8)
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

    private func toolbarAction(_ id: String) {
        switch id {
        case "ghidra.vibe.toolbar.save": model.saveProgram()
        case "ghidra.vibe.toolbar.nav_back": model.navBack()
        case "ghidra.vibe.toolbar.nav_fwd": model.navForward()
        case "ghidra.vibe.toolbar.undo": model.undoAction()
        case "ghidra.vibe.toolbar.redo": model.redoAction()
        case "ghidra.vibe.toolbar.goto": model.promptGoTo()
        case "ghidra.vibe.toolbar.analyze": model.autoAnalyze()
        case "ghidra.vibe.toolbar.mcp_health": model.refreshMCPHealth()
        case "ghidra.vibe.toolbar.start_mcp": model.startMCPBridge()
        case "ghidra.vibe.toolbar.dsc":
            model.presentFrameworkOpenSheet()
        case "ghidra.vibe.toolbar.apple": model.openAppBundlePicker()
        default: break
        }
    }

    private var headerInactiveStrip: some View {
        LiquidGlass.Bar(spacing: 4) {
            HStack(spacing: 4) {
                ForEach([ProviderKind.entropy, .overview], id: \.id) { kind in
                    Button(kind.title) { model.showProvider(kind) }
                        .buttonStyle(.glass)
                        .font(.caption2)
                        .a11yCatalog("ghidra.vibe.codebrowser.header.\(kind.rawValue)")
                }
                Spacer(minLength: 0)
                Button {
                    showHeaderStrip = false
                    model.closeProvider(.entropy)
                    model.closeProvider(.overview)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Hide Entropy / Overview header")
                .font(.caption2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .vibeGlassBarBackground()
        }
        .frame(height: 36)
        .onDrop(of: [.json], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadDataRepresentation(for: .json) { data, _ in
                guard let data,
                      let drag = try? JSONDecoder().decode(ProviderDockDrag.self, from: data),
                      let kind = drag.kind
                else { return }
                Task { @MainActor in
                    model.moveProvider(kind, to: .header)
                }
            }
            return true
        }
    }
}
