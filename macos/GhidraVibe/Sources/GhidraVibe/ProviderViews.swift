import SwiftUI

struct ProviderView: View {
    @Environment(AppModel.self) private var model
    let kind: ProviderKind

    var body: some View {
        Group {
            switch kind {
            case .listing: ListingProvider()
            case .decompiler: DecompilerProvider()
            case .programTree: ProgramTreeProvider()
            case .symbolTree: SymbolTreeProvider()
            case .dataTypes: DataTypesProvider()
            case .console: ConsoleProvider()
            case .functions: FunctionsProvider()
            case .strings: StringsProvider()
            case .memoryMap: MemoryMapProvider()
            case .symbolTable: SymbolTableProvider()
            case .bytes: BytesProvider()
            case .bookmarks: BookmarksProvider()
            case .scriptManager: ScriptManagerProvider()
            case .functionGraph: FunctionGraphProvider()
            case .mcp: MCPProvider()
            case .agent:
                // Agent is trailing-sidebar only — never a modular dock pane.
                ContentUnavailableView(
                    "Agent Sidebar",
                    systemImage: "sidebar.trailing",
                    description: Text("Use the trailing Agent sidebar from the toolbar.")
                )
            case .rag: RAGProvider()
            case .rules: RulesProvider()
            case .dsc: DSCProvider()
            case .appleBundle: MalimiteAnalysisView()
            case .swiftClasses: SwiftClassesProvider()
            case .codeEditor: CodeEditorProvider()
            case .versionTracking: VersionTrackingProvider()
            case .datatypePreview: DatatypePreviewProvider()
            case .disassembledView: DisassembledViewProvider()
            case .entropy: EntropyProvider()
            case .overview: OverviewProvider()
            case .definedData: DefinedDataProvider()
            case .equates: EquatesProvider()
            case .externalPrograms: ExternalProgramsProvider()
            case .relocations: RelocationsProvider()
            case .registers: RegistersProvider()
            case .symbolReferences: SymbolReferencesProvider()
            case .checksum: ChecksumProvider()
            case .functionTags: FunctionTagsProvider()
            case .comments: CommentsProvider()
            case .python: PythonProvider()
            }
        }
        .a11yContainerCatalog(kind.a11yRoot)
    }
}

/// Simple provider shell — stock dock chrome + optional inventory toolbar.
struct ProviderChrome<Content: View>: View {
    @Environment(AppModel.self) private var model
    let kind: ProviderKind
    var title: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        DockedProviderChrome(
            kind: kind,
            title: title ?? kind.title,
            closeA11yId: "ghidra.vibe.provider.\(kind.rawValue).close",
            onClose: { model.closeProvider(kind) }
        ) {
            InventoryProviderToolbar(kind: kind)
        } content: {
            content()
        }
    }
}

/// Stock-style provider header: draggable title, Dock-to menu, local toolbar, close.
/// Titlebar is square / stock (no concentric Liquid Glass radius on module chrome).
struct DockedProviderChrome<Toolbar: View, Content: View>: View {
    @Environment(AppModel.self) private var model
    let kind: ProviderKind
    let title: String
    var closeA11yId: String? = nil
    var onClose: (() -> Void)? = nil
    @ViewBuilder var toolbar: () -> Toolbar
    @ViewBuilder var content: () -> Content

    private var isDraggingThis: Bool { model.dockDragKind == kind }

    var body: some View {
        // Chrome must sit above content in z-order: NSViewRepresentable canvases
        // (Function Graph) otherwise composite over the title/toolbar buttons.
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: VibeChrome.Space.sm) {
                // Explicit move grip — square stock chrome, not concentric glass.
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isDraggingThis ? VibeChrome.ProviderSurface.accent : VibeChrome.ProviderSurface.secondary)
                    .frame(width: 16, height: 16)
                    .help("Drag to tile on Top / Left / Right / Bottom / Center")
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isDraggingThis ? VibeChrome.ProviderSurface.accent : VibeChrome.ProviderSurface.foreground)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .help("Drag to redock · Right-click for Dock to…")
                Spacer(minLength: 0)
                toolbar()
                if let onClose {
                    ProviderToolButton(
                        id: closeA11yId ?? "ghidra.vibe.provider.\(kind.rawValue).close",
                        systemImage: "xmark",
                        label: "Close"
                    ) { onClose() }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            // Title strip: content base + wash (controlBackground ≈ textBackground on Tahoe).
            .background {
                ZStack {
                    VibeChrome.ProviderSurface.titleBar
                    if isDraggingThis {
                        VibeChrome.ProviderSurface.titleBarActiveWash
                    } else {
                        VibeChrome.ProviderSurface.titleBarWash
                    }
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isDraggingThis ? VibeChrome.ProviderSurface.accent : VibeChrome.ProviderSurface.separator)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
            // AppKit onDrag — SwiftUI `.draggable` paints blue focus rings on every module.
            .onDrag { ProviderDockDrag(kindRaw: kind.rawValue).itemProvider() }
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in
                        if model.dockDragKind != kind {
                            model.beginProviderDockDrag(kind)
                        }
                    }
                    .onEnded { _ in
                        // Keep HUD up until drop / Cancel; clear highlight only.
                        model.setDockDropHighlight(nil)
                    }
            )
            .contextMenu {
                providerDockMenu
            }
            .a11yCatalog("ghidra.vibe.provider.\(kind.rawValue).chrome")
            .zIndex(2)

            content()
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .background(VibeChrome.ProviderSurface.content)
                .clipped()
                .zIndex(0)
        }
        // One content fill for the module — do not stack windowBackground under title+body.
        // No outline stroke: separator/accent borders read as “blue boxes” under Apple chrome.
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .background(VibeChrome.ProviderSurface.content)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private var providerDockMenu: some View {
        Menu("Dock to") {
            ForEach(DockRegion.dropTargets, id: \DockRegion.id) { (region: DockRegion) in
                Button(region.dropLabel) { model.moveProvider(kind, to: region) }
            }
        }
        Button("Float") { model.floatProvider(kind) }
        Button("Reattach") { model.reattachProvider(kind) }
        Divider()
        Button("Close") { (onClose ?? { model.closeProvider(kind) })() }
    }
}

struct InventoryProviderToolbar: View {
    @Environment(AppModel.self) private var model
    let kind: ProviderKind

    var body: some View {
        let specs = ProviderChromeCatalog.toolbar(for: kind)
        if specs.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 2) {
                ForEach(specs) { spec in
                    ProviderToolButton(
                        id: spec.id,
                        systemImage: spec.systemImage,
                        label: spec.label,
                        disabled: spec.isHonestDisabled
                            && !Self.wiredOverrides.contains(spec.id)
                    ) {
                        model.providerChromeAction(id: spec.id, kind: kind)
                    }
                }
            }
        }
    }

    /// Wired in AppModel even when chrome.json still says disabled_honest for some ids.
    private static let wiredOverrides: Set<String> = [
        "ghidra.vibe.provider.console.copy",
        "ghidra.vibe.provider.decompiler.export",
        "ghidra.vibe.provider.decompiler.refresh",
        "ghidra.vibe.provider.decompiler.options",
        "ghidra.vibe.provider.listing.goto_field",
        "ghidra.vibe.provider.listing.settings",
        "ghidra.vibe.provider.listing.marker",
        "ghidra.vibe.provider.symbol_tree.snapshot",
        "ghidra.vibe.provider.symbol_tree.filter_go",
        "ghidra.vibe.provider.symbol_tree.create_namespace",
        "ghidra.vibe.provider.symbol_tree.create_class",
        "ghidra.vibe.provider.symbol_tree.create_symbol",
        "ghidra.vibe.provider.program_tree.create_tree",
        "ghidra.vibe.provider.program_tree.create_folder",
        "ghidra.vibe.provider.program_tree.create_fragment",
        "ghidra.vibe.provider.data_types.open_archive",
        "ghidra.vibe.provider.data_types.filter_go",
        "ghidra.vibe.provider.data_types.back",
        "ghidra.vibe.provider.data_types.forward",
        "ghidra.vibe.provider.data_types.create",
        "ghidra.vibe.provider.data_types.settings",
        "ghidra.vibe.provider.console.lock",
        "ghidra.vibe.provider.console.clear",
        "ghidra.vibe.provider.console.input",
    ]
}

struct ProviderToolButton: View {
    let id: String
    let systemImage: String
    let label: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .frame(width: 20, height: 18)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .a11yCatalog(id)
        .help(
            disabled
                ? "\(A11yCatalog.hoverTip(for: id, fallback: label)) (not wired yet — engine is fine)"
                : A11yCatalog.hoverTip(for: id, fallback: label)
        )
    }
}

struct ListingProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        DockedProviderChrome(
            kind: .listing,
            title: model.currentProgramName.isEmpty ? "Listing" : "Listing: \(model.currentProgramName)",
            closeA11yId: "ghidra.vibe.provider.listing.close",
            onClose: { model.closeProvider(.listing) }
        ) {
            HStack(spacing: 2) {
                ProviderToolButton(
                    id: "ghidra.vibe.provider.listing.settings",
                    systemImage: "gearshape",
                    label: "Listing Settings"
                ) { model.providerChromeAction(id: "ghidra.vibe.provider.listing.settings", kind: .listing) }
                ProviderToolButton(
                    id: "ghidra.vibe.provider.listing.marker",
                    systemImage: "bookmark",
                    label: "Marker"
                ) { model.providerChromeAction(id: "ghidra.vibe.provider.listing.marker", kind: .listing) }
            }
        } content: {
            VStack(spacing: 0) {
                TextField("Go to address / label", text: $model.goToDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .padding(4)
                    .a11yCatalog("ghidra.vibe.provider.listing.goto_field")
                    .onSubmit { model.performGoTo() }
                // Bidirectional scroll: narrow panes hide columns; pan left/right to read them.
                ScrollView([.horizontal, .vertical]) {
                    Text(model.listingText.isEmpty ? "// Listing empty — select a function or Go To" : model.listingText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.vibeForeground)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                        // Intrinsic width so long disasm lines scroll instead of wrapping/clipping.
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(8)
                        .a11yCatalog("ghidra.vibe.provider.listing.text")
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .vibeDocumentPane()
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DecompilerProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        DockedProviderChrome(
            kind: .decompiler,
            title: "Decompile",
            closeA11yId: "ghidra.vibe.provider.decompiler.close",
            onClose: { model.closeProvider(.decompiler) }
        ) {
            HStack(spacing: 2) {
                ProviderToolButton(
                    id: "ghidra.vibe.provider.decompiler.refresh",
                    systemImage: "arrow.clockwise",
                    label: "Refresh"
                ) { model.decompileSelected() }
                ProviderToolButton(
                    id: "ghidra.vibe.provider.decompiler.options",
                    systemImage: "slider.horizontal.3",
                    label: "Decompiler Options"
                ) { model.providerChromeAction(id: "ghidra.vibe.provider.decompiler.options", kind: .decompiler) }
                ProviderToolButton(
                    id: "ghidra.vibe.provider.decompiler.export",
                    systemImage: "square.and.arrow.up",
                    label: "Export"
                ) {
                    model.agentDraft = model.decompiledText
                    model.statusMessage = "Decompile copied toward Agent / clipboard path"
                }
            }
        } content: {
            VStack(spacing: 0) {
                if let fn = model.selectedFunction {
                    Text("\(fn.name)\(fn.address.isEmpty ? "" : "  \(fn.address)")")
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.vibeSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.vibeContentAlt)
                        .contentShape(Rectangle())
                        .agentMentionDraggable(AgentMentionDrag.function(fn.name), title: fn.name)
                        .a11yCatalog("ghidra.vibe.provider.decompiler.fn_drag")
                } else if model.decompiledText.contains("Select a function") {
                    Text("No Function")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.vibeSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.vibeContentAlt)
                }
                SyntaxHighlightedCodeView(
                    text: model.decompiledText.isEmpty ? "// No Function" : model.decompiledText
                )
                .vibeDocumentPane()
                .a11yCatalog("ghidra.vibe.provider.decompiler.text")
            }
        }
    }
}

struct ProgramTreeProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        return DockedProviderChrome(
            kind: .programTree,
            title: "Program Trees",
            closeA11yId: "ghidra.vibe.provider.program_tree.close",
            onClose: { model.closeProvider(.programTree) }
        ) {
            HStack(spacing: 2) {
                ProviderToolButton(
                    id: "ghidra.vibe.provider.program_tree.create_tree",
                    systemImage: "doc.badge.plus",
                    label: "Create Tree"
                ) { model.statusMessage = "Create Program Tree" }
                ProviderToolButton(
                    id: "ghidra.vibe.provider.program_tree.create_folder",
                    systemImage: "folder.badge.plus",
                    label: "Create Folder"
                ) { model.statusMessage = "Create Folder" }
                ProviderToolButton(
                    id: "ghidra.vibe.provider.program_tree.create_fragment",
                    systemImage: "rectangle.stack.badge.plus",
                    label: "Create Fragment"
                ) { model.statusMessage = "Create Fragment" }
            }
        } content: {
            NativeOutlineTree(
                roots: programTreeRoots,
                selection: $model.selectedProgramTreeNodeId,
                a11yId: "ghidra.vibe.provider.program_tree.tree",
                emptyLabel: "No Program",
                agentDrag: OutlineAgentDragSource { node in
                    if node.id == "ghidra.vibe.provider.program_tree.root"
                        || node.id == "ghidra.vibe.provider.program_tree.bundle"
                    {
                        return .mention(.program)
                    }
                    guard !node.isFolder, let payload = node.payload else { return nil }
                    let url = URL(fileURLWithPath: payload)
                    if payload.hasPrefix("/"), FileManager.default.fileExists(atPath: url.path) {
                        return .file(url)
                    }
                    return .mention(.program)
                }
            ) { node in
                guard let payload = node.payload, !node.isFolder else {
                    model.statusMessage = node.title
                    return
                }
                if !model.bundleBinaryRows.isEmpty {
                    model.currentProgramName = URL(fileURLWithPath: payload).lastPathComponent
                    model.statusMessage = "Selected bundle binary \(model.currentProgramName)"
                    model.fetchFunctionsViaMCP()
                } else {
                    model.statusMessage = "Program tree: \(payload)"
                    model.goToDraft = payload
                }
            }
            .onAppear {
                model.refreshProjectPrograms()
                model.refreshMemoryMap()
                if model.bundleBinaryRows.isEmpty, !model.memoryMapRows.isEmpty {
                    model.programTreeNodes = model.memoryMapRows
                }
            }
        }
    }

    private var programTreeRoots: [OutlineTreeNode] {
        let fallback = model.programTreeNodes == ["(open a program)"] ? [] : model.programTreeNodes
        return OutlineTreeBuilder.programTree(
            programName: model.currentProgramName,
            segments: model.memoryMapRows,
            bundleRows: model.bundleBinaryRows,
            fallbackNodes: fallback
        )
    }
}

struct SymbolTreeProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        return DockedProviderChrome(
            kind: .symbolTree,
            title: "Symbol Tree",
            closeA11yId: "ghidra.vibe.provider.symbol_tree.close",
            onClose: { model.closeProvider(.symbolTree) }
        ) {
            HStack(spacing: 2) {
                ProviderToolButton(
                    id: "ghidra.vibe.provider.symbol_tree.create_namespace",
                    systemImage: "doc.badge.plus",
                    label: "Create Namespace"
                ) { model.statusMessage = "Create Namespace" }
                ProviderToolButton(
                    id: "ghidra.vibe.provider.symbol_tree.create_class",
                    systemImage: "doc.text.badge.plus",
                    label: "Create Class"
                ) { model.statusMessage = "Create Class" }
                ProviderToolButton(
                    id: "ghidra.vibe.provider.symbol_tree.create_symbol",
                    systemImage: "folder.badge.plus",
                    label: "Create Symbol"
                ) { model.statusMessage = "Create Symbol" }
                ProviderToolButton(
                    id: "ghidra.vibe.provider.symbol_tree.snapshot",
                    systemImage: "camera",
                    label: "Capture Symbol Tree"
                ) { model.refreshSymbolTable() }
            }
        } content: {
            VStack(spacing: 0) {
                NativeOutlineTree(
                    roots: symbolTreeRoots,
                    selection: $model.selectedSymbolTreeNodeId,
                    a11yId: "ghidra.vibe.provider.symbol_tree.tree",
                    emptyLabel: "No symbols",
                    agentDrag: OutlineAgentDragSource { node in
                        guard !node.isFolder, let payload = node.payload else { return nil }
                        let name: String
                        if payload.contains("\t") {
                            let parts = payload.split(separator: "\t", maxSplits: 1).map(String.init)
                            name = parts.count == 2 ? parts[1] : payload
                        } else {
                            name = payload
                        }
                        return .mention(.function(name))
                    }
                ) { node in
                    guard let payload = node.payload, !node.isFolder else {
                        model.statusMessage = node.title
                        return
                    }
                    if payload.contains("\t") {
                        let parts = payload.split(separator: "\t", maxSplits: 1).map(String.init)
                        model.selectFunction(
                            name: parts.count == 2 ? parts[1] : payload,
                            address: parts.first,
                            id: nil
                        )
                    } else {
                        model.selectFunction(name: payload, address: nil, id: nil)
                        if model.selectedFunction == nil {
                            model.statusMessage = "Symbol: \(payload)"
                        }
                    }
                }
                HStack(spacing: 6) {
                    Text("Filter:")
                        .font(.caption2)
                        .foregroundStyle(Color.vibeSecondary)
                    TextField("Filter", text: $model.symbolSearch)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .a11yCatalog("ghidra.vibe.provider.symbol_tree.search")
                    ProviderToolButton(
                        id: "ghidra.vibe.provider.symbol_tree.filter_go",
                        systemImage: "doc.text.magnifyingglass",
                        label: "Apply Filter"
                    ) { model.refreshSymbolTable() }
                }
                .padding(4)
            }
            .onAppear { model.refreshSymbolTable() }
        }
    }

    private var symbolTreeRoots: [OutlineTreeNode] {
        OutlineTreeBuilder.symbolTree(
            functions: model.functions.map { ($0.name, $0.address) },
            tableRows: model.symbolTableRows,
            namespaces: model.symbolNodes,
            filter: model.symbolSearch
        )
    }
}

struct DataTypesProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        return DockedProviderChrome(
            kind: .dataTypes,
            title: "Data Type Manager",
            closeA11yId: "ghidra.vibe.provider.data_types.close",
            onClose: { model.closeProvider(.dataTypes) }
        ) {
            HStack(spacing: 2) {
                ProviderToolButton(
                    id: "ghidra.vibe.provider.data_types.back",
                    systemImage: "chevron.left",
                    label: "Previous Data Type"
                ) { model.statusMessage = "Previous data type" }
                ProviderToolButton(
                    id: "ghidra.vibe.provider.data_types.forward",
                    systemImage: "chevron.right",
                    label: "Next Data Type"
                ) { model.statusMessage = "Next data type" }
                ProviderToolButton(
                    id: "ghidra.vibe.provider.data_types.create",
                    systemImage: "plus.square.on.square",
                    label: "Create Data Type"
                ) { model.statusMessage = "Create data type" }
                ProviderToolButton(
                    id: "ghidra.vibe.provider.data_types.open_archive",
                    systemImage: "books.vertical",
                    label: "Open Archive"
                ) { model.refreshDataTypes() }
                ProviderToolButton(
                    id: "ghidra.vibe.provider.data_types.settings",
                    systemImage: "gearshape",
                    label: "Data Type Manager Settings"
                ) { model.statusMessage = "Data Type Manager settings" }
            }
        } content: {
            VStack(spacing: 0) {
                NativeOutlineTree(
                    roots: OutlineTreeBuilder.dataTypes(
                        nodes: model.dataTypeNodes,
                        filter: model.dataTypeSearch
                    ),
                    selection: $model.selectedDataTypeNodeId,
                    a11yId: "ghidra.vibe.provider.data_types.tree",
                    emptyLabel: "No data types"
                ) { node in
                    guard let payload = node.payload, !node.isFolder else {
                        model.statusMessage = node.title
                        return
                    }
                    model.statusMessage = "Data type: \(node.title)"
                    model.consoleAppend("Data Type Manager select: \(payload)")
                    model.refreshDatatypePreview()
                }
                HStack(spacing: 6) {
                    Text("Filter:")
                        .font(.caption2)
                        .foregroundStyle(Color.vibeSecondary)
                    TextField("Filter", text: $model.dataTypeSearch)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .a11yCatalog("ghidra.vibe.provider.data_types.search")
                    ProviderToolButton(
                        id: "ghidra.vibe.provider.data_types.filter_go",
                        systemImage: "doc.text.magnifyingglass",
                        label: "Apply Filter"
                    ) { model.refreshDataTypes() }
                }
                .padding(4)
            }
            .onAppear { model.refreshDataTypes() }
        }
    }
}

struct ConsoleProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        DockedProviderChrome(
            kind: .console,
            title: "Console - Scripting",
            closeA11yId: "ghidra.vibe.provider.console.close",
            onClose: { model.closeProvider(.console) }
        ) {
            HStack(spacing: 2) {
                ProviderToolButton(
                    id: "ghidra.vibe.provider.console.lock",
                    systemImage: model.consoleScrollLocked ? "lock.fill" : "lock.open",
                    label: "Scroll Lock"
                ) {
                    model.consoleScrollLocked.toggle()
                    model.statusMessage = model.consoleScrollLocked ? "Console scroll locked" : "Console scroll unlocked"
                }
                ProviderToolButton(
                    id: "ghidra.vibe.provider.console.copy",
                    systemImage: "doc.on.doc",
                    label: "Copy Console"
                ) { model.copyConsoleToClipboard() }
                ProviderToolButton(
                    id: "ghidra.vibe.provider.console.clear",
                    systemImage: "trash",
                    label: "Clear Console"
                ) { model.clearConsole() }
            }
        } content: {
            VStack(spacing: 0) {
                ScrollView {
                    Text(model.consoleText.isEmpty ? "// Console" : model.consoleText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.vibeForeground)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .a11yCatalog("ghidra.vibe.provider.console.text")
                }
                .vibeDocumentPane()
                HStack {
                    TextField("Script / command (!script to run)", text: $model.consoleInputDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                        .a11yCatalog("ghidra.vibe.provider.console.input")
                        .onSubmit { model.submitConsoleInput() }
                    Button("Run") { model.submitConsoleInput() }
                        .buttonStyle(.bordered)
                        .help("Submit console input")
                }
                .padding(4)
            }
        }
    }
}

struct FunctionsProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ProviderChrome(kind: .functions) {
            VStack(spacing: 0) {
                TextField("Filter", text: $model.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .padding(4)
                List(model.functions.filter {
                    model.searchQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(model.searchQuery)
                }, id: \.id, selection: $model.selectedFunction) { fn in
                    Text("\(fn.name)  \(fn.address)")
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .agentMentionDraggable(AgentMentionDrag.function(fn.name), title: fn.name)
                        .help("Drag onto Agent to insert @Functions:\(fn.name)")
                }
                .a11yCatalog("ghidra.vibe.provider.functions.list")
            }
            .onAppear { model.fetchFunctionsViaMCP() }
            .onChange(of: model.selectedFunction) { _, _ in
                model.decompileSelected()
                model.fetchListing()
                model.refreshBytes()
            }
        }
    }
}

struct StringsProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ProviderChrome(kind: .strings) {
            List(model.stringRows, id: \.self) { Text($0).font(.caption.monospaced()) }
                .a11yCatalog("ghidra.vibe.provider.strings.body")
                .vibeThemedList()
                .onAppear { model.probeStrings() }
        }
    }
}

struct MemoryMapProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ProviderChrome(kind: .memoryMap) {
            List(model.memoryMapRows, id: \.self) { Text($0).font(.caption.monospaced()) }
                .a11yCatalog("ghidra.vibe.provider.memory_map.body")
                .vibeThemedList()
                .onAppear { model.refreshMemoryMap() }
        }
    }
}

struct SymbolTableProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ProviderChrome(kind: .symbolTable) {
            List(model.symbolTableRows, id: \.self) { Text($0).font(.caption.monospaced()) }
                .a11yCatalog("ghidra.vibe.provider.symbol_table.body")
                .vibeThemedList()
                .onAppear { model.refreshSymbolTable() }
        }
    }
}

struct BytesProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ProviderChrome(kind: .bytes) {
            ScrollView {
                Text(model.bytesText.isEmpty ? "// Select address for bytes" : model.bytesText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.vibeForeground)
                    .padding(8)
                    .a11yCatalog("ghidra.vibe.provider.bytes.body")
            }
            .vibeDocumentPane()
            .onAppear { model.refreshBytes() }
        }
    }
}

struct BookmarksProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ProviderChrome(kind: .bookmarks) {
            List(model.bookmarkRows, id: \.self) { Text($0) }
                .a11yCatalog("ghidra.vibe.provider.bookmarks.body")
                .vibeThemedList()
                .onAppear { model.refreshBookmarks() }
        }
    }
}

struct ScriptManagerProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ProviderChrome(kind: .scriptManager) {
            VStack(alignment: .leading) {
                Button("Refresh scripts") { model.refreshScripts() }
                    .buttonStyle(.bordered)
                    .padding(4)
                    .a11yCatalog("ghidra.vibe.provider.script_manager.refresh")
                List(model.scriptRows, id: \.self) { row in
                    Button(row) { model.runSelectedScript(row) }
                        .buttonStyle(.plain)
                        .font(.caption.monospaced())
                        .a11yCatalog("ghidra.vibe.provider.script_manager.run")
                .vibeThemedList()
                        .help("Run script \(row)")
                }
                .a11yCatalog("ghidra.vibe.provider.script_manager.body")
            }
            .onAppear { model.refreshScripts() }
        }
    }
}

struct FunctionGraphProvider: View {
    @Environment(AppModel.self) private var model
    @State private var showJSON = false

    var body: some View {
        ProviderChrome(kind: .functionGraph) {
            // ZStack keeps the AppKit canvas *under* the toolbar. NSViewRepresentable
            // otherwise composites above sibling SwiftUI chrome (nodes over buttons).
            ZStack(alignment: .top) {
                Group {
                    if showJSON || model.functionGraphModel.isEmpty {
                        ScrollView {
                            Text(model.functionGraphText.isEmpty
                                ? "// Select a function, then Refresh Graph"
                                : model.functionGraphText)
                                .font(.caption.monospaced())
                                .foregroundStyle(Color.vibeForeground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(.top, 36)
                                .padding(8)
                        }
                        .vibeDocumentPane()
                    } else {
                        FunctionGraphCanvas(
                            model: model.functionGraphModel,
                            selectedId: model.selectedGraphNodeId,
                            onSelectAddress: { model.selectGraphNode(address: $0) }
                        )
                        .padding(.top, 32)
                        .clipped()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.vibeContent)
                .a11yCatalog("ghidra.vibe.provider.function_graph.body")

                HStack(spacing: 8) {
                    Button("Refresh Graph") { model.refreshFunctionGraph() }
                        .buttonStyle(.bordered)
                        .a11yCatalog("ghidra.vibe.provider.function_graph.refresh")
                    if !model.functionGraphModel.isEmpty {
                        Text("\(model.functionGraphModel.function) · \(model.functionGraphModel.nodes.count) blocks · \(model.functionGraphModel.edges.count) edges")
                            .font(.caption)
                            .foregroundStyle(Color.vibeSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Toggle("JSON", isOn: $showJSON)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .help("Show raw CFG JSON instead of the canvas")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color.vibeControl)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.vibeSeparator).frame(height: 1)
                }
                .zIndex(10)
            }
            .onAppear { model.refreshFunctionGraph() }
            .onChange(of: model.selectedFunction?.id) { _, _ in
                model.refreshFunctionGraph()
            }
        }
    }
}

struct EntropyProvider: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ProviderChrome(kind: .entropy) {
            List(model.entropyRows, id: \.self) { Text($0).font(.caption.monospaced()) }
                .a11yCatalog("ghidra.vibe.provider.entropy.body")
                .vibeThemedList()
                .onAppear { model.refreshEntropy(); model.ensureVibeMCP() }
        }
    }
}

struct OverviewProvider: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ProviderChrome(kind: .overview) {
            ScrollView {
                Text(model.overviewText.isEmpty ? model.entropyRows.joined(separator: "\n") : model.overviewText)
                    .font(.caption.monospaced())
                    .padding(8)
                    .a11yCatalog("ghidra.vibe.provider.overview.body")
            }
            .onAppear { model.refreshEntropy() }
        }
    }
}

struct DefinedDataProvider: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ProviderChrome(kind: .definedData) {
            List(model.definedDataRows, id: \.self) { Text($0).font(.caption.monospaced()) }
                .a11yCatalog("ghidra.vibe.provider.defined_data.body")
                .vibeThemedList()
                .onAppear { model.refreshDefinedData() }
        }
    }
}

struct EquatesProvider: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ProviderChrome(kind: .equates) {
            List(model.equateRows, id: \.self) { Text($0).font(.caption.monospaced()) }
                .a11yCatalog("ghidra.vibe.provider.equates.body")
                .vibeThemedList()
                .onAppear { model.refreshEquates() }
        }
    }
}

struct ExternalProgramsProvider: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ProviderChrome(kind: .externalPrograms) {
            List(model.externalProgramRows, id: \.self) { Text($0).font(.caption.monospaced()) }
                .a11yCatalog("ghidra.vibe.provider.external_programs.body")
                .vibeThemedList()
                .onAppear { model.refreshExternals() }
        }
    }
}

struct RelocationsProvider: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ProviderChrome(kind: .relocations) {
            List(model.relocationRows, id: \.self) { Text($0).font(.caption.monospaced()) }
                .a11yCatalog("ghidra.vibe.provider.relocations.body")
                .vibeThemedList()
                .onAppear { model.refreshRelocations() }
        }
    }
}

struct RegistersProvider: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ProviderChrome(kind: .registers) {
            VStack(alignment: .leading) {
                Text(model.debuggerStatus).font(.caption2).foregroundStyle(Color.vibeSecondary).padding(4)
                List(model.registerRows, id: \.self) { Text($0).font(.caption.monospaced()) }
                    .a11yCatalog("ghidra.vibe.provider.registers.body")
                .vibeThemedList()
            }
            .onAppear {
                model.refreshRegisters()
                model.refreshDebuggerStatus()
            }
        }
    }
}

struct SymbolReferencesProvider: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ProviderChrome(kind: .symbolReferences) {
            List(model.symbolRefRows, id: \.self) { Text($0).font(.caption.monospaced()) }
                .a11yCatalog("ghidra.vibe.provider.symbol_references.body")
                .vibeThemedList()
                .onAppear { model.refreshSymbolReferences() }
        }
    }
}

struct ChecksumProvider: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ProviderChrome(kind: .checksum) {
            ScrollView {
                Text(model.checksumText.isEmpty ? "(select function)" : model.checksumText)
                    .font(.caption.monospaced())
                    .padding(8)
                    .a11yCatalog("ghidra.vibe.provider.checksum.body")
            }
            .onAppear { model.refreshChecksum() }
        }
    }
}

struct FunctionTagsProvider: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ProviderChrome(kind: .functionTags) {
            List(model.functionTagRows, id: \.self) { Text($0).font(.caption.monospaced()) }
                .a11yCatalog("ghidra.vibe.provider.function_tags.body")
                .vibeThemedList()
                .onAppear { model.refreshFunctionTags() }
        }
    }
}

struct CommentsProvider: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ProviderChrome(kind: .comments) {
            List(model.commentRows, id: \.self) { Text($0) }
                .a11yCatalog("ghidra.vibe.provider.comments.body")
                .vibeThemedList()
                .onAppear { model.refreshComments() }
        }
    }
}

struct DatatypePreviewProvider: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ProviderChrome(kind: .datatypePreview) {
            ScrollView {
                Text(model.datatypePreviewText.isEmpty ? "(preview)" : model.datatypePreviewText)
                    .font(.caption.monospaced())
                    .padding(8)
                    .a11yCatalog("ghidra.vibe.provider.datatype_preview.body")
            }
            .onAppear { model.refreshDatatypePreview() }
        }
    }
}

struct DisassembledViewProvider: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ProviderChrome(kind: .disassembledView) {
            ScrollView {
                Text(model.disassembledViewText.isEmpty ? "// disasm" : model.disassembledViewText)
                    .font(.caption.monospaced())
                    .padding(8)
                    .a11yCatalog("ghidra.vibe.provider.disassembled_view.body")
            }
            .onAppear { model.refreshDisassembledView() }
        }
    }
}

struct PythonProvider: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        ProviderChrome(kind: .python) {
            VStack(alignment: .leading) {
                TextEditor(text: $model.pythonScriptDraft)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .vibeThemedEditor()
                Button("Run via MCP scripts") { model.runPythonScript() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.vibeAccent)
                    .a11yCatalog("ghidra.vibe.provider.python.run")
                ScrollView {
                    Text(model.pythonScriptOutput)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.vibeForeground)
                }
                .vibeDocumentPane()
            }
            .padding(8)
            .a11yCatalog("ghidra.vibe.provider.python.body")
        }
    }
}

struct MCPProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ProviderChrome(kind: .mcp) {
            Form {
                TextField("Program engine URL", text: $model.mcpServerURL)
                    .a11yCatalog("ghidra.vibe.provider.mcp.url")
                TextField("Vibe helpers URL", text: $model.vibeMcpURL)
                    .a11yCatalog("ghidra.vibe.provider.mcp.vibe_url")
                TextField("Debugger URL", text: $model.debuggerURL)
                Text("Optional diagnostics. Daily RE uses the in-process engine; Cursor bridges need GHIDRA_VIBE_CURSOR_BRIDGE=1.")
                    .font(.caption2)
                    .foregroundStyle(Color.vibeSecondary)
                HStack {
                    Button("Engine status") { model.refreshMCPHealth(); model.ensureVibeMCP() }
                        .a11yCatalog("ghidra.vibe.provider.mcp.health")
                    Button("Restart engine") { model.ensureProgramEngineRunning() }
                        .a11yCatalog("ghidra.vibe.provider.mcp.start")
                }
                Text(model.mcpStatus).font(.caption)
                Text(model.vcStatus).font(.caption2)
                Text(model.debuggerStatus).font(.caption2)
            }
            .padding(8)
            .onAppear { model.refreshDebuggerStatus(); model.refreshVCStatus() }
        }
    }
}

struct RAGProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ProviderChrome(kind: .rag) {
            VStack(alignment: .leading) {
                Text(model.jspaceStatus).font(.caption)
                    .a11yCatalog("ghidra.vibe.provider.rag.body")
                TextField("Discover query", text: $model.ragQuery)
                    .a11yCatalog("ghidra.vibe.provider.rag.query")
                HStack {
                    Button("Discover") { model.runRAGDiscover() }
                        .a11yCatalog("ghidra.vibe.provider.rag.discover")
                    Button("Index") { model.indexJSpace() }
                        .a11yCatalog("ghidra.vibe.provider.rag.index")
                }
                ScrollView {
                    Text(model.ragResult).font(.caption.monospaced())
                }
            }
            .padding(8)
            .onAppear { model.ensureVibeMCP() }
        }
    }
}

struct RulesProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ProviderChrome(kind: .rules) {
            VStack {
                TextEditor(text: $model.rulesText)
                    .font(.system(.body, design: .monospaced))
                    .vibeThemedEditor()
                    .a11yCatalog("ghidra.vibe.provider.rules.editor")
                Button("Save rules") { model.saveRules() }
                    .a11yCatalog("ghidra.vibe.provider.rules.save")
            }
            .padding(8)
            .background(Color.vibeContent)
            .onAppear { model.loadRules() }
        }
    }
}

struct DSCProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ProviderChrome(kind: .dsc) {
            // Same control order as stock DSC index; HIG margins/gaps only.
            VStack(alignment: .leading, spacing: VibeChrome.Space.related) {
                Text("Shared Cache index — prefer File → Open Framework… for the simple open path.")
                    .font(.caption2)
                    .foregroundStyle(Color.vibeSecondary)
                Button("Open Framework…") { model.presentFrameworkOpenSheet() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.vibeAccent)
                    .a11yCatalog("ghidra.vibe.provider.dsc.open_framework")
                Text(model.dyldCachePath ?? "(no cache discovered)")
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .a11yCatalog("ghidra.vibe.provider.dsc.cache_path")
                Text("Project: \(model.dscImportTarget().gpr)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(Color.vibeSecondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .a11yCatalog("ghidra.vibe.provider.dsc.project_path")

                TextField("Filter (AppKit, SwiftUI, SkyLight…)", text: $model.dyldQuery)
                    .a11yCatalog("ghidra.vibe.provider.dsc.image_search")
                    .onSubmit { model.refreshDyldImagesAsync(query: model.dyldQuery) }
                    .onChange(of: model.dyldQuery) { _, newValue in
                        model.scheduleDyldFilter(newValue)
                    }

                HStack(spacing: VibeChrome.Space.related) {
                    Button("Rescan") { model.openDyldCache() }
                        .buttonStyle(.bordered)
                        .a11yCatalog("ghidra.vibe.provider.dsc.refresh")
                        .disabled(model.dyldListingBusy || model.dyldImportBusy)
                    Button("Open selected") {
                        if let img = model.selectedDyldImage {
                            model.importDyldImage(img)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.vibeAccent)
                    .a11yCatalog("ghidra.vibe.provider.dsc.import")
                    .disabled(model.selectedDyldImage == nil || model.dyldImportBusy)
                    Toggle("Auto Analyze", isOn: $model.dyldRunAnalysisOnImport)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .help("Off = open module first. On = full analysis (slower).")
                        .a11yCatalog("ghidra.vibe.provider.dsc.analyze_toggle")
                }

                if model.dyldImportBusy || model.dyldListingBusy {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: VibeChrome.Space.related) {
                            ProgressView().controlSize(.small)
                            Text(model.dyldImportBusy
                                ? "DSC Import — see Console for live log"
                                : "Scanning Shared Cache…")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.vibeSecondary)
                        }
                        if model.dyldImportBusy {
                            Text(model.statusMessage)
                                .font(.caption2)
                                .foregroundStyle(Color.vibeMuted)
                                .lineLimit(3)
                        }
                    }
                }

                Text("\(model.dyldImages.count) images — double-click to open")
                    .font(.caption2)
                    .foregroundStyle(Color.vibeSecondary)
                    .padding(.top, VibeChrome.Space.xs)
                    // Breathing room above the scrolling list (was flush under Auto Analyze).
                    .padding(.bottom, VibeChrome.Space.listInset)

                List(model.dyldImages, id: \.self, selection: $model.selectedDyldImage) { img in
                    Text(img)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .help(img)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            model.selectedDyldImage = img
                            model.importDyldImage(img)
                        }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .a11yCatalog("ghidra.vibe.provider.dsc.image_list")
            }
            .padding(VibeChrome.Space.margin)
            .onAppear {
                model.ensureVibeMCP()
                if model.dyldCachePath == nil || model.dyldImages.isEmpty {
                    model.openDyldCache()
                }
            }
        }
    }
}

struct SwiftClassesProvider: View {
    @Environment(AppModel.self) private var model
    @State private var tab: ClassTab = .objc

    private enum ClassTab: String, CaseIterable, Identifiable {
        case objc = "ObjC"
        case swift = "Swift"
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var model = model
        ProviderChrome(kind: .swiftClasses) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("", selection: $tab) {
                        ForEach(ClassTab.allCases) { t in Text(t.rawValue).tag(t) }
                    }
                    .pickerStyle(.segmented)
                    .a11yCatalog("ghidra.vibe.provider.swift_classes.tabs")
                    Spacer(minLength: 0)
                    Button("Refresh") {
                        model.refreshObjcClassesFromFunctions()
                        model.refreshSwiftClasses()
                        model.refreshMalimiteClasses()
                    }
                    .buttonStyle(.bordered)
                    .a11yCatalog("ghidra.vibe.provider.swift_classes.refresh")
                    Button("App Bundle…") { model.showProvider(.appleBundle) }
                        .help("Open App Bundle analysis (resources, refs, translate)")
                        .a11yCatalog("ghidra.vibe.provider.swift_classes.dump")
                }
                .padding(4)
                let rows: [String] = {
                    switch tab {
                    case .objc:
                        return model.objcClassRows.isEmpty
                            ? ["(no ObjC classes yet — open a program / Auto Analyze)"]
                            : model.objcClassRows
                    case .swift:
                        let swift = model.malimiteClassRows.isEmpty
                            ? model.swiftClassRows
                            : model.malimiteClassRows
                        return swift.isEmpty
                            ? ["(no Swift classes yet — open a program or App Bundle)"]
                            : swift
                    }
                }()
                List(rows, id: \.self) { row in
                    Button(row) {
                        if row.hasPrefix("(") { return }
                        // Prefer matching a function for ObjC method selectors / class names.
                        if let fn = model.functions.first(where: {
                            $0.name.contains(row) || row.contains($0.name)
                        }) {
                            model.selectFunction(name: fn.name, address: fn.address, id: fn.id)
                            model.decompileSelected()
                            model.refreshFunctionGraph()
                        } else {
                            model.goToDraft = row
                            model.performGoTo()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption.monospaced())
                    .a11yCatalog("ghidra.vibe.provider.swift_classes.go")
                    .help(row.hasPrefix("(")
                          ? row
                          : "Click to go · drag onto Agent for @Classes:\(row)")
                    .agentMentionDraggable(
                        row.hasPrefix("(") ? nil : AgentMentionDrag.className(row),
                        title: row
                    )
                }
                .a11yCatalog("ghidra.vibe.provider.swift_classes.list")
            }
            .onAppear {
                model.refreshObjcClassesFromFunctions()
                model.refreshSwiftClasses()
                model.refreshMalimiteClasses()
            }
        }
    }
}

struct CodeEditorProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ProviderChrome(kind: .codeEditor) {
            VStack(spacing: 0) {
                HStack {
                    Button("Load decompile") {
                        model.codeEditorText = model.decompiledText
                    }
                    .a11yCatalog("ghidra.vibe.provider.code_editor.load")
                    Button("Send to Agent") {
                        model.agentDraft = model.codeEditorText
                        model.showProvider(.agent)
                    }
                    .a11yCatalog("ghidra.vibe.provider.code_editor.to_agent")
                    Spacer()
                }
                .padding(4)
                SyntaxCodeEditor(text: $model.codeEditorText)
                    .a11yCatalog("ghidra.vibe.provider.code_editor.body")
            }
        }
    }
}

/// Stock Version Tracking tool (Tool Chest footprints) — session wizard shell.
struct VersionTrackingProvider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ProviderChrome(kind: .versionTracking) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "shoeprints.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version Tracking")
                            .font(.headline)
                        Text("Match markup between a source and destination program (stock VT tool).")
                            .font(.caption)
                            .foregroundStyle(Color.vibeSecondary)
                    }
                }
                .padding(.top, 8)

                Text("Create a session by choosing two programs from the Active Project, or drag programs onto this tool in stock Ghidra. Here: pick source/destination names then start.")
                    .font(.caption)
                    .foregroundStyle(Color.vibeSecondary)

                HStack {
                    Button("Create Session…") {
                        model.runVT(op: "create")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.vibeAccent)
                    .a11yCatalog("ghidra.vibe.provider.version_tracking.create")
                    Button("Open CodeBrowser") { model.openCodeBrowser() }
                        .buttonStyle(.bordered)
                        .a11yCatalog("ghidra.vibe.provider.version_tracking.open_codebrowser")
                }

                if !model.projectPrograms.isEmpty {
                    Text("Programs in project:")
                        .font(.caption.weight(.semibold))
                    List(model.projectPrograms, id: \.self) { name in
                        Text(name).font(.caption.monospaced())
                    }
                    .frame(minHeight: 80)
                } else {
                    Text("(no programs — import or open a project first)")
                        .font(.caption)
                        .foregroundStyle(Color.vibeSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .a11yCatalog("ghidra.vibe.provider.version_tracking.body")
            .onAppear { model.refreshProjectPrograms() }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.vibeTheme) private var themes

    var body: some View {
        @Bindable var model = model
        let t = themes.theme
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Ghidra Theme")
                                .font(.headline)
                            Spacer()
                            Text(themes.ghidraThemeName)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(t.vibeAccent)
                                .a11yCatalog("ghidra.vibe.settings.theme.active")
                        }
                        Text(
                            "Default Light / Default Dark use stock macOS window, control, "
                                + "and button accent colors. Custom Base16 themes keep their palette."
                        )
                        .font(.caption)
                        .foregroundStyle(Color.vibeSecondary)
                        Toggle(
                            "Match System Appearance",
                            isOn: Binding(
                                get: { themes.followSystemAppearance },
                                set: { themes.setFollowSystemAppearance($0) }
                            )
                        )
                        .a11yCatalog("ghidra.vibe.settings.theme.follow_system")
                        Base16ThemePicker()
                    }
                } header: {
                    Text("Appearance")
                }
                TextField("MCP URL", text: $model.mcpServerURL)
                TextField("Vibe MCP URL", text: $model.vibeMcpURL)
                Section("Agent") {
                    Toggle("Show Agent", isOn: $model.agentEnabled)
                    Picker("Provider", selection: $model.agentProvider) {
                        ForEach(AgentProviderKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .onChange(of: model.agentProvider) { _, new in
                        model.applyAgentProviderDefaults(new)
                        model.persistAgentAISettings()
                    }
                    TextField("Base URL", text: $model.agentBaseURL)
                        .onSubmit { model.persistAgentAISettings() }
                    TextField("Model", text: $model.agentModel)
                        .onSubmit { model.persistAgentAISettings() }
                    if !model.agentModelPicker.isEmpty {
                        Picker("Models", selection: $model.agentModel) {
                            ForEach(model.agentModelPicker, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .onChange(of: model.agentModel) { _, _ in
                            model.persistAgentAISettings()
                        }
                    }
                    HStack {
                        Button("Refresh models") { model.refreshAgentModels() }
                        Button("Agent Setup…") { model.showAgentSetup = true }
                        Text(model.agentBackend)
                            .font(.caption)
                            .foregroundStyle(Color.vibeSecondary)
                    }
                    if model.agentProvider.needsKeyFile {
                        TextField("API key file", text: $model.apiKeyFilePath)
                            .help("Path to a key file (never paste keys into Nix)")
                    }
                    Text("Local weights: \(AgentLocalModels.modelsDirectory.path)")
                        .font(.caption2)
                        .foregroundStyle(Color.vibeSecondary)
                        .textSelection(.enabled)
                }
                Section("Mixture of Experts") {
                    Toggle(
                        "Route by expert",
                        isOn: Binding(
                            get: { model.agentMoE.enabled },
                            set: { model.agentMoE.enabled = $0; model.persistAgentAISettings() }
                        )
                    )
                    .help("Pick local models by task (rename / decompile / ObjC / plan)")
                    Toggle(
                        "Allow API escalation",
                        isOn: Binding(
                            get: { model.agentMoE.allowCloudEscalation },
                            set: {
                                model.agentMoE.allowCloudEscalation = $0
                                model.persistAgentAISettings()
                            }
                        )
                    )
                    .help("On local failure or “use cloud”, call proprietary API if a key file is set")
                    ForEach(AgentExpertRole.allCases) { role in
                        TextField(
                            role.title,
                            text: Binding(
                                get: { model.agentMoE.models[role] ?? "" },
                                set: { model.agentMoE.models[role] = $0 }
                            )
                        )
                        .help(role.hint)
                        .onSubmit { model.persistAgentAISettings() }
                    }
                    if !model.agentMoELastRoute.isEmpty {
                        Text("Last route: \(model.agentMoELastRoute)")
                            .font(.caption2)
                            .foregroundStyle(Color.vibeSecondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 420)
        .vibeContainer(radius: VibeChrome.Radius.shell)
        .onDisappear { model.persistAgentAISettings() }
    }
}
