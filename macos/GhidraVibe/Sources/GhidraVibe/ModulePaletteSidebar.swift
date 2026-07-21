import SwiftUI

/// Leading CodeBrowser Modules palette — Window → provider list with checkmarks + drag-to-dock.
/// Replaces the former right-stack “More…” module picker.
struct ModulePaletteSidebar: View {
    @Environment(AppModel.self) private var model

    private static let regionOrder: [DockRegion] = [
        .left, .center, .right, .bottomStrip, .console, .header,
    ]

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            // Title only — hide/show lives on the main toolbar Modules control.
            Text("Modules")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background {
                    ZStack {
                        VibeChrome.ProviderSurface.titleBar
                        VibeChrome.ProviderSurface.titleBarWash
                    }
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(VibeChrome.ProviderSurface.separator)
                        .frame(height: 1)
                }

            List {
                ForEach(Self.regionOrder, id: \.self) { region in
                    let kinds = modules(in: region)
                    if !kinds.isEmpty {
                        Section(region.title) {
                            ForEach(kinds, id: \.id) { kind in
                                moduleRow(kind)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .a11yContainerCatalog("ghidra.vibe.codebrowser.modules")
    }

    private func modules(in region: DockRegion) -> [ProviderKind] {
        ProviderKind.modularWindowModules.filter {
            model.dockLayout.homeRegion(for: $0) == region
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    @ViewBuilder
    private func moduleRow(_ kind: ProviderKind) -> some View {
        let visible = model.isProviderVisible(kind) || model.dockLayout.isFloating(kind)
        let floating = model.dockLayout.isFloating(kind)
        HStack(spacing: 8) {
            Image(systemName: visible ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(visible ? VibeChrome.ProviderSurface.accent : VibeChrome.ProviderSurface.secondary)
                .font(.body)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                    .lineLimit(1)
                if floating {
                    Text("Floating")
                        .font(.caption2)
                        .foregroundStyle(Color.vibeSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(Color.vibeMuted)
                .help("Drag to tile on Top / Left / Right / Bottom / Center")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleModule(kind)
        }
        .draggable(ProviderDockDrag(kindRaw: kind.rawValue)) {
            Label(kind.title, systemImage: "macwindow")
                .padding(8)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in
                    if model.dockDragKind != kind {
                        model.beginProviderDockDrag(kind)
                    }
                }
        )
        .contextMenu {
            Button(visible ? "Hide \(kind.title)" : "Show \(kind.title)") {
                toggleModule(kind)
            }
            if floating {
                Button("Reattach") { model.reattachProvider(kind) }
            } else if visible {
                Button("Float") { model.floatProvider(kind) }
            }
        }
        .a11yCatalog("ghidra.vibe.codebrowser.module.\(kind.rawValue)")
        .help(visible ? "Hide \(kind.title)" : "Show \(kind.title) — drag to redock")
    }

    private func toggleModule(_ kind: ProviderKind) {
        if model.dockLayout.isFloating(kind) {
            model.reattachProvider(kind)
            return
        }
        if model.isProviderVisible(kind) {
            model.closeProvider(kind)
        } else {
            model.showProvider(kind)
        }
    }
}
