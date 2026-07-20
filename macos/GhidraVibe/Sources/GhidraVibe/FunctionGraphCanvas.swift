import AppKit
import SwiftUI

// MARK: - Model

struct FunctionGraphNode: Identifiable, Hashable, Sendable {
    var id: String
    var addr: String
    var end: String
    var label: String
    var kind: String
    var insns: [String]
    var truncated: Bool
}

struct FunctionGraphEdge: Hashable, Sendable {
    var from: String
    var to: String
    var type: String
}

struct FunctionGraphModel: Equatable, Sendable {
    var function: String = ""
    var entry: String = ""
    var nodes: [FunctionGraphNode] = []
    var edges: [FunctionGraphEdge] = []
    var bodySize: Int = 0

    var isEmpty: Bool { nodes.isEmpty }

    static func parse(from json: [String: Any]) -> FunctionGraphModel? {
        if json["error"] != nil { return nil }
        guard json["ok"] as? Bool != false else { return nil }

        if let nodeArr = json["nodes"] as? [[String: Any]], !nodeArr.isEmpty {
            return parseNative(json: json, nodeArr: nodeArr, edgeArr: (json["edges"] as? [[String: Any]]) ?? [])
        }

        if let blocks = json["basic_block_details"] as? [[String: Any]], !blocks.isEmpty {
            return parseAnalyzeControlFlow(json: json, blocks: blocks)
        }
        return nil
    }

    private static func parseNative(
        json: [String: Any],
        nodeArr: [[String: Any]],
        edgeArr: [[String: Any]]
    ) -> FunctionGraphModel {
        var nodes: [FunctionGraphNode] = []
        for n in nodeArr {
            let id = (n["id"] as? String) ?? (n["addr"] as? String) ?? ""
            guard !id.isEmpty else { continue }
            let addr = (n["addr"] as? String) ?? id
            nodes.append(
                FunctionGraphNode(
                    id: id,
                    addr: addr,
                    end: (n["end"] as? String) ?? addr,
                    label: (n["label"] as? String) ?? addr,
                    kind: (n["kind"] as? String) ?? "body",
                    insns: (n["insns"] as? [String]) ?? [],
                    truncated: (n["truncated"] as? Bool) ?? false
                )
            )
        }
        var edges: [FunctionGraphEdge] = []
        for e in edgeArr {
            guard let from = e["from"] as? String, let to = e["to"] as? String else { continue }
            edges.append(FunctionGraphEdge(from: from, to: to, type: (e["type"] as? String) ?? "flow"))
        }
        return FunctionGraphModel(
            function: (json["function"] as? String) ?? "",
            entry: (json["entry"] as? String) ?? "",
            nodes: nodes,
            edges: edges,
            bodySize: (json["body_size"] as? Int) ?? 0
        )
    }

    private static func parseAnalyzeControlFlow(json: [String: Any], blocks: [[String: Any]]) -> FunctionGraphModel {
        let entry = (json["entry_point"] as? String) ?? ""
        let fname = (json["function_name"] as? String) ?? ""
        var nodes: [FunctionGraphNode] = []
        for b in blocks {
            let addr = (b["address"] as? String) ?? ""
            guard !addr.isEmpty else { continue }
            let kind = addr == entry ? "entry" : ((b["type"] as? String) ?? "body")
            let size = b["size"] as? Int
            let succ = b["successors"] as? Int
            var insns: [String] = []
            if let size { insns.append("size \(size)") }
            if let succ { insns.append("successors \(succ)") }
            if (b["is_loop_header"] as? Bool) == true { insns.append("loop header") }
            nodes.append(
                FunctionGraphNode(
                    id: addr,
                    addr: addr,
                    end: addr,
                    label: kind == "entry" ? (fname.isEmpty ? addr : fname) : addr,
                    kind: kind == "entry" ? "entry" : "body",
                    insns: insns,
                    truncated: false
                )
            )
        }
        return FunctionGraphModel(
            function: fname,
            entry: entry,
            nodes: nodes,
            edges: [],
            bodySize: (json["size_bytes"] as? Int) ?? 0
        )
    }
}

struct GraphLayout {
    var positions: [String: CGPoint] = [:]
    var contentSize: CGSize = .zero
    var nodeSize: [String: CGSize] = [:]
}

enum FunctionGraphLayout {
    static let nodeWidth: CGFloat = 240
    static let minNodeHeight: CGFloat = 56
    static let hGap: CGFloat = 48
    static let vGap: CGFloat = 36
    static let pad: CGFloat = 40

    static func layout(_ model: FunctionGraphModel) -> GraphLayout {
        guard !model.nodes.isEmpty else { return GraphLayout() }
        let ids = model.nodes.map(\.id)
        let idSet = Set(ids)
        var succ: [String: [String]] = Dictionary(uniqueKeysWithValues: ids.map { ($0, []) })
        for e in model.edges where idSet.contains(e.from) && idSet.contains(e.to) {
            succ[e.from, default: []].append(e.to)
        }
        let entry = model.entry.isEmpty ? ids[0] : (idSet.contains(model.entry) ? model.entry : ids[0])

        var level: [String: Int] = [entry: 0]
        var queue = [entry]
        var qi = 0
        while qi < queue.count {
            let u = queue[qi]
            qi += 1
            let lu = level[u] ?? 0
            for v in succ[u] ?? [] where level[v] == nil {
                level[v] = lu + 1
                queue.append(v)
            }
        }
        for id in ids where level[id] == nil {
            level[id] = (level.values.max() ?? 0) + 1
        }

        var buckets: [Int: [String]] = [:]
        for id in ids {
            buckets[level[id] ?? 0, default: []].append(id)
        }
        for k in buckets.keys {
            buckets[k]?.sort { a, b in
                if a == entry { return true }
                if b == entry { return false }
                return a < b
            }
        }

        var nodeSize: [String: CGSize] = [:]
        for n in model.nodes {
            let lines = max(1, min(n.insns.count + 1, 8))
            let h = max(minNodeHeight, 28 + CGFloat(lines) * 14)
            nodeSize[n.id] = CGSize(width: nodeWidth, height: h)
        }

        var positions: [String: CGPoint] = [:]
        var maxW: CGFloat = pad * 2 + nodeWidth
        var maxH: CGFloat = pad
        let levels = buckets.keys.sorted()
        var y = pad
        for lv in levels {
            let row = buckets[lv] ?? []
            let rowH = row.map { nodeSize[$0]?.height ?? minNodeHeight }.max() ?? minNodeHeight
            let rowW = CGFloat(row.count) * nodeWidth + CGFloat(max(0, row.count - 1)) * hGap
            let targetW = max(maxW - pad * 2, rowW)
            var x = pad + max(0, (targetW - rowW) / 2)
            for id in row {
                let sz = nodeSize[id] ?? CGSize(width: nodeWidth, height: minNodeHeight)
                positions[id] = CGPoint(x: x, y: y)
                x += sz.width + hGap
            }
            maxW = max(maxW, pad + max(targetW, rowW) + pad)
            y += rowH + vGap
            maxH = y
        }
        maxH += pad

        return GraphLayout(positions: positions, contentSize: CGSize(width: maxW, height: maxH), nodeSize: nodeSize)
    }
}

// MARK: - AppKit canvas

final class FunctionGraphNSView: NSView {
    var model = FunctionGraphModel() {
        didSet {
            let graphKey = "\(model.function)|\(model.entry)|\(model.nodes.count)|\(model.edges.count)"
            if graphKey != lastGraphKey {
                lastGraphKey = graphKey
                positionOverrides.removeAll()
                needsCameraFit = true
            }
            relayout()
            needsDisplay = true
        }
    }
    var selectedId: String? {
        didSet { needsDisplay = true }
    }
    var onSelectAddress: ((String) -> Void)?

    private var layoutCache = GraphLayout()
    private var positionOverrides: [String: CGPoint] = [:]
    private var lastGraphKey = ""
    private var needsCameraFit = true
    private var magnification: CGFloat = 1
    private var pan = CGPoint.zero

    private enum DragKind {
        case none
        case pan(start: CGPoint, panAtStart: CGPoint)
        case node(id: String, originAtStart: CGPoint, mouseAtStart: CGPoint)
    }

    private var dragKind: DragKind = .none
    private var nodeDragMoved = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    private func relayout() {
        layoutCache = FunctionGraphLayout.layout(model)
        for (id, p) in positionOverrides {
            layoutCache.positions[id] = p
        }
        expandContentBounds()
        if needsCameraFit, bounds.width > 1, bounds.height > 1 {
            needsCameraFit = false
            fitInView()
        }
    }

    private func expandContentBounds() {
        var maxX = layoutCache.contentSize.width
        var maxY = layoutCache.contentSize.height
        for (id, origin) in layoutCache.positions {
            let sz = layoutCache.nodeSize[id]
                ?? CGSize(width: FunctionGraphLayout.nodeWidth, height: FunctionGraphLayout.minNodeHeight)
            maxX = max(maxX, origin.x + sz.width + FunctionGraphLayout.pad)
            maxY = max(maxY, origin.y + sz.height + FunctionGraphLayout.pad)
        }
        layoutCache.contentSize = CGSize(width: maxX, height: maxY)
    }

    private func localPoint(for event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func contentPoint(for event: NSEvent) -> CGPoint {
        let p = localPoint(for: event)
        return CGPoint(x: (p.x - pan.x) / magnification, y: (p.y - pan.y) / magnification)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: pan.x, y: pan.y)
        ctx.scaleBy(x: magnification, y: magnification)

        // Edges under nodes — port-aware routing + oriented arrowheads.
        for e in model.edges {
            guard let a = layoutCache.positions[e.from],
                  let b = layoutCache.positions[e.to],
                  let asz = layoutCache.nodeSize[e.from],
                  let bsz = layoutCache.nodeSize[e.to]
            else { continue }
            drawEdge(
                fromRect: CGRect(origin: a, size: asz),
                toRect: CGRect(origin: b, size: bsz),
                type: e.type,
                selfLoop: e.from == e.to
            )
        }

        for n in model.nodes {
            guard let origin = layoutCache.positions[n.id],
                  let sz = layoutCache.nodeSize[n.id]
            else { continue }
            drawNode(n, origin: origin, size: sz, selected: n.id == selectedId)
        }

        ctx.restoreGState()

        if model.isEmpty {
            let msg = "// Select a function, then Refresh Graph"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            (msg as NSString).draw(at: CGPoint(x: 16, y: 16), withAttributes: attrs)
        }
    }

    /// Pick exit/entry ports from geometry, curve between them, arrow along final direction.
    private func drawEdge(fromRect: CGRect, toRect: CGRect, type: String, selfLoop: Bool) {
        let stroke: NSColor
        var dashed = false
        var width: CGFloat = 1.4
        switch type {
        case "conditional":
            stroke = NSColor.systemOrange.withAlphaComponent(0.95)
            width = 1.6
        case "unconditional", "jump":
            stroke = NSColor.systemBlue.withAlphaComponent(0.9)
            width = 1.5
        case "fallthrough":
            stroke = NSColor.secondaryLabelColor.withAlphaComponent(0.75)
            width = 1.1
            dashed = true
        default:
            stroke = NSColor.labelColor.withAlphaComponent(0.6)
        }

        if selfLoop {
            let r = fromRect
            let start = CGPoint(x: r.maxX - 12, y: r.minY)
            let end = CGPoint(x: r.maxX, y: r.minY + 18)
            let c1 = CGPoint(x: r.maxX + 36, y: r.minY - 28)
            let c2 = CGPoint(x: r.maxX + 36, y: r.minY + 40)
            let path = NSBezierPath()
            path.move(to: start)
            path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
            stroke.setStroke()
            path.lineWidth = width
            if dashed { path.setLineDash([4, 3], count: 2, phase: 0) }
            path.stroke()
            drawArrowhead(at: end, direction: CGVector(dx: end.x - c2.x, dy: end.y - c2.y), color: stroke)
            return
        }

        let fromC = CGPoint(x: fromRect.midX, y: fromRect.midY)
        let toC = CGPoint(x: toRect.midX, y: toRect.midY)
        let dx = toC.x - fromC.x
        let dy = toC.y - fromC.y

        let start: CGPoint
        let end: CGPoint
        var c1: CGPoint
        var c2: CGPoint
        let bend: CGFloat = 28

        if abs(dy) >= abs(dx) * 0.85 {
            // Primarily vertical (normal CFG flow / back-edge).
            if dy >= 0 {
                start = CGPoint(x: fromRect.midX, y: fromRect.maxY)
                end = CGPoint(x: toRect.midX, y: toRect.minY)
                let midY = (start.y + end.y) / 2
                c1 = CGPoint(x: start.x, y: midY)
                c2 = CGPoint(x: end.x, y: midY)
            } else {
                start = CGPoint(x: fromRect.midX, y: fromRect.minY)
                end = CGPoint(x: toRect.midX, y: toRect.maxY)
                let midY = (start.y + end.y) / 2
                c1 = CGPoint(x: start.x, y: midY)
                c2 = CGPoint(x: end.x, y: midY)
            }
        } else {
            // Primarily horizontal (same-level / dragged sideways).
            if dx >= 0 {
                start = CGPoint(x: fromRect.maxX, y: fromRect.midY)
                end = CGPoint(x: toRect.minX, y: toRect.midY)
                let midX = (start.x + end.x) / 2
                c1 = CGPoint(x: midX, y: start.y)
                c2 = CGPoint(x: midX, y: end.y)
            } else {
                start = CGPoint(x: fromRect.minX, y: fromRect.midY)
                end = CGPoint(x: toRect.maxX, y: toRect.midY)
                let midX = (start.x + end.x) / 2
                c1 = CGPoint(x: midX, y: start.y)
                c2 = CGPoint(x: midX, y: end.y)
            }
            // Slight vertical bow so overlapping horizontals stay readable.
            if abs(start.y - end.y) < 2 {
                c1.y -= bend
                c2.y -= bend
            }
        }

        let path = NSBezierPath()
        path.move(to: start)
        path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
        stroke.setStroke()
        path.lineWidth = width
        if dashed { path.setLineDash([4, 3], count: 2, phase: 0) }
        path.stroke()

        drawArrowhead(
            at: end,
            direction: CGVector(dx: end.x - c2.x, dy: end.y - c2.y),
            color: stroke
        )
    }

    private func drawArrowhead(at tip: CGPoint, direction: CGVector, color: NSColor) {
        var dx = direction.dx
        var dy = direction.dy
        let len = hypot(dx, dy)
        if len < 0.001 {
            dx = 0
            dy = 1
        } else {
            dx /= len
            dy /= len
        }
        let size: CGFloat = 8
        let back = CGPoint(x: tip.x - dx * size, y: tip.y - dy * size)
        let px = -dy
        let py = dx
        let left = CGPoint(x: back.x + px * size * 0.55, y: back.y + py * size * 0.55)
        let right = CGPoint(x: back.x - px * size * 0.55, y: back.y - py * size * 0.55)
        let arrow = NSBezierPath()
        arrow.move(to: tip)
        arrow.line(to: left)
        arrow.line(to: right)
        arrow.close()
        color.withAlphaComponent(0.95).setFill()
        arrow.fill()
    }

    private func drawNode(_ n: FunctionGraphNode, origin: CGPoint, size: CGSize, selected: Bool) {
        let rect = CGRect(origin: origin, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        if n.kind == "entry" {
            NSColor.systemBlue.withAlphaComponent(0.12).setFill()
        } else {
            NSColor.textBackgroundColor.setFill()
        }
        path.fill()
        (selected ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = selected ? 2.0 : 1.0
        path.stroke()

        let padX: CGFloat = 8
        let maxTextW = max(12, size.width - padX * 2)
        let titleFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let insnFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.labelColor,
        ]
        let insnAttrs: [NSAttributedString.Key: Any] = [
            .font: insnFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        NSBezierPath(rect: rect.insetBy(dx: 3, dy: 3)).addClip()

        var y = origin.y + 8
        let title = n.kind == "entry" ? "\(n.label)  [\(n.addr)]" : n.addr
        Self.drawClippedLine(title, at: CGPoint(x: origin.x + padX, y: y), maxWidth: maxTextW, attributes: titleAttrs)
        y += 16

        let maxLines = max(0, Int((size.height - 28) / 14))
        for (i, line) in n.insns.prefix(maxLines).enumerated() {
            Self.drawClippedLine(
                line,
                at: CGPoint(x: origin.x + padX, y: y + CGFloat(i) * 14),
                maxWidth: maxTextW,
                attributes: insnAttrs
            )
        }
        if n.truncated || n.insns.count > maxLines {
            Self.drawClippedLine(
                "…",
                at: CGPoint(x: origin.x + padX, y: origin.y + size.height - 16),
                maxWidth: maxTextW,
                attributes: insnAttrs
            )
        }

        ctx.restoreGState()
    }

    private static func drawClippedLine(
        _ string: String,
        at point: CGPoint,
        maxWidth: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        var text = string
        if (string as NSString).size(withAttributes: attributes).width > maxWidth {
            let ellipsis = "…"
            var lo = 0
            var hi = string.count
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                let idx = string.index(string.startIndex, offsetBy: mid)
                let candidate = String(string[..<idx]) + ellipsis
                if (candidate as NSString).size(withAttributes: attributes).width <= maxWidth {
                    lo = mid
                } else {
                    hi = mid - 1
                }
            }
            let idx = string.index(string.startIndex, offsetBy: max(0, lo))
            text = String(string[..<idx]) + ellipsis
        }
        (text as NSString).draw(at: point, withAttributes: attributes)
    }

    private func hitTestNode(at contentPoint: CGPoint) -> FunctionGraphNode? {
        for n in model.nodes.reversed() {
            guard let o = layoutCache.positions[n.id], let sz = layoutCache.nodeSize[n.id] else { continue }
            if CGRect(origin: o, size: sz).contains(contentPoint) { return n }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let local = localPoint(for: event)
        let content = contentPoint(for: event)
        nodeDragMoved = false
        if let n = hitTestNode(at: content), let origin = layoutCache.positions[n.id] {
            selectedId = n.id
            needsDisplay = true
            dragKind = .node(id: n.id, originAtStart: origin, mouseAtStart: content)
            return
        }
        dragKind = .pan(start: local, panAtStart: pan)
    }

    override func mouseDragged(with event: NSEvent) {
        switch dragKind {
        case .none:
            return
        case let .pan(start, panAtStart):
            let local = localPoint(for: event)
            pan = CGPoint(x: panAtStart.x + (local.x - start.x), y: panAtStart.y + (local.y - start.y))
            needsDisplay = true
        case let .node(id, originAtStart, mouseAtStart):
            let content = contentPoint(for: event)
            let dx = content.x - mouseAtStart.x
            let dy = content.y - mouseAtStart.y
            if hypot(dx, dy) > 3 { nodeDragMoved = true }
            var origin = CGPoint(x: originAtStart.x + dx, y: originAtStart.y + dy)
            origin.x = max(4, origin.x)
            origin.y = max(4, origin.y)
            positionOverrides[id] = origin
            layoutCache.positions[id] = origin
            expandContentBounds()
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let kind = dragKind
        dragKind = .none
        if case let .node(id, _, _) = kind, !nodeDragMoved {
            if let n = model.nodes.first(where: { $0.id == id }) {
                onSelectAddress?(n.addr)
            }
        }
    }

    override func magnify(with event: NSEvent) {
        magnification = max(0.25, min(2.5, magnification * (1 + event.magnification)))
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            let factor: CGFloat = event.scrollingDeltaY > 0 ? 1.08 : 0.92
            magnification = max(0.25, min(2.5, magnification * factor))
        } else {
            pan.x += event.scrollingDeltaX
            pan.y += event.scrollingDeltaY
        }
        needsDisplay = true
    }

    func fitInView() {
        let size = layoutCache.contentSize
        guard size.width > 1, size.height > 1, bounds.width > 1, bounds.height > 1 else { return }
        let sx = (bounds.width - 24) / size.width
        let sy = (bounds.height - 24) / size.height
        magnification = max(0.25, min(1.0, min(sx, sy)))
        let contentW = size.width * magnification
        let contentH = size.height * magnification
        pan = CGPoint(
            x: max(0, (bounds.width - contentW) / 2),
            y: max(0, (bounds.height - contentH) / 2)
        )
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        // Fit once when the view first gets a real size (not on every resize thrash).
        if needsCameraFit, bounds.width > 1, bounds.height > 1 {
            needsCameraFit = false
            fitInView()
        }
    }
}

struct FunctionGraphCanvas: NSViewRepresentable {
    var model: FunctionGraphModel
    var selectedId: String?
    var onSelectAddress: (String) -> Void

    func makeNSView(context: Context) -> FunctionGraphNSView {
        let v = FunctionGraphNSView()
        v.model = model
        v.selectedId = selectedId
        v.onSelectAddress = onSelectAddress
        return v
    }

    func updateNSView(_ nsView: FunctionGraphNSView, context: Context) {
        nsView.onSelectAddress = onSelectAddress
        if nsView.model.function != model.function
            || nsView.model.entry != model.entry
            || nsView.model.nodes.count != model.nodes.count
            || nsView.model.edges.count != model.edges.count
            || nsView.model != model
        {
            nsView.model = model
        }
        nsView.selectedId = selectedId
    }
}
