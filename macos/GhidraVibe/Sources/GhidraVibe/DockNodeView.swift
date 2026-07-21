import SwiftUI
import UniformTypeIdentifiers

/// Recursive / region-based CodeBrowser dock renderer with drop zones for redock.
struct DockWorkspaceView: View {
    @Environment(AppModel.self) private var model

    private var dragging: Bool { model.dockDragKind != nil }

    var body: some View {
        @Bindable var model = model
        // Mins must sum under a narrow CodeBrowser width. High mins (Modules+Left+Center+Right+Agent
        // ≈ 1160) made HSplitView fight the window and collapse/clip the whole UI.
        GeometryReader { geo in
            let narrow = geo.size.width < 960
            // Top edge drop uses CodeBrowser header strip (shown while dragging).
            HSplitView {
                    // Leading Modules palette (Window → providers) — checkmarks + drag-to-dock.
                    if model.dockLayout.leftSidebarVisible {
                        ModulePaletteSidebar()
                            .frame(
                                minWidth: narrow ? 120 : 140,
                                idealWidth: 200,
                                maxWidth: 280
                            )
                    }

                    HSplitView {
                        if model.dockLayout.hasVisibleLeft || dragging {
                            DockStackColumn(region: .left, style: .verticalPanes)
                                .frame(
                                    minWidth: narrow ? 100 : 140,
                                    idealWidth: 220,
                                    maxWidth: 360
                                )
                                .a11yContainerCatalog("ghidra.vibe.codebrowser.left_dock")
                        }

                        VSplitView {
                            HSplitView {
                                if model.dockLayout.hasVisibleCenter || dragging {
                                    // Listing (center) must shrink freely — wide disasm scrolls horizontally
                                    // inside the provider; do not force a fat minWidth on the split.
                                    DockStackColumn(region: .center, style: .verticalPanes)
                                        // Listing scrolls horizontally inside; keep the column tiny so
                                        // side docks / Agent can claim space.
                                        .frame(minWidth: 36, idealWidth: 480)
                                        .layoutPriority(1)
                                }
                                if model.dockLayout.hasVisibleRight || dragging {
                                    DockStackColumn(region: .right, style: .tabbed)
                                        .frame(
                                            minWidth: narrow ? 120 : 160,
                                            idealWidth: 300,
                                            maxWidth: 480
                                        )
                                }
                            }
                            .layoutPriority(1)

                            if model.dockLayout.hasVisibleBottomStrip || dragging {
                                DockStackColumn(region: .bottomStrip, style: .horizontalPanes)
                                    .frame(minHeight: 56, idealHeight: 100)
                            }

                            if model.dockLayout.hasVisibleConsole || dragging {
                                DockStackColumn(region: .console, style: .tabbed)
                                    .frame(minHeight: 72, idealHeight: 120)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .layoutPriority(1)
                    }

                // Trailing Agent column only — not a modular dock provider.
                if model.agentEnabled, model.dockLayout.agentSidebarVisible {
                    AgentChatView()
                        .frame(
                            minWidth: narrow ? 140 : 180,
                            idealWidth: 280,
                            maxWidth: 420
                        )
                        .a11yContainerCatalog("ghidra.vibe.agent.sidebar")
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay {
                if dragging {
                    DockEdgeGuideOverlay()
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(VibeChrome.Space.xs)
        .overlay(alignment: .top) {
            if model.dockDragKind != nil {
                DockDropBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.18), value: model.dockDragKind)
        .animation(.easeInOut(duration: 0.12), value: model.dockDropHighlight)
    }
}

enum DockStackStyle {
    /// Each visible provider is its own pane (stock left trees).
    case verticalPanes
    /// Side-by-side panes (stock bottom strip).
    case horizontalPanes
    /// Tab bar + single active provider (stock right / console).
    case tabbed
}

/// Thin drop-only lane for edges that are not always an open stack (e.g. Top / Header).
struct DockEdgeDropLane: View {
    @Environment(AppModel.self) private var model
    let region: DockRegion

    var body: some View {
        let highlighted = model.dockDropHighlight == region
        ZStack {
            Rectangle()
                .fill(VibeChrome.ProviderSurface.accent.opacity(highlighted ? 0.28 : 0.12))
            Rectangle()
                .strokeBorder(
                    VibeChrome.ProviderSurface.accent,
                    style: StrokeStyle(lineWidth: highlighted ? 3 : 2, dash: highlighted ? [] : [7, 4])
                )
            HStack(spacing: 8) {
                Image(systemName: region.symbol)
                    .font(.system(size: 14, weight: .bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text((region.tileEdge?.title ?? region.title).uppercased())
                        .font(.caption2.weight(.heavy))
                        .tracking(0.7)
                    Text(highlighted ? region.tileVerb : "Drop here to \(region.tileVerb.lowercased())")
                        .font(.caption.weight(.semibold))
                }
                Spacer(minLength: 0)
                if let title = model.dockDragKind?.title, highlighted {
                    Text("“\(title)”")
                        .font(.caption2)
                        .foregroundStyle(Color.vibeSecondary)
                }
            }
            .foregroundStyle(VibeChrome.ProviderSurface.accent)
            .padding(.horizontal, 12)
        }
        .onDrop(of: [.json], isTargeted: Binding(
            get: { model.dockDropHighlight == region },
            set: { hovering in
                if hovering {
                    model.setDockDropHighlight(region)
                } else if model.dockDropHighlight == region {
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
                    model.moveProvider(kind, to: region)
                }
            }
            return true
        }
        .a11yCatalog("ghidra.vibe.dock.edge_lane.\(region.rawValue)")
    }
}

struct DockStackColumn: View {
    @Environment(AppModel.self) private var model
    let region: DockRegion
    let style: DockStackStyle

    var body: some View {
        @Bindable var model = model
        let visible = model.dockLayout.visibleKinds(in: region)
        let highlighted = model.dockDropHighlight == region
        let showEmptyDrop = model.dockDragKind != nil && visible.isEmpty

        Group {
            switch style {
            case .verticalPanes:
                if visible.isEmpty {
                    Color.clear
                } else {
                    VSplitView {
                        ForEach(visible, id: \.id) { kind in
                            ProviderView(kind: kind)
                                .frame(minHeight: 72)
                        }
                    }
                }
            case .horizontalPanes:
                if visible.isEmpty {
                    Color.clear
                } else {
                    HSplitView {
                        ForEach(visible, id: \.id) { kind in
                            ProviderView(kind: kind)
                        }
                    }
                }
            case .tabbed:
                if visible.isEmpty, model.dockDragKind == nil {
                    Color.clear
                } else {
                    tabbedStack(visible: visible)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            DockRegionDropOverlay(
                region: region,
                highlighted: highlighted,
                emptyPlaceholder: showEmptyDrop,
                movingTitle: model.dockDragKind?.title
            )
        }
        .onDrop(of: [.json], isTargeted: Binding(
            get: { model.dockDropHighlight == region },
            set: { hovering in
                if hovering {
                    model.setDockDropHighlight(region)
                } else if model.dockDropHighlight == region {
                    model.setDockDropHighlight(nil)
                }
            }
        )) { providers in
            handleDrop(providers)
        }
        .a11yContainerCatalog("ghidra.vibe.dock.region.\(region.rawValue)")
    }

    @ViewBuilder
    private func tabbedStack(visible: [ProviderKind]) -> some View {
        @Bindable var model = model
        // Stock Console stack always exposes Console + Bookmarks tabs.
        let tabKinds: [ProviderKind] =
            region == .console ? model.dockLayout.kinds(in: .console) : visible
        let active = model.dockLayout.activeKind(in: region)
        VStack(spacing: 0) {
            // Right dock: Modules sidebar switches providers — no redundant horizontal tab strip.
            if region == .console, tabKinds.count > 1 || !visible.isEmpty {
                dockTabBar(visible: tabKinds)
            }
            if let active, visible.contains(active) || (region == .console && tabKinds.contains(active)) {
                ProviderView(kind: active)
            } else if let first = visible.first {
                ProviderView(kind: first)
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private func dockTabBar(visible: [ProviderKind]) -> some View {
        @Bindable var model = model
        // Square stock tab strip (not concentric glass plate).
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(visible.filter(\.isModularDockProvider), id: \.id) { kind in
                    let selected = model.dockLayout.activeKind(in: region) == kind
                    Button(kind.title) {
                        if !model.isProviderVisible(kind) {
                            model.showProvider(kind)
                        }
                        model.selectDockTab(kind, in: region)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(selected ? VibeChrome.ProviderSurface.accent : nil)
                    .font(.caption2)
                    .a11yCatalog("ghidra.vibe.codebrowser.tab.\(kind.rawValue)")
                    .help("Show \(kind.title) provider")
                }
            }
            .padding(4)
        }
        .background {
            ZStack {
                VibeChrome.ProviderSurface.titleBar
                VibeChrome.ProviderSurface.titleBarWash
            }
        }
        .a11yContainerCatalog(
            region == .right
                ? "ghidra.vibe.codebrowser.right_tabs"
                : "ghidra.vibe.codebrowser.tabs.\(region.rawValue)"
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(VibeChrome.ProviderSurface.separator)
                .frame(height: 1)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadDataRepresentation(for: .json) { data, _ in
            guard let data,
                  let drag = try? JSONDecoder().decode(ProviderDockDrag.self, from: data),
                  let kind = drag.kind
            else { return }
            Task { @MainActor in
                model.moveProvider(kind, to: region)
            }
        }
        return true
    }
}

/// Large, obvious drop-target feedback while redocking a provider.
struct DockRegionDropOverlay: View {
    let region: DockRegion
    let highlighted: Bool
    var emptyPlaceholder: Bool = false
    var movingTitle: String? = nil

    var body: some View {
        let active = highlighted || emptyPlaceholder
        ZStack {
            if active {
                Rectangle()
                    .fill(VibeChrome.ProviderSurface.accent.opacity(highlighted ? 0.24 : 0.10))
                Rectangle()
                    .strokeBorder(
                        VibeChrome.ProviderSurface.accent,
                        style: StrokeStyle(lineWidth: highlighted ? 3.5 : 2, dash: highlighted ? [] : [8, 5])
                    )
                // Thick rail on the edge this region tiles against (skip center fill).
                if let edge = region.tileEdge, edge != .center {
                    DockEdgeRailMark(edge: edge, hot: highlighted)
                }
                VStack(spacing: 4) {
                    if let edge = region.tileEdge {
                        Text(edge.title.uppercased())
                            .font(.caption2.weight(.heavy))
                            .tracking(0.8)
                    }
                    Image(systemName: region.symbol)
                        .font(.system(size: highlighted ? 26 : 20, weight: .semibold))
                    Text(highlighted
                         ? region.tileVerb
                         : (emptyPlaceholder ? "Drop to \(region.tileVerb.lowercased())" : region.dropLabel))
                        .font(.caption.weight(.bold))
                        .multilineTextAlignment(.center)
                    if highlighted, let movingTitle {
                        Text("“\(movingTitle)”")
                            .font(.caption2)
                            .foregroundStyle(Color.vibeSecondary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(VibeChrome.ProviderSurface.accent)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(VibeChrome.ProviderSurface.control.opacity(0.94))
                }
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.12), value: highlighted)
        .a11yCatalog("ghidra.vibe.dock.overlay.\(region.rawValue)")
    }
}

/// Thick accent rail glued to the tile edge inside a region overlay.
private struct DockEdgeRailMark: View {
    let edge: DockTileEdge
    let hot: Bool

    var body: some View {
        let thickness: CGFloat = hot ? 8 : 5
        Rectangle()
            .fill(VibeChrome.ProviderSurface.accent.opacity(hot ? 0.95 : 0.55))
            .frame(
                width: (edge == .left || edge == .right) ? thickness : nil,
                height: (edge == .top || edge == .bottom) ? thickness : nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private var alignment: Alignment {
        switch edge {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        case .center: .center
        }
    }
}

/// Workspace-wide edge rails while dragging — identify Top / Left / Right / Bottom before drop.
struct DockEdgeGuideOverlay: View {
    @Environment(AppModel.self) private var model

    private let rail: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let hot = model.dockDropHighlight
            ZStack {
                // Top
                edgeRail(
                    hot: hot?.tileEdge == .top,
                    label: "TOP",
                    width: geo.size.width,
                    height: rail
                )
                .frame(maxHeight: .infinity, alignment: .top)

                // Bottom (covers bottom strip + console)
                edgeRail(
                    hot: hot?.tileEdge == .bottom,
                    label: hot == .console ? "BOTTOM · CONSOLE" : "BOTTOM",
                    width: geo.size.width,
                    height: rail
                )
                .frame(maxHeight: .infinity, alignment: .bottom)

                // Left
                edgeRail(
                    hot: hot?.tileEdge == .left,
                    label: "LEFT",
                    width: rail,
                    height: geo.size.height,
                    vertical: true
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right
                edgeRail(
                    hot: hot?.tileEdge == .right,
                    label: "RIGHT",
                    width: rail,
                    height: geo.size.height,
                    vertical: true
                )
                .frame(maxWidth: .infinity, alignment: .trailing)

                // Center compass chip
                VStack(spacing: 6) {
                    Text("TILE EDGES")
                        .font(.caption2.weight(.heavy))
                        .tracking(1.0)
                        .foregroundStyle(VibeChrome.ProviderSurface.accent)
                    HStack(spacing: 8) {
                        ForEach(DockRegion.primaryEdgeTargets, id: \.id) { region in
                            let active = hot == region
                                || (region == .bottomStrip && hot?.tileEdge == .bottom)
                            Text(region.tileEdge?.title ?? region.title)
                                .font(.caption2.weight(active ? .bold : .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background {
                                    Capsule()
                                        .fill(
                                            active
                                                ? VibeChrome.ProviderSurface.accent.opacity(0.35)
                                                : VibeChrome.ProviderSurface.control.opacity(0.85)
                                        )
                                }
                                .overlay {
                                    Capsule()
                                        .strokeBorder(
                                            VibeChrome.ProviderSurface.accent.opacity(active ? 1 : 0.35),
                                            lineWidth: active ? 1.5 : 1
                                        )
                                }
                        }
                    }
                    if let hot, let kind = model.dockDragKind {
                        Text(hot.hoverPlacementHint(moving: kind.title))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VibeChrome.ProviderSurface.foreground)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    } else {
                        Text("Hover an edge to preview drop · Top / Left / Right / Bottom / Center")
                            .font(.caption)
                            .foregroundStyle(Color.vibeSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(VibeChrome.ProviderSurface.control.opacity(0.92))
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
                }
                .frame(maxWidth: min(geo.size.width - 48, 520))
            }
        }
        .a11yCatalog("ghidra.vibe.dock.edge_guide")
    }

    @ViewBuilder
    private func edgeRail(
        hot: Bool,
        label: String,
        width: CGFloat,
        height: CGFloat,
        vertical: Bool = false
    ) -> some View {
        ZStack {
            Rectangle()
                .fill(VibeChrome.ProviderSurface.accent.opacity(hot ? 0.55 : 0.22))
            if !vertical {
                Text(label)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(hot ? 1 : 0.85))
            } else {
                Text(label)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(hot ? 1 : 0.85))
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
            }
        }
        .frame(width: width, height: height)
        .animation(.easeInOut(duration: 0.1), value: hot)
    }
}

struct DockDropBanner: View {
    @Environment(AppModel.self) private var model

    private var liveHint: String {
        guard let kind = model.dockDragKind else {
            return "Drop on Top / Left / Right / Bottom / Center to tile."
        }
        if let region = model.dockDropHighlight {
            return region.hoverPlacementHint(moving: kind.title)
        }
        return "Hover Top · Left · Right · Bottom · Center — drop when the edge lights up."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(VibeChrome.ProviderSurface.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.dockDragKind.map { "Moving “\($0.title)”" } ?? "Moving provider")
                        .font(.headline)
                    Text(liveHint)
                        .font(.caption.weight(model.dockDropHighlight == nil ? .regular : .semibold))
                        .foregroundStyle(
                            model.dockDropHighlight == nil
                                ? Color.vibeSecondary
                                : VibeChrome.ProviderSurface.accent
                        )
                        .animation(.easeInOut(duration: 0.1), value: model.dockDropHighlight)
                }
                Spacer(minLength: 0)
                Button("Cancel", role: .cancel) {
                    model.clearProviderDockDrag()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 6) {
                ForEach(DockRegion.dropTargets, id: \DockRegion.id) { (region: DockRegion) in
                    let hot = model.dockDropHighlight == region
                    Button {
                        if let kind = model.dockDragKind {
                            model.moveProvider(kind, to: region)
                        }
                    } label: {
                        Label(region.dropLabel, systemImage: region.symbol)
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(hot ? VibeChrome.ProviderSurface.accent : Color.vibeSelection.opacity(0.35))
                    .controlSize(.small)
                    .help(region.tileVerb)
                    .a11yCatalog("ghidra.vibe.dock.drop.\(region.rawValue)")
                }
                Button {
                    if let kind = model.dockDragKind {
                        model.floatProvider(kind)
                    }
                } label: {
                    Label("Float", systemImage: DockRegion.floating.symbol)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Float as a separate window")
                .a11yCatalog("ghidra.vibe.dock.drop.floating")
            }
        }
        .padding(12)
        .background(VibeChrome.ProviderSurface.control)
        .overlay {
            Rectangle()
                .stroke(VibeChrome.ProviderSurface.accent.opacity(0.55), lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .a11yContainerCatalog("ghidra.vibe.dock.drop_banner")
    }
}
