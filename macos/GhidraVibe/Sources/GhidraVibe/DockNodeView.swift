import SwiftUI
import UniformTypeIdentifiers

/// Recursive / region-based CodeBrowser dock renderer with drop zones for redock.
struct DockWorkspaceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HSplitView {
            HSplitView {
                if model.dockLayout.hasVisibleLeft {
                    DockStackColumn(region: .left, style: .verticalPanes)
                        .frame(minWidth: 200, idealWidth: 234, maxWidth: 420)
                        .a11yContainerCatalog("ghidra.vibe.codebrowser.left_dock")
                }

                VSplitView {
                    HSplitView {
                        if model.dockLayout.hasVisibleCenter {
                            DockStackColumn(region: .center, style: .verticalPanes)
                                .frame(minWidth: 280, idealWidth: 520)
                        }
                        if model.dockLayout.hasVisibleRight {
                            DockStackColumn(region: .right, style: .tabbed)
                                .frame(minWidth: 240, idealWidth: 360)
                        }
                    }
                    .layoutPriority(1)

                    if model.dockLayout.hasVisibleBottomStrip {
                        DockStackColumn(region: .bottomStrip, style: .horizontalPanes)
                            .frame(minHeight: 72, idealHeight: 100)
                    }

                    if model.dockLayout.hasVisibleConsole {
                        DockStackColumn(region: .console, style: .tabbed)
                            .frame(minHeight: 88, idealHeight: 120)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            // Xcode-style trailing Agent column (independent of Decompiler tabs).
            if model.agentEnabled, model.dockLayout.agentSidebarVisible {
                AgentChatView()
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 520)
                    .a11yContainerCatalog("ghidra.vibe.agent.sidebar")
            }
        }
        .padding(4)
        .overlay(alignment: .top) {
            if model.dockDragKind != nil {
                DockDropBanner()
            }
        }
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

struct DockStackColumn: View {
    @Environment(AppModel.self) private var model
    let region: DockRegion
    let style: DockStackStyle

    var body: some View {
        @Bindable var model = model
        let visible = model.dockLayout.visibleKinds(in: region)
        let highlighted = model.dockDropHighlight == region

        Group {
            switch style {
            case .verticalPanes:
                VSplitView {
                    ForEach(visible, id: \.id) { kind in
                        ProviderView(kind: kind)
                            .frame(minHeight: 72)
                    }
                }
            case .horizontalPanes:
                HSplitView {
                    ForEach(visible, id: \.id) { kind in
                        ProviderView(kind: kind)
                    }
                }
            case .tabbed:
                tabbedStack(visible: visible)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(highlighted ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .background(highlighted ? Color.accentColor.opacity(0.08) : Color.clear)
        .onDrop(of: [.json], isTargeted: Binding(
            get: { model.dockDropHighlight == region },
            set: { hovering in
                if hovering {
                    model.dockDropHighlight = region
                } else if model.dockDropHighlight == region {
                    model.dockDropHighlight = nil
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
            if tabKinds.count > 1 || region == .right || region == .console {
                dockTabBar(visible: tabKinds)
            }
            if let active, visible.contains(active) || (region == .console && tabKinds.contains(active)) {
                ProviderView(kind: active)
            } else if let first = visible.first {
                ProviderView(kind: first)
            }
        }
    }

    @ViewBuilder
    private func dockTabBar(visible: [ProviderKind]) -> some View {
        @Bindable var model = model
        LiquidGlass.Bar(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(visible, id: \.id) { kind in
                        let selected = model.dockLayout.activeKind(in: region) == kind
                        Button(kind.title) {
                            if !model.isProviderVisible(kind) {
                                model.showProvider(kind)
                            }
                            model.selectDockTab(kind, in: region)
                        }
                        .modifier(GlassTabStyle(prominent: selected))
                        .font(.caption2)
                        .a11yCatalog("ghidra.vibe.codebrowser.tab.\(kind.rawValue)")
                        .help("Show \(kind.title) provider")
                    }
                    if region == .right {
                        rightMoreMenu
                    }
                }
                .padding(4)
            }
        }
    }

    private var rightMoreMenu: some View {
        let moreTabs = ProviderKind.windowMenuOrder.filter { kind in
            !DockLayoutState.defaultRightTabs.contains(kind)
                && kind != .entropy
                && kind != .overview
                && kind != .bookmarks
                && kind != .versionTracking
        }
        return Menu("More…") {
            ForEach(moreTabs, id: \.id) { kind in
                Button(kind.title) { model.showProvider(kind) }
                    .help("Show \(kind.title) provider")
            }
            Divider()
            Button("Data Type Preview") { model.showProvider(.datatypePreview) }
                .help("Show Data Type Preview in bottom strip")
            Button("Disassembled View") { model.showProvider(.disassembledView) }
                .help("Show Disassembled View in bottom strip")
        }
        .buttonStyle(.glass)
        .font(.caption2)
        .a11yCatalog("ghidra.vibe.codebrowser.more")
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
                model.dockDragKind = nil
                model.dockDropHighlight = nil
            }
        }
        return true
    }
}

struct DockDropBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.3x1")
            Text(model.dockDragKind.map { "Dock \($0.title) — drop on Left / Center / Right / Bottom / Console" } ?? "Dock")
                .font(.caption.weight(.medium))
            Spacer(minLength: 0)
            ForEach(DockRegion.dropTargets, id: \DockRegion.id) { (region: DockRegion) in
                Button(region.title) {
                    if let kind = model.dockDragKind {
                        model.moveProvider(kind, to: region)
                    }
                    model.dockDragKind = nil
                }
                .buttonStyle(.glass)
                .font(.caption2)
                .a11yCatalog("ghidra.vibe.dock.drop.\(region.rawValue)")
            }
            Button("Float") {
                if let kind = model.dockDragKind {
                    model.floatProvider(kind)
                }
                model.dockDragKind = nil
            }
            .buttonStyle(.glass)
            .font(.caption2)
            .a11yCatalog("ghidra.vibe.dock.drop.floating")
            Button("Cancel", role: .cancel) {
                model.dockDragKind = nil
                model.dockDropHighlight = nil
            }
            .buttonStyle(.borderless)
            .font(.caption2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(8)
        .a11yContainerCatalog("ghidra.vibe.dock.drop_banner")
    }
}
