import SwiftUI

/// Default CodeBrowser.tool spatial layout — modular dock regions (stock DockingWindowManager).
/// Primary tools live in the macOS Tahoe unified titlebar/toolbar (Liquid Glass); listing/decompiler stay opaque.
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
            if showHeaderStrip || model.dockLayout.hasVisibleHeader || model.dockDragKind != nil {
                headerInactiveStrip
                Divider()
            }
            DockWorkspaceView()
        }
        .toolbarRole(.editor)
        // Left controls · system window title (middle) · right listing/tools. Do not inject a
        // second title Text — ContentRootView `.navigationTitle` owns the macOS title.
        .toolbar {
            // Dense CodeBrowser chrome. On macOS 26, NSToolbar can clip items when the
            // window is narrow — there is no `.visibilityPriority` / `ToolbarOverflowMenu`
            // until the macOS 27 SDK. Keep glass groups, and mirror every stock action in
            // the trailing More… menu so nothing is unreachable at small sizes.
            // ToolbarContentBuilder max is 10 children (spacers count).

            // ── Modules: own glass grouping (not shared with window controls) ──
            // Tahoe merges adjacent `.navigation` items onto one plate unless the
            // item is forced into its own grouping via `sharedBackgroundVisibility`.
            // See Apple: ToolbarContent.sharedBackgroundVisibility(_:).
            ToolbarItem(id: "ghidra.vibe.toolbar.modules_sidebar", placement: .navigation) {
                Button {
                    model.toggleLeftSidebar()
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                // Own capsule: shared toolbar plate is hidden below so this
                // does not melt into the window-controls group.
                .buttonStyle(.bordered)
                        .tint(Color.vibeAccent)
                .a11yCatalog("ghidra.vibe.toolbar.modules_sidebar")
                .help(
                    model.dockLayout.leftSidebarVisible
                        ? "Hide Modules sidebar"
                        : "Show Modules sidebar"
                )
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.fixed, placement: .navigation)

            // ── Window controls (nav + edit share one plate) ──
            ToolbarItemGroup(placement: .navigation) {
                ForEach(Self.chromeToolbar.prefix(5), id: \.0) { id, symbol, label in
                    UnifiedToolbarButton(id: id, systemImage: symbol, label: label) {
                        toolbarAction(id)
                    }
                }
            }

            // ── RIGHT: I/D/U/L/F/V/B · tools · More · Agent ──
            ToolbarItemGroup(placement: .primaryAction) {
                ForEach(Self.listingMnemonics, id: \.0) { id, letter, label, _ in
                    UnifiedToolbarButton(
                        id: id,
                        systemImage: "\(letter.lowercased()).circle",
                        label: label,
                        helpTip: A11yCatalog.hoverTip(for: id, fallback: "\(letter) — \(label)")
                    ) {
                        toolbarAction(id)
                    }
                }
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItemGroup(placement: .primaryAction) {
                ForEach(Self.chromeToolbar.dropFirst(5), id: \.0) { id, symbol, label in
                    UnifiedToolbarButton(id: id, systemImage: symbol, label: label) {
                        toolbarAction(id)
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    overflowMenuContent
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .a11yCatalog("ghidra.vibe.toolbar.more")
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            // Agent: own glass grouping — not merged with More….
            ToolbarItem(id: "ghidra.vibe.toolbar.agent_sidebar", placement: .primaryAction) {
                Button {
                    model.toggleAgentSidebar()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .buttonStyle(.bordered)
                        .tint(Color.vibeAccent)
                .a11yCatalog("ghidra.vibe.toolbar.agent_sidebar")
                .help(
                    model.dockLayout.agentSidebarVisible && model.agentEnabled
                        ? "Hide Agent sidebar"
                        : "Show Agent sidebar"
                )
            }
            .sharedBackgroundVisibility(.hidden)
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
        case "ghidra.vibe.toolbar.listing_i": model.runAction(id: "listing_disassemble")
        case "ghidra.vibe.toolbar.listing_d": model.runAction(id: "listing_define_data")
        case "ghidra.vibe.toolbar.listing_u": model.runAction(id: "listing_clear_code")
        case "ghidra.vibe.toolbar.listing_l": model.runAction(id: "listing_create_label")
        case "ghidra.vibe.toolbar.listing_f": model.runAction(id: "listing_create_function")
        case "ghidra.vibe.toolbar.listing_v": model.runAction(id: "listing_create_structure")
        case "ghidra.vibe.toolbar.listing_b": model.runAction(id: "listing_add_bookmark")
        default: break
        }
    }

    /// Trailing More… — full stock toolbar mirror + secondary chrome (narrow-window safety net).
    @ViewBuilder
    private var overflowMenuContent: some View {
        Section("Navigate") {
            ForEach(Self.chromeToolbar.prefix(2), id: \.0) { id, _, label in
                Button(label) { toolbarAction(id) }
            }
        }
        Section("Edit") {
            ForEach(Self.chromeToolbar.dropFirst(2).prefix(3), id: \.0) { id, _, label in
                Button(label) { toolbarAction(id) }
            }
        }
        Section("Listing") {
            ForEach(Self.listingMnemonics, id: \.0) { _, letter, label, action in
                Button("\(letter) — \(label)") { model.runAction(id: action) }
            }
        }
        Section("Analysis") {
            ForEach(Self.chromeToolbar.dropFirst(5), id: \.0) { id, _, label in
                Button(label) { toolbarAction(id) }
            }
        }
        Divider()
        moreMenuContent
    }

    @ViewBuilder
    private var moreMenuContent: some View {
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
        Button(
            model.dockLayout.leftSidebarVisible
                ? "Hide Modules sidebar"
                : "Show Modules sidebar"
        ) {
            model.toggleLeftSidebar()
        }
        .help("Toggle the leading Modules palette")
        Button(
            model.dockLayout.agentSidebarVisible && model.agentEnabled
                ? "Hide Agent sidebar"
                : "Show Agent sidebar"
        ) {
            model.toggleAgentSidebar()
        }
        .help("Toggle the trailing Agent sidebar")
        Divider()
        Button("Reset Dock Layout") { model.resetDockLayoutToStock() }
            .help("Restore stock CodeBrowser dock regions")
        Button("Project Window") { model.enterProjectWindow() }
            .help("Return to Front End / Project Window")
    }

    private var headerInactiveStrip: some View {
        LiquidGlass.Bar(spacing: VibeChrome.Space.xs) {
            HStack(spacing: VibeChrome.Space.xs) {
                ForEach([ProviderKind.entropy, .overview], id: \.id) { kind in
                    Button(kind.title) { model.showProvider(kind) }
                        .buttonStyle(.bordered)
                        .tint(Color.vibeAccent)
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
            .padding(.horizontal, VibeChrome.Space.sm)
            .padding(.vertical, VibeChrome.Space.xxs)
            .vibeGlassBarBackground()
        }
        .frame(height: 36)
        .onDrop(of: [.json], isTargeted: Binding(
            get: { model.dockDropHighlight == .header },
            set: { hovering in
                if hovering {
                    model.setDockDropHighlight(.header)
                } else if model.dockDropHighlight == .header {
                    model.setDockDropHighlight(nil)
                }
            }
        )) { providers in
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
        .overlay {
            if model.dockDragKind != nil {
                DockRegionDropOverlay(
                    region: .header,
                    highlighted: model.dockDropHighlight == .header,
                    emptyPlaceholder: true,
                    movingTitle: model.dockDragKind?.title
                )
            }
        }
    }
}
