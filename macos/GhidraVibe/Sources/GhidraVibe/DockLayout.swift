import Foundation
import UniformTypeIdentifiers
import CoreTransferable

/// Screen edge a modular provider tiles against when dropped on a dock region.
enum DockTileEdge: String, CaseIterable, Identifiable, Hashable {
    case top
    case left
    case right
    case bottom
    case center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: "Top"
        case .left: "Left"
        case .right: "Right"
        case .bottom: "Bottom"
        case .center: "Center"
        }
    }

    var symbol: String {
        switch self {
        case .top: "rectangle.topthird.inset.filled"
        case .left: "sidebar.left"
        case .right: "sidebar.right"
        case .bottom: "rectangle.bottomthird.inset.filled"
        case .center: "rectangle.center.inset.filled"
        }
    }
}

/// Stock CodeBrowser dock regions (SwiftUI stand-in for DockingWindowManager anchors).
enum DockRegion: String, Codable, CaseIterable, Identifiable, Hashable {
    case header
    case left
    case center
    case right
    case bottomStrip
    case console
    case floating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .header: "Header"
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        case .bottomStrip: "Bottom Strip"
        case .console: "Console"
        case .floating: "Floating"
        }
    }

    /// Which workspace edge this region tiles against (nil for float).
    var tileEdge: DockTileEdge? {
        switch self {
        case .header: .top
        case .left: .left
        case .right: .right
        case .bottomStrip, .console: .bottom
        case .center: .center
        case .floating: nil
        }
    }

    /// Short control label: edge first, then region when edges share a side.
    var dropLabel: String {
        switch self {
        case .header: "Top · Header"
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        case .bottomStrip: "Bottom · Strip"
        case .console: "Bottom · Console"
        case .floating: "Float"
        }
    }

    /// Imperative placement verb shown on hover / drop overlays.
    var tileVerb: String {
        switch self {
        case .header: "Tile top (header)"
        case .left: "Tile left"
        case .center: "Stack in center"
        case .right: "Tile right"
        case .bottomStrip: "Tile bottom strip"
        case .console: "Tile bottom console"
        case .floating: "Float window"
        }
    }

    /// SF Symbol for drop-target affordances (CodeBrowser redock HUD).
    var symbol: String {
        tileEdge?.symbol ?? "macwindow"
    }

    /// Live status / banner line while hovering this drop target.
    func hoverPlacementHint(moving kindTitle: String) -> String {
        switch self {
        case .header:
            return "Will tile TOP — “\(kindTitle)” → header strip"
        case .left:
            return "Will tile LEFT — “\(kindTitle)” → left dock"
        case .right:
            return "Will tile RIGHT — “\(kindTitle)” → right dock"
        case .center:
            return "Will stack CENTER — “\(kindTitle)” → main column"
        case .bottomStrip:
            return "Will tile BOTTOM — “\(kindTitle)” → bottom strip"
        case .console:
            return "Will tile BOTTOM — “\(kindTitle)” → console stack"
        case .floating:
            return "Will FLOAT — “\(kindTitle)” as a separate window"
        }
    }

    func dockedStatus(moving kindTitle: String) -> String {
        switch self {
        case .header: "Docked \(kindTitle) to top (header)"
        case .left: "Docked \(kindTitle) to left edge"
        case .right: "Docked \(kindTitle) to right edge"
        case .center: "Docked \(kindTitle) to center"
        case .bottomStrip: "Docked \(kindTitle) to bottom strip"
        case .console: "Docked \(kindTitle) to bottom console"
        case .floating: "Floating \(kindTitle)"
        }
    }

    /// Regions that accept redock drops (not the floating bucket itself).
    static let dropTargets: [DockRegion] = [.left, .center, .right, .bottomStrip, .console, .header]

    /// Primary edge tiles shown in the drag compass (one chip per edge).
    static let primaryEdgeTargets: [DockRegion] = [.header, .left, .center, .right, .bottomStrip]
}

/// Serializable CodeBrowser dock layout — seeded from stock CodeBrowser.tool geometry intent.
struct DockLayoutState: Codable, Equatable {
    /// Ordered providers per region. Left/center/bottomStrip render as stacked panes;
    /// right/console/header use tab stacks when multiple visible.
    var stacks: [String: [String]]
    var active: [String: String]
    var hidden: [String]
    var floating: [String]
    /// Last non-floating region for reattach after close/float.
    var home: [String: String]

    var leftWidthRatio: Double
    var rightWidthRatio: Double
    var consoleHeightRatio: Double
    var bottomStripHeightRatio: Double
    /// Leading Modules palette (Window → providers); independent of left dock panes.
    var leftSidebarVisible: Bool
    /// Xcode-style trailing Agent chat column (not a dockable provider module).
    var agentSidebarVisible: Bool
    var agentSidebarWidthRatio: Double

    static let persistenceKey = "ghidra.vibe.dock.layout.v1"

    enum CodingKeys: String, CodingKey {
        case stacks, active, hidden, floating, home
        case leftWidthRatio, rightWidthRatio, consoleHeightRatio, bottomStripHeightRatio
        case leftSidebarVisible, agentSidebarVisible, agentSidebarWidthRatio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stacks = try c.decodeIfPresent([String: [String]].self, forKey: .stacks) ?? [:]
        active = try c.decodeIfPresent([String: String].self, forKey: .active) ?? [:]
        hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? []
        floating = try c.decodeIfPresent([String].self, forKey: .floating) ?? []
        home = try c.decodeIfPresent([String: String].self, forKey: .home) ?? [:]
        leftWidthRatio = try c.decodeIfPresent(Double.self, forKey: .leftWidthRatio) ?? 0.14
        rightWidthRatio = try c.decodeIfPresent(Double.self, forKey: .rightWidthRatio) ?? 0.28
        consoleHeightRatio = try c.decodeIfPresent(Double.self, forKey: .consoleHeightRatio) ?? 0.16
        bottomStripHeightRatio = try c.decodeIfPresent(Double.self, forKey: .bottomStripHeightRatio) ?? 0.12
        leftSidebarVisible = try c.decodeIfPresent(Bool.self, forKey: .leftSidebarVisible) ?? true
        agentSidebarVisible = try c.decodeIfPresent(Bool.self, forKey: .agentSidebarVisible) ?? true
        agentSidebarWidthRatio = try c.decodeIfPresent(Double.self, forKey: .agentSidebarWidthRatio) ?? 0.22
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stacks, forKey: .stacks)
        try c.encode(active, forKey: .active)
        try c.encode(hidden, forKey: .hidden)
        try c.encode(floating, forKey: .floating)
        try c.encode(home, forKey: .home)
        try c.encode(leftWidthRatio, forKey: .leftWidthRatio)
        try c.encode(rightWidthRatio, forKey: .rightWidthRatio)
        try c.encode(consoleHeightRatio, forKey: .consoleHeightRatio)
        try c.encode(bottomStripHeightRatio, forKey: .bottomStripHeightRatio)
        try c.encode(leftSidebarVisible, forKey: .leftSidebarVisible)
        try c.encode(agentSidebarVisible, forKey: .agentSidebarVisible)
        try c.encode(agentSidebarWidthRatio, forKey: .agentSidebarWidthRatio)
    }

    // Memberwise init retained for stockDefault (custom Codable suppresses synthesis).
    init(
        stacks: [String: [String]],
        active: [String: String],
        hidden: [String],
        floating: [String],
        home: [String: String],
        leftWidthRatio: Double,
        rightWidthRatio: Double,
        consoleHeightRatio: Double,
        bottomStripHeightRatio: Double,
        leftSidebarVisible: Bool,
        agentSidebarVisible: Bool,
        agentSidebarWidthRatio: Double
    ) {
        self.stacks = stacks
        self.active = active
        self.hidden = hidden
        self.floating = floating
        self.home = home
        self.leftWidthRatio = leftWidthRatio
        self.rightWidthRatio = rightWidthRatio
        self.consoleHeightRatio = consoleHeightRatio
        self.bottomStripHeightRatio = bottomStripHeightRatio
        self.leftSidebarVisible = leftSidebarVisible
        self.agentSidebarVisible = agentSidebarVisible
        self.agentSidebarWidthRatio = agentSidebarWidthRatio
    }

    static func stockDefault() -> DockLayoutState {
        DockLayoutState(
            stacks: [
                DockRegion.header.rawValue: [ProviderKind.entropy.rawValue, ProviderKind.overview.rawValue],
                DockRegion.left.rawValue: [
                    ProviderKind.programTree.rawValue,
                    ProviderKind.symbolTree.rawValue,
                    ProviderKind.dataTypes.rawValue,
                    ProviderKind.swiftClasses.rawValue,
                ],
                DockRegion.center.rawValue: [ProviderKind.listing.rawValue],
                DockRegion.right.rawValue: [
                    ProviderKind.decompiler.rawValue,
                    ProviderKind.bytes.rawValue,
                    ProviderKind.definedData.rawValue,
                    ProviderKind.strings.rawValue,
                    ProviderKind.equates.rawValue,
                    ProviderKind.externalPrograms.rawValue,
                    ProviderKind.functions.rawValue,
                    ProviderKind.relocations.rawValue,
                    ProviderKind.memoryMap.rawValue,
                    ProviderKind.symbolTable.rawValue,
                    ProviderKind.scriptManager.rawValue,
                    ProviderKind.functionGraph.rawValue,
                    ProviderKind.registers.rawValue,
                ],
                DockRegion.bottomStrip.rawValue: [
                    ProviderKind.datatypePreview.rawValue,
                    ProviderKind.disassembledView.rawValue,
                ],
                DockRegion.console.rawValue: [
                    ProviderKind.console.rawValue,
                    ProviderKind.bookmarks.rawValue,
                ],
            ],
            active: [
                DockRegion.right.rawValue: ProviderKind.decompiler.rawValue,
                DockRegion.console.rawValue: ProviderKind.console.rawValue,
                DockRegion.header.rawValue: ProviderKind.entropy.rawValue,
            ],
            // Header + bottom strip + bookmarks inactive; extras closed until Window menu.
            hidden: Self.defaultHiddenRawValues(),
            floating: [],
            home: [:],
            leftWidthRatio: 0.14,
            rightWidthRatio: 0.28,
            consoleHeightRatio: 0.16,
            bottomStripHeightRatio: 0.12,
            leftSidebarVisible: true,
            agentSidebarVisible: true,
            agentSidebarWidthRatio: 0.22
        )
        .withDefaultHomes()
    }

    /// Right-stack tabs present at stock CodeBrowser open (not Window-menu extras).
    static let defaultRightTabs: [ProviderKind] = [
        .decompiler, .bytes, .definedData, .strings, .equates, .externalPrograms,
        .functions, .relocations, .memoryMap, .symbolTable, .scriptManager,
        .functionGraph, .registers,
    ]

    private static func defaultHiddenRawValues() -> [String] {
        var hidden: Set<String> = [
            ProviderKind.entropy.rawValue,
            ProviderKind.overview.rawValue,
            ProviderKind.datatypePreview.rawValue,
            ProviderKind.disassembledView.rawValue,
            ProviderKind.bookmarks.rawValue,
        ]
        let alwaysVisible = Set(
            ProviderKind.defaultDocked.map(\.rawValue)
                + defaultRightTabs.map(\.rawValue)
        )
        for kind in ProviderKind.allCases
            where kind != .versionTracking && kind.isModularDockProvider
        {
            if !alwaysVisible.contains(kind.rawValue) {
                hidden.insert(kind.rawValue)
            }
        }
        // Agent is trailing-sidebar only — never a modular dock tab.
        hidden.insert(ProviderKind.agent.rawValue)
        return Array(hidden)
    }

    private func withDefaultHomes() -> DockLayoutState {
        var copy = self
        for region in DockRegion.allCases where region != .floating {
            for raw in copy.kinds(in: region) {
                if copy.home[raw.rawValue] == nil {
                    copy.home[raw.rawValue] = region.rawValue
                }
            }
        }
        // Window-menu extras default home = right stack.
        for kind in ProviderKind.windowMenuOrder {
            if copy.home[kind.rawValue] == nil {
                copy.home[kind.rawValue] = DockRegion.right.rawValue
            }
        }
        return copy
    }

    func kinds(in region: DockRegion) -> [ProviderKind] {
        (stacks[region.rawValue] ?? []).compactMap(ProviderKind.init(rawValue:))
    }

    mutating func setKinds(_ kinds: [ProviderKind], in region: DockRegion) {
        stacks[region.rawValue] = kinds.map(\.rawValue)
    }

    func activeKind(in region: DockRegion) -> ProviderKind? {
        guard let raw = active[region.rawValue] else { return kinds(in: region).first }
        return ProviderKind(rawValue: raw) ?? kinds(in: region).first
    }

    mutating func setActive(_ kind: ProviderKind?, in region: DockRegion) {
        if let kind {
            active[region.rawValue] = kind.rawValue
        } else {
            active.removeValue(forKey: region.rawValue)
        }
    }

    var hiddenSet: Set<ProviderKind> {
        Set(hidden.compactMap(ProviderKind.init(rawValue:)))
    }

    var floatingSet: Set<ProviderKind> {
        Set(floating.compactMap(ProviderKind.init(rawValue:)))
    }

    func isHidden(_ kind: ProviderKind) -> Bool {
        hidden.contains(kind.rawValue)
    }

    func isFloating(_ kind: ProviderKind) -> Bool {
        floating.contains(kind.rawValue)
    }

    func isDockVisible(_ kind: ProviderKind) -> Bool {
        !isHidden(kind) && !isFloating(kind)
    }

    func region(containing kind: ProviderKind) -> DockRegion? {
        if isFloating(kind) { return .floating }
        for region in DockRegion.allCases where region != .floating {
            if kinds(in: region).contains(kind) { return region }
        }
        if let homeRaw = home[kind.rawValue], let r = DockRegion(rawValue: homeRaw) {
            return r
        }
        return nil
    }

    func homeRegion(for kind: ProviderKind) -> DockRegion {
        if let raw = home[kind.rawValue], let r = DockRegion(rawValue: raw), r != .floating {
            return r
        }
        if ProviderKind.bottomStrip.contains(kind) { return .bottomStrip }
        if ProviderKind.consoleStack.contains(kind) { return .console }
        if kind == .listing { return .center }
        if [.programTree, .symbolTree, .dataTypes, .swiftClasses].contains(kind) { return .left }
        if kind == .entropy || kind == .overview { return .header }
        return .right
    }

    mutating func removeFromAllStacks(_ kind: ProviderKind) {
        for region in DockRegion.allCases where region != .floating {
            let list = kinds(in: region).filter { $0 != kind }
            setKinds(list, in: region)
            if activeKind(in: region) == kind {
                setActive(list.first, in: region)
            }
        }
    }

    mutating func move(_ kind: ProviderKind, to region: DockRegion, activate: Bool = true) {
        floating.removeAll { $0 == kind.rawValue }
        hidden.removeAll { $0 == kind.rawValue }
        removeFromAllStacks(kind)
        if region == .floating {
            if !floating.contains(kind.rawValue) {
                floating.append(kind.rawValue)
            }
            return
        }
        var list = kinds(in: region)
        if !list.contains(kind) {
            list.append(kind)
            setKinds(list, in: region)
        }
        home[kind.rawValue] = region.rawValue
        if activate {
            setActive(kind, in: region)
        }
    }

    mutating func show(_ kind: ProviderKind) {
        floating.removeAll { $0 == kind.rawValue }
        hidden.removeAll { $0 == kind.rawValue }
        let region = region(containing: kind).flatMap { $0 == .floating ? nil : $0 } ?? homeRegion(for: kind)
        if !kinds(in: region).contains(kind) {
            var list = kinds(in: region)
            list.append(kind)
            setKinds(list, in: region)
        }
        home[kind.rawValue] = region.rawValue
        setActive(kind, in: region)
    }

    mutating func close(_ kind: ProviderKind) {
        floating.removeAll { $0 == kind.rawValue }
        if !hidden.contains(kind.rawValue) {
            hidden.append(kind.rawValue)
        }
        // Closing console hides the whole console stack (stock).
        if kind == .console || kind == .bookmarks {
            for k in ProviderKind.consoleStack where !hidden.contains(k.rawValue) {
                hidden.append(k.rawValue)
            }
        }
    }

    mutating func float(_ kind: ProviderKind) {
        if let current = region(containing: kind), current != .floating {
            home[kind.rawValue] = current.rawValue
        } else if home[kind.rawValue] == nil {
            home[kind.rawValue] = homeRegion(for: kind).rawValue
        }
        removeFromAllStacks(kind)
        hidden.removeAll { $0 == kind.rawValue }
        if !floating.contains(kind.rawValue) {
            floating.append(kind.rawValue)
        }
    }

    mutating func reattach(_ kind: ProviderKind) {
        let target = homeRegion(for: kind)
        move(kind, to: target, activate: true)
    }

    func visibleKinds(in region: DockRegion) -> [ProviderKind] {
        kinds(in: region).filter { isDockVisible($0) }
    }

    var hasVisibleLeft: Bool { !visibleKinds(in: .left).isEmpty }
    var hasVisibleCenter: Bool { !visibleKinds(in: .center).isEmpty }
    var hasVisibleRight: Bool { !visibleKinds(in: .right).isEmpty }
    var hasVisibleBottomStrip: Bool { !visibleKinds(in: .bottomStrip).isEmpty }
    var hasVisibleConsole: Bool { !visibleKinds(in: .console).isEmpty }
    var hasVisibleHeader: Bool { !visibleKinds(in: .header).isEmpty }

    // MARK: Persistence

    static func load() -> DockLayoutState {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let decoded = try? JSONDecoder().decode(DockLayoutState.self, from: data)
        else {
            return .stockDefault()
        }
        return decoded.migrated()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
    }

    /// Ensure stock providers exist in stacks after schema tweaks.
    private func migrated() -> DockLayoutState {
        var copy = self
        let stock = DockLayoutState.stockDefault()
        for region in DockRegion.allCases where region != .floating {
            if copy.stacks[region.rawValue] == nil {
                copy.stacks[region.rawValue] = stock.stacks[region.rawValue]
            }
        }
        for (k, v) in stock.home where copy.home[k] == nil {
            copy.home[k] = v
        }
        // Pre-agent-sidebar layouts decode with false/0 via Codable defaults missing —
        // clamp to sensible stock when ratio unset.
        if copy.agentSidebarWidthRatio <= 0.05 || copy.agentSidebarWidthRatio > 0.5 {
            copy.agentSidebarWidthRatio = stock.agentSidebarWidthRatio
        }
        // Classes browser is first-class left dock (ObjC / Swift) — promote if missing.
        let classes = ProviderKind.swiftClasses.rawValue
        var left = copy.kinds(in: .left)
        if !left.contains(.swiftClasses) {
            left.append(.swiftClasses)
            copy.setKinds(left, in: .left)
        }
        copy.hidden.removeAll { $0 == classes }
        copy.home[classes] = DockRegion.left.rawValue
        // Agent is never a dockable module — strip legacy stack/float entries.
        copy.removeFromAllStacks(.agent)
        copy.floating.removeAll { $0 == ProviderKind.agent.rawValue }
        if !copy.hidden.contains(ProviderKind.agent.rawValue) {
            copy.hidden.append(ProviderKind.agent.rawValue)
        }
        copy.home.removeValue(forKey: ProviderKind.agent.rawValue)
        return copy
    }
}

/// Transferable drag payload for provider title-bar redock.
struct ProviderDockDrag: Codable, Transferable, Hashable {
    let kindRaw: String

    var kind: ProviderKind? { ProviderKind(rawValue: kindRaw) }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

extension Notification.Name {
    static let ghidraVibeFloatProvider = Notification.Name("ghidra.vibe.dock.float")
    static let ghidraVibeUnfloatProvider = Notification.Name("ghidra.vibe.dock.unfloat")
}
