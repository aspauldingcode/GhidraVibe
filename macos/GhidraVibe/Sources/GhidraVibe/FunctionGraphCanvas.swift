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
    /// Wider gutters so orthogonal edges stay in channels (IDA / Binja style).
    static let hGap: CGFloat = 96
    static let vGap: CGFloat = 72
    static let pad: CGFloat = 56
    /// Minimum empty space between node rects while dragging / after resolve.
    static let nodeSeparation: CGFloat = 32

    static func layout(_ model: FunctionGraphModel) -> GraphLayout {
        guard !model.nodes.isEmpty else { return GraphLayout() }
        let ids = model.nodes.map(\.id)
        let idSet = Set(ids)
        var succ: [String: [String]] = Dictionary(uniqueKeysWithValues: ids.map { ($0, []) })
        var pred: [String: [String]] = Dictionary(uniqueKeysWithValues: ids.map { ($0, []) })
        for e in model.edges where idSet.contains(e.from) && idSet.contains(e.to) {
            succ[e.from, default: []].append(e.to)
            pred[e.to, default: []].append(e.from)
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

        var nodeSize: [String: CGSize] = [:]
        for n in model.nodes {
            let lines = max(1, min(n.insns.count + 1, 8))
            let h = max(minNodeHeight, 28 + CGFloat(lines) * 14)
            nodeSize[n.id] = CGSize(width: nodeWidth, height: h)
        }

        // Barycenter ordering per layer (reduces crossings before routing).
        var positions: [String: CGPoint] = [:]
        var maxW: CGFloat = pad * 2 + nodeWidth
        var maxH: CGFloat = pad
        let levels = buckets.keys.sorted()
        var y = pad
        var prevOrder: [String] = []
        for lv in levels {
            var row = buckets[lv] ?? []
            if lv == 0 {
                row.sort { a, b in
                    if a == entry { return true }
                    if b == entry { return false }
                    return a < b
                }
            } else if !prevOrder.isEmpty {
                let rank = Dictionary(uniqueKeysWithValues: prevOrder.enumerated().map { ($0.element, $0.offset) })
                row.sort { a, b in
                    let ba = (pred[a] ?? []).compactMap { rank[$0] }.reduce(0, +)
                    let bb = (pred[b] ?? []).compactMap { rank[$0] }.reduce(0, +)
                    let ca = max(1, (pred[a] ?? []).filter { rank[$0] != nil }.count)
                    let cb = max(1, (pred[b] ?? []).filter { rank[$0] != nil }.count)
                    let avgA = Double(ba) / Double(ca)
                    let avgB = Double(bb) / Double(cb)
                    if avgA != avgB { return avgA < avgB }
                    return a < b
                }
            }
            buckets[lv] = row
            prevOrder = row

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

// MARK: - Flowchart edge router (Ghidra / IDA style)

/// Orthogonal CFG edges: exit bottom → enter top when possible (1 / 3 / 5 segments),
/// small filleted corners, sparse hop samples. Designed for readable, cheap redraw.
enum GraphEdgeRouter {
    struct Cubic: Sendable {
        var p0: CGPoint
        var c1: CGPoint
        var c2: CGPoint
        var p1: CGPoint
    }

    struct RoutedEdge: Sendable {
        var cubics: [Cubic]
        var tip: CGPoint
        var direction: CGVector
        /// Sparse polyline samples for hop detection only.
        var samples: [CGPoint]
        var start: CGPoint
        var type: String
    }

    private static let stub: CGFloat = 12
    private static let approachLen: CGFloat = 14
    private static let cornerR: CGFloat = 6
    private static let circleKappa: CGFloat = 0.5522847498
    static let headLen: CGFloat = 9
    static let hopGapHalf: CGFloat = 5.5
    /// Max hops computed per edge (keeps draw cheap).
    static let maxHopsPerEdge = 2

    static func route(
        from fromRect: CGRect,
        to toRect: CGRect,
        obstacles: [CGRect],
        selfLoop: Bool,
        type: String,
        exitFan: CGFloat = 0,
        entryFan: CGFloat = 0
    ) -> RoutedEdge {
        if selfLoop { return selfLoopRoute(fromRect, type: type) }

        let inflated = obstacles.map { $0.insetBy(dx: -10, dy: -10) }
        let forward = toRect.midY >= fromRect.midY - 8

        // Flowchart ports (Ghidra OrthogonalEdgeRouter): out bottom, in top for forward edges.
        let start: CGPoint
        let tip: CGPoint
        let out: CGVector
        let dir: CGVector
        if forward {
            start = CGPoint(x: fromRect.midX + exitFan, y: fromRect.maxY)
            tip = CGPoint(x: toRect.midX + entryFan, y: toRect.minY)
            out = CGVector(dx: 0, dy: 1)
            dir = CGVector(dx: 0, dy: 1) // into tip from above
        } else {
            // Back-edge: leave top, enter bottom (C-shape).
            start = CGPoint(x: fromRect.midX + exitFan, y: fromRect.minY)
            tip = CGPoint(x: toRect.midX + entryFan, y: toRect.maxY)
            out = CGVector(dx: 0, dy: -1)
            dir = CGVector(dx: 0, dy: -1)
        }

        let base = CGPoint(x: tip.x - dir.dx * headLen, y: tip.y - dir.dy * headLen)
        let approach = CGPoint(x: base.x - dir.dx * approachLen, y: base.y - dir.dy * approachLen)
        let exit = CGPoint(x: start.x + out.dx * stub, y: start.y + out.dy * stub)

        let articulations = flowchartArticulations(
            exit: exit,
            approach: approach,
            out: out,
            forward: forward,
            fromRect: fromRect,
            toRect: toRect,
            obstacles: inflated
        )

        let body = filletedPolyline(articulations)
        let cubics =
            [straight(from: start, to: exit, dir: out)]
            + body
            + [straight(from: approach, to: base, dir: dir)]

        return RoutedEdge(
            cubics: cubics,
            tip: tip,
            direction: dir,
            samples: sampleSparse(cubics),
            start: start,
            type: type
        )
    }

    // MARK: flowchart articulations (1 / 3 / 5 segments)

    /// Orthogonal waypoints from `exit` through to `approach` (inclusive ends).
    private static func flowchartArticulations(
        exit: CGPoint,
        approach: CGPoint,
        out: CGVector,
        forward: Bool,
        fromRect: CGRect,
        toRect: CGRect,
        obstacles: [CGRect]
    ) -> [CGPoint] {
        // 1-segment: same column, clear vertical corridor.
        if abs(exit.x - approach.x) < 6 {
            let direct = [exit, approach]
            if !polylineHits(direct, obstacles: obstacles) { return direct }
        }

        if forward {
            // 3-segment: down → horizontal → down (Ghidra type 2).
            let gapTop = exit.y
            let gapBot = approach.y
            if gapBot > gapTop + 8 {
                let candidates: [CGFloat] = [
                    gapTop + (gapBot - gapTop) * 0.45,
                    gapTop + 18,
                    gapBot - 18,
                    (gapTop + gapBot) * 0.5,
                ]
                for midY in candidates where midY > gapTop + 4 && midY < gapBot - 4 {
                    let pts = [
                        exit,
                        CGPoint(x: exit.x, y: midY),
                        CGPoint(x: approach.x, y: midY),
                        approach,
                    ]
                    if !polylineHits(pts, obstacles: obstacles) { return pts }
                }
            }

            // 5-segment: down → side column → down past blockers → to target column → down.
            let left = min(fromRect.minX, toRect.minX) - 28
            let right = max(fromRect.maxX, toRect.maxX) + 28
            for col in [left, right, left - 40, right + 40] {
                let y1 = exit.y + 10
                let y2 = approach.y - 10
                guard y2 > y1 + 8 else { continue }
                let pts = [
                    exit,
                    CGPoint(x: exit.x, y: y1),
                    CGPoint(x: col, y: y1),
                    CGPoint(x: col, y: y2),
                    CGPoint(x: approach.x, y: y2),
                    approach,
                ]
                if !polylineHits(pts, obstacles: obstacles) { return pts }
            }
        } else {
            // Back-edge C: up → outward column → down/up to approach row → in.
            let left = min(fromRect.minX, toRect.minX) - 36
            let right = max(fromRect.maxX, toRect.maxX) + 36
            let yTop = min(exit.y, approach.y) - 24
            for col in [right, left] {
                let pts = [
                    exit,
                    CGPoint(x: exit.x, y: yTop),
                    CGPoint(x: col, y: yTop),
                    CGPoint(x: col, y: approach.y),
                    approach,
                ]
                if !polylineHits(pts, obstacles: obstacles) { return pts }
            }
        }

        // Last resort: simple 3-bend ignoring soft collisions (still orthogonal).
        let midY = (exit.y + approach.y) * 0.5
        return [
            exit,
            CGPoint(x: exit.x, y: midY),
            CGPoint(x: approach.x, y: midY),
            approach,
        ]
    }

    /// Convert orthogonal polyline into straight legs + small filleted corners.
    private static func filletedPolyline(_ pts: [CGPoint]) -> [Cubic] {
        guard pts.count >= 2 else { return [] }
        if pts.count == 2 {
            let d = unit(CGVector(dx: pts[1].x - pts[0].x, dy: pts[1].y - pts[0].y))
            return [straight(from: pts[0], to: pts[1], dir: d)]
        }
        var cubics: [Cubic] = []
        var cursor = pts[0]
        for i in 1 ..< (pts.count - 1) {
            let prev = pts[i - 1]
            let corner = pts[i]
            let next = pts[i + 1]
            let uIn = unit(CGVector(dx: corner.x - prev.x, dy: corner.y - prev.y))
            let uOut = unit(CGVector(dx: next.x - corner.x, dy: next.y - corner.y))
            let dIn = hypot(corner.x - cursor.x, corner.y - cursor.y)
            let dOut = hypot(next.x - corner.x, next.y - corner.y)
            let R = min(cornerR, dIn * 0.4, dOut * 0.4)
            if R >= 4, abs(uIn.dx * uOut.dx + uIn.dy * uOut.dy) < 0.25 {
                let before = CGPoint(x: corner.x - uIn.dx * R, y: corner.y - uIn.dy * R)
                let after = CGPoint(x: corner.x + uOut.dx * R, y: corner.y + uOut.dy * R)
                if hypot(before.x - cursor.x, before.y - cursor.y) > 1 {
                    cubics.append(straight(from: cursor, to: before, dir: uIn))
                }
                cubics.append(fillet(from: before, to: after, dirIn: uIn, dirOut: uOut, radius: R))
                cursor = after
            } else {
                // Degenerate: go to corner without fillet.
                if hypot(corner.x - cursor.x, corner.y - cursor.y) > 1 {
                    cubics.append(straight(from: cursor, to: corner, dir: uIn))
                }
                cursor = corner
            }
        }
        let last = pts[pts.count - 1]
        let u = unit(CGVector(dx: last.x - cursor.x, dy: last.y - cursor.y))
        if hypot(last.x - cursor.x, last.y - cursor.y) > 1 {
            cubics.append(straight(from: cursor, to: last, dir: u))
        }
        return cubics
    }

    private static func straight(from a: CGPoint, to b: CGPoint, dir: CGVector) -> Cubic {
        let d = max(hypot(b.x - a.x, b.y - a.y), 1)
        let pull = min(d / 3, 12)
        let u = unit(dir)
        return Cubic(
            p0: a,
            c1: CGPoint(x: a.x + u.dx * pull, y: a.y + u.dy * pull),
            c2: CGPoint(x: b.x - u.dx * pull, y: b.y - u.dy * pull),
            p1: b
        )
    }

    private static func fillet(
        from before: CGPoint,
        to after: CGPoint,
        dirIn: CGVector,
        dirOut: CGVector,
        radius: CGFloat
    ) -> Cubic {
        let k = radius * circleKappa
        return Cubic(
            p0: before,
            c1: CGPoint(x: before.x + dirIn.dx * k, y: before.y + dirIn.dy * k),
            c2: CGPoint(x: after.x - dirOut.dx * k, y: after.y - dirOut.dy * k),
            p1: after
        )
    }

    private static func selfLoopRoute(_ r: CGRect, type: String) -> RoutedEdge {
        let start = CGPoint(x: r.maxX - 10, y: r.minY)
        let tip = CGPoint(x: r.maxX, y: r.minY + 14)
        let dir = unit(CGVector(dx: 0.45, dy: 0.9))
        let base = CGPoint(x: tip.x - dir.dx * headLen, y: tip.y - dir.dy * headLen)
        let c = Cubic(
            p0: start,
            c1: CGPoint(x: r.maxX + 18, y: r.minY - 12),
            c2: CGPoint(x: r.maxX + 20, y: r.minY + 16),
            p1: base
        )
        return RoutedEdge(
            cubics: [c], tip: tip, direction: dir, samples: sampleSparse([c]), start: start, type: type
        )
    }

    // MARK: geometry

    private static func unit(_ v: CGVector) -> CGVector {
        let len = hypot(v.dx, v.dy)
        if len < 1e-4 { return CGVector(dx: 0, dy: 1) }
        return CGVector(dx: v.dx / len, dy: v.dy / len)
    }

    private static func polylineHits(_ pts: [CGPoint], obstacles: [CGRect]) -> Bool {
        guard pts.count >= 2 else { return false }
        for i in 0 ..< (pts.count - 1) {
            if segmentHitsAny(pts[i], pts[i + 1], obstacles) { return true }
        }
        return false
    }

    private static func segmentHitsAny(_ a: CGPoint, _ b: CGPoint, _ obstacles: [CGRect]) -> Bool {
        let steps = max(4, Int(hypot(b.x - a.x, b.y - a.y) / 12))
        for i in 1 ..< steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            for r in obstacles where r.contains(p) { return true }
        }
        return false
    }

    static func bezierPoint(_ c: Cubic, t: CGFloat) -> CGPoint {
        let u = 1 - t
        let uu = u * u
        let tt = t * t
        return CGPoint(
            x: uu * u * c.p0.x + 3 * uu * t * c.c1.x + 3 * u * tt * c.c2.x + tt * t * c.p1.x,
            y: uu * u * c.p0.y + 3 * uu * t * c.c1.y + 3 * u * tt * c.c2.y + tt * t * c.p1.y
        )
    }

    /// Sparse samples (~8–12 / cubic) — enough for hops, cheap for O(E²).
    private static func sampleSparse(_ cubics: [Cubic]) -> [CGPoint] {
        var pts: [CGPoint] = []
        for c in cubics {
            let n = 8
            for i in 0 ... n {
                let p = bezierPoint(c, t: CGFloat(i) / CGFloat(n))
                if let last = pts.last, hypot(last.x - p.x, last.y - p.y) < 2 { continue }
                pts.append(p)
            }
        }
        return pts
    }

    static func pointAndTangent(along samples: [CGPoint], distance: CGFloat) -> (CGPoint, CGVector)? {
        guard samples.count >= 2 else { return nil }
        var remaining = max(0, distance)
        for i in 0 ..< (samples.count - 1) {
            let a = samples[i], b = samples[i + 1]
            let seg = hypot(b.x - a.x, b.y - a.y)
            if seg < 1e-4 { continue }
            if remaining <= seg {
                let t = remaining / seg
                return (
                    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
                    CGVector(dx: (b.x - a.x) / seg, dy: (b.y - a.y) / seg)
                )
            }
            remaining -= seg
        }
        let a = samples[samples.count - 2], b = samples[samples.count - 1]
        let seg = max(hypot(b.x - a.x, b.y - a.y), 1e-4)
        return (b, CGVector(dx: (b.x - a.x) / seg, dy: (b.y - a.y) / seg))
    }

    static func arcLength(of samples: [CGPoint]) -> [CGFloat] {
        var dists: [CGFloat] = [0]
        guard samples.count >= 2 else { return dists }
        for i in 1 ..< samples.count {
            dists.append(dists[i - 1] + hypot(samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y))
        }
        return dists
    }

    static func closestDistance(along samples: [CGPoint], dists: [CGFloat], to point: CGPoint) -> CGFloat {
        guard !samples.isEmpty else { return 0 }
        var bestI = 0
        var bestD = CGFloat.greatestFiniteMagnitude
        for (i, p) in samples.enumerated() {
            let d = hypot(p.x - point.x, p.y - point.y)
            if d < bestD { bestD = d; bestI = i }
        }
        return dists[min(bestI, dists.count - 1)]
    }

    /// Crossing with AABB prune (much cheaper than dense Bezier hops).
    static func crossing(of a: [CGPoint], and b: [CGPoint]) -> CGPoint? {
        guard a.count >= 2, b.count >= 2 else { return nil }
        let ab = bounds(a), bb = bounds(b)
        guard ab.insetBy(dx: -2, dy: -2).intersects(bb.insetBy(dx: -2, dy: -2)) else { return nil }
        for i in 0 ..< (a.count - 1) {
            let a0 = a[i], a1 = a[i + 1]
            let segA = CGRect(
                x: min(a0.x, a1.x), y: min(a0.y, a1.y),
                width: abs(a1.x - a0.x), height: abs(a1.y - a0.y)
            ).insetBy(dx: -1, dy: -1)
            for j in 0 ..< (b.count - 1) {
                let b0 = b[j], b1 = b[j + 1]
                let segB = CGRect(
                    x: min(b0.x, b1.x), y: min(b0.y, b1.y),
                    width: abs(b1.x - b0.x), height: abs(b1.y - b0.y)
                ).insetBy(dx: -1, dy: -1)
                guard segA.intersects(segB) else { continue }
                if let p = segmentIntersection(a0, a1, b0, b1) { return p }
            }
        }
        return nil
    }

    private static func bounds(_ pts: [CGPoint]) -> CGRect {
        guard let first = pts.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in pts.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func segmentIntersection(
        _ p1: CGPoint, _ p2: CGPoint,
        _ q1: CGPoint, _ q2: CGPoint
    ) -> CGPoint? {
        let r = CGPoint(x: p2.x - p1.x, y: p2.y - p1.y)
        let s = CGPoint(x: q2.x - q1.x, y: q2.y - q1.y)
        let den = r.x * s.y - r.y * s.x
        if abs(den) < 1e-6 { return nil }
        // Skip near-parallel axis overlaps (shared corridors) — only true crossings.
        let parallelish = abs(r.x * s.x + r.y * s.y) > 0.95 * hypot(r.x, r.y) * hypot(s.x, s.y)
        if parallelish { return nil }
        let qp = CGPoint(x: q1.x - p1.x, y: q1.y - p1.y)
        let t = (qp.x * s.y - qp.y * s.x) / den
        let u = (qp.x * r.y - qp.y * r.x) / den
        if t > 0.12, t < 0.88, u > 0.12, u < 0.88 {
            return CGPoint(x: p1.x + t * r.x, y: p1.y + t * r.y)
        }
        return nil
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
                panLocked = false
            }
            relayout()
            invalidateRoutes()
            needsDisplay = true
        }
    }
    var selectedId: String? {
        didSet { needsDisplay = true } // selection chrome only — keep cached routes
    }
    var onSelectAddress: ((String) -> Void)?

    private var layoutCache = GraphLayout()
    private var positionOverrides: [String: CGPoint] = [:]
    private var lastGraphKey = ""
    private var needsCameraFit = true
    private var magnification: CGFloat = 1
    private var pan = CGPoint.zero
    private var panLocked = false
    /// Routes rebuilt only when layout / model / node drag changes — not on pan/zoom.
    private var cachedRoutes: [GraphEdgeRouter.RoutedEdge] = []
    private var cachedHops: [[CGPoint]] = []
    private var routesDirty = true

    private enum DragKind {
        case none
        case pan(start: CGPoint, panAtStart: CGPoint)
        case node(id: String, originAtStart: CGPoint, mouseAtStart: CGPoint)
        case minimap
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
        resolveAllNodeOverlaps()
        expandContentBounds()
        if needsCameraFit, bounds.width > 1, bounds.height > 1 {
            needsCameraFit = false
            fitInView()
        }
        clampPan()
        invalidateRoutes()
    }

    private func invalidateRoutes() {
        routesDirty = true
    }

    private func rebuildRoutesIfNeeded() {
        guard routesDirty else { return }
        routesDirty = false

        let nodeRects: [String: CGRect] = Dictionary(uniqueKeysWithValues: model.nodes.compactMap { n in
            guard let o = layoutCache.positions[n.id], let sz = layoutCache.nodeSize[n.id] else { return nil }
            return (n.id, CGRect(origin: o, size: sz))
        })
        let exitFans = portFans(outgoing: true)
        let entryFans = portFans(outgoing: false)

        var routes: [GraphEdgeRouter.RoutedEdge] = []
        routes.reserveCapacity(model.edges.count)
        for e in model.edges {
            guard let fromRect = nodeRects[e.from], let toRect = nodeRects[e.to] else { continue }
            let obstacles = nodeRects.compactMap { id, rect -> CGRect? in
                (id == e.from || id == e.to) ? nil : rect
            }
            let key = "\(e.from)->\(e.to)|\(e.type)"
            routes.append(
                GraphEdgeRouter.route(
                    from: fromRect,
                    to: toRect,
                    obstacles: obstacles,
                    selfLoop: e.from == e.to,
                    type: e.type,
                    exitFan: exitFans[key] ?? 0,
                    entryFan: entryFans[key] ?? 0
                )
            )
        }

        var hopPoints: [[CGPoint]] = Array(repeating: [], count: routes.count)
        // Cap work on huge graphs — hop bridges are polish, not required for correctness.
        if routes.count > 1, routes.count <= 64 {
            for i in 0 ..< routes.count {
                for j in (i + 1) ..< routes.count {
                    guard hopPoints[j].count < GraphEdgeRouter.maxHopsPerEdge else { continue }
                    if let p = GraphEdgeRouter.crossing(of: routes[i].samples, and: routes[j].samples) {
                        hopPoints[j].append(p)
                    }
                }
            }
        }
        cachedRoutes = routes
        cachedHops = hopPoints
    }

    private func expandContentBounds() {
        var maxX = layoutCache.contentSize.width
        var maxY = layoutCache.contentSize.height
        var minX: CGFloat = 0
        var minY: CGFloat = 0
        for (id, origin) in layoutCache.positions {
            let sz = layoutCache.nodeSize[id]
                ?? CGSize(width: FunctionGraphLayout.nodeWidth, height: FunctionGraphLayout.minNodeHeight)
            minX = min(minX, origin.x)
            minY = min(minY, origin.y)
            maxX = max(maxX, origin.x + sz.width + FunctionGraphLayout.pad)
            maxY = max(maxY, origin.y + sz.height + FunctionGraphLayout.pad)
        }
        // Keep origin non-negative for camera math.
        if minX < 0 || minY < 0 {
            let ox = minX < 0 ? -minX + FunctionGraphLayout.pad : 0
            let oy = minY < 0 ? -minY + FunctionGraphLayout.pad : 0
            if ox > 0 || oy > 0 {
                for id in layoutCache.positions.keys {
                    layoutCache.positions[id]?.x += ox
                    layoutCache.positions[id]?.y += oy
                    if var o = positionOverrides[id] {
                        o.x += ox
                        o.y += oy
                        positionOverrides[id] = o
                    }
                }
                maxX += ox
                maxY += oy
            }
        }
        layoutCache.contentSize = CGSize(width: max(maxX, 120), height: max(maxY, 120))
    }

    private func localPoint(for event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func contentPoint(for event: NSEvent) -> CGPoint {
        let p = localPoint(for: event)
        return CGPoint(x: (p.x - pan.x) / magnification, y: (p.y - pan.y) / magnification)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        VibeChrome.ProviderSurface.nsControl.setFill()
        bounds.fill()

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: pan.x, y: pan.y)
        ctx.scaleBy(x: magnification, y: magnification)

        rebuildRoutesIfNeeded()
        let routes = cachedRoutes
        let hopPoints = cachedHops

        // Edges under nodes (flowchart orthogonal).
        for (idx, route) in routes.enumerated() {
            let hops = idx < hopPoints.count ? hopPoints[idx] : []
            drawRoutedEdge(route, hops: hops)
        }

        for n in model.nodes {
            guard let origin = layoutCache.positions[n.id],
                  let sz = layoutCache.nodeSize[n.id]
            else { continue }
            drawNode(n, origin: origin, size: sz, selected: n.id == selectedId)
        }

        ctx.restoreGState()

        drawHUD()

        if model.isEmpty {
            let msg = "// Select a function, then Refresh Graph"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: VibeChrome.ProviderSurface.nsSecondary,
            ]
            (msg as NSString).draw(at: CGPoint(x: 16, y: 16), withAttributes: attrs)
        }
    }

    private func portFans(outgoing: Bool) -> [String: CGFloat] {
        var groups: [String: [Int]] = [:]
        for (i, e) in model.edges.enumerated() {
            let key = outgoing ? e.from : e.to
            groups[key, default: []].append(i)
        }
        var result: [String: CGFloat] = [:]
        let spacing: CGFloat = 12
        for (_, indices) in groups {
            let n = indices.count
            guard n > 1 else { continue }
            for (k, ei) in indices.enumerated() {
                let e = model.edges[ei]
                let edgeKey = "\(e.from)->\(e.to)|\(e.type)"
                let offset = CGFloat(k) - CGFloat(n - 1) / 2
                result[edgeKey] = offset * spacing
            }
        }
        return result
    }

    private func edgeColor(type: String) -> (NSColor, CGFloat, Bool) {
        let t = type.lowercased()
        // Binary Ninja / IDA-like branch coloring.
        if t.contains("true") || t == "conditional_true" {
            return (VibeChrome.ProviderSurface.nsSuccess.withAlphaComponent(0.92), 1.55, false)
        }
        if t.contains("false") || t == "conditional_false" {
            return (VibeChrome.ProviderSurface.nsError.withAlphaComponent(0.88), 1.55, false)
        }
        switch t {
        case "conditional":
            return (VibeChrome.ProviderSurface.nsWarning.withAlphaComponent(0.9), 1.45, false)
        case "unconditional", "jump", "branch":
            return (VibeChrome.ProviderSurface.nsAccent.withAlphaComponent(0.88), 1.4, false)
        case "fallthrough", "fall_through":
            return (VibeChrome.ProviderSurface.nsSecondary.withAlphaComponent(0.7), 1.1, true)
        default:
            return (VibeChrome.ProviderSurface.nsForeground.withAlphaComponent(0.55), 1.25, false)
        }
    }

    private func drawRoutedEdge(_ route: GraphEdgeRouter.RoutedEdge, hops: [CGPoint]) {
        let (stroke, width, dashed) = edgeColor(type: route.type)
        guard let first = route.cubics.first else { return }

        let samples = route.samples
        let dists = GraphEdgeRouter.arcLength(of: samples)
        let totalLen = dists.last ?? 0
        let gapHalf = GraphEdgeRouter.hopGapHalf

        // Build cleared gaps on the *stem* (do not draw the chord under the bridge).
        struct Gap {
            var d0: CGFloat
            var d1: CGFloat
        }
        var gaps: [Gap] = []
        if totalLen > gapHalf * 2 + 4 {
            for hop in hops {
                let mid = GraphEdgeRouter.closestDistance(along: samples, dists: dists, to: hop)
                let d0 = max(1, mid - gapHalf)
                let d1 = min(totalLen - 1, mid + gapHalf)
                if d1 - d0 >= 3 {
                    gaps.append(Gap(d0: d0, d1: d1))
                }
            }
            gaps.sort { $0.d0 < $1.d0 }
            // Merge overlaps.
            var merged: [Gap] = []
            for g in gaps {
                if let last = merged.last, g.d0 <= last.d1 + 1 {
                    merged[merged.count - 1].d1 = max(last.d1, g.d1)
                } else {
                    merged.append(g)
                }
            }
            gaps = merged
        }

        stroke.setStroke()
        if gaps.isEmpty {
            let path = NSBezierPath()
            path.move(to: first.p0)
            for c in route.cubics {
                path.curve(to: c.p1, controlPoint1: c.c1, controlPoint2: c.c2)
            }
            path.lineWidth = width
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            if dashed { path.setLineDash([5, 3], count: 2, phase: 0) }
            path.stroke()
        } else {
            // Stroke densified samples with hard gaps — bridge arc fills the hole.
            let path = NSBezierPath()
            var penDown = false
            for i in 0 ..< samples.count {
                let d = dists[i]
                let inGap = gaps.contains { d >= $0.d0 && d <= $0.d1 }
                if inGap {
                    penDown = false
                    continue
                }
                if !penDown {
                    path.move(to: samples[i])
                    penDown = true
                } else {
                    path.line(to: samples[i])
                }
            }
            path.lineWidth = width
            path.lineJoinStyle = .round
            path.lineCapStyle = .butt
            if dashed { path.setLineDash([5, 3], count: 2, phase: 0) }
            path.stroke()

            for g in gaps {
                drawHopBridge(
                    along: samples,
                    fromDistance: g.d0,
                    toDistance: g.d1,
                    color: stroke,
                    width: width
                )
            }
        }

        let headHalf: CGFloat = 5.2
        let base = CGPoint(
            x: route.tip.x - route.direction.dx * GraphEdgeRouter.headLen,
            y: route.tip.y - route.direction.dy * GraphEdgeRouter.headLen
        )
        drawArrowhead(tip: route.tip, base: base, direction: route.direction, halfWidth: headHalf, color: stroke)
    }

    /// Circuit-style hop: arc between gap endpoints only (nothing drawn under the bridge).
    private func drawHopBridge(
        along samples: [CGPoint],
        fromDistance d0: CGFloat,
        toDistance d1: CGFloat,
        color: NSColor,
        width: CGFloat
    ) {
        guard let (p0, t0) = GraphEdgeRouter.pointAndTangent(along: samples, distance: d0),
              let (p1, t1) = GraphEdgeRouter.pointAndTangent(along: samples, distance: d1)
        else { return }
        let tang = CGVector(
            dx: (t0.dx + t1.dx) * 0.5,
            dy: (t0.dy + t1.dy) * 0.5
        )
        let tlen = hypot(tang.dx, tang.dy)
        let ux = tlen > 1e-4 ? tang.dx / tlen : 1
        let uy = tlen > 1e-4 ? tang.dy / tlen : 0
        let nx = -uy
        let ny = ux
        let chord = hypot(p1.x - p0.x, p1.y - p0.y)
        let rise = max(4.5, min(7.5, chord * 0.4))
        let hop = NSBezierPath()
        hop.move(to: p0)
        hop.curve(
            to: p1,
            controlPoint1: CGPoint(
                x: p0.x + ux * chord * 0.25 + nx * rise,
                y: p0.y + uy * chord * 0.25 + ny * rise
            ),
            controlPoint2: CGPoint(
                x: p1.x - ux * chord * 0.25 + nx * rise,
                y: p1.y - uy * chord * 0.25 + ny * rise
            )
        )
        color.setStroke()
        hop.lineWidth = width
        hop.lineCapStyle = .round
        hop.stroke()
    }

    private func drawArrowhead(
        tip: CGPoint,
        base: CGPoint,
        direction: CGVector,
        halfWidth: CGFloat,
        color: NSColor
    ) {
        let px = -direction.dy
        let py = direction.dx
        let left = CGPoint(x: base.x + px * halfWidth, y: base.y + py * halfWidth)
        let right = CGPoint(x: base.x - px * halfWidth, y: base.y - py * halfWidth)
        let arrow = NSBezierPath()
        arrow.move(to: tip)
        arrow.line(to: left)
        arrow.line(to: right)
        arrow.close()
        color.withAlphaComponent(0.95).setFill()
        arrow.fill()
    }

    private func drawPorts(on rect: CGRect, id: String, routes: [GraphEdgeRouter.RoutedEdge]) {
        // Output ports (filled) / input ports (hollow) from routed endpoints near this node.
        let pad: CGFloat = 2.5
        for route in routes {
            let nearStart = hypot(route.start.x - rect.midX, route.start.y - rect.midY) < max(rect.width, rect.height)
            let nearTip = hypot(route.tip.x - rect.midX, route.tip.y - rect.midY) < max(rect.width, rect.height)
            if nearStart, rect.insetBy(dx: -6, dy: -6).contains(route.start) {
                let p = NSBezierPath(
                    ovalIn: CGRect(x: route.start.x - pad, y: route.start.y - pad, width: pad * 2, height: pad * 2)
                )
                VibeChrome.ProviderSurface.nsSecondary.setFill()
                p.fill()
            }
            if nearTip, rect.insetBy(dx: -8, dy: -8).contains(route.tip) {
                let p = NSBezierPath(
                    ovalIn: CGRect(x: route.tip.x - pad, y: route.tip.y - pad, width: pad * 2, height: pad * 2)
                )
                VibeChrome.ProviderSurface.nsControl.setFill()
                p.fill()
                VibeChrome.ProviderSurface.nsSecondary.setStroke()
                p.lineWidth = 1.2
                p.stroke()
            }
        }
        _ = id
    }

    private func drawNode(_ n: FunctionGraphNode, origin: CGPoint, size: CGSize, selected: Bool) {
        let rect = CGRect(origin: origin, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        VibeChrome.ProviderSurface.nsContent.setFill()
        path.fill()

        // Header strip (IDA / Binja block chrome).
        let headerH: CGFloat = 22
        VibeChrome.ProviderSurface.nsControl.setFill()
        NSBezierPath(rect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: headerH)).fill()
        // Hairline under header.
        VibeChrome.ProviderSurface.nsSeparator.setStroke()
        let rule = NSBezierPath()
        rule.move(to: CGPoint(x: rect.minX, y: rect.minY + headerH))
        rule.line(to: CGPoint(x: rect.maxX, y: rect.minY + headerH))
        rule.lineWidth = 1
        rule.stroke()

        if n.kind == "entry" {
            VibeChrome.ProviderSurface.nsAccent.withAlphaComponent(0.55).setFill()
            NSBezierPath(rect: CGRect(x: rect.minX, y: rect.minY, width: 3, height: rect.height)).fill()
        }

        (selected ? VibeChrome.ProviderSurface.nsAccent : VibeChrome.ProviderSurface.nsSeparator).setStroke()
        path.lineWidth = selected ? 2.0 : 1.0
        path.stroke()

        let padX: CGFloat = 8
        let maxTextW = max(12, size.width - padX * 2)
        let titleFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let insnFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: VibeChrome.ProviderSurface.nsForeground,
        ]
        let insnAttrs: [NSAttributedString.Key: Any] = [
            .font: insnFont,
            .foregroundColor: VibeChrome.ProviderSurface.nsSecondary,
        ]

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        NSBezierPath(rect: rect.insetBy(dx: 3, dy: 3)).addClip()

        let title = n.kind == "entry" ? "\(n.label)  [\(n.addr)]" : n.addr
        Self.drawClippedLine(
            title,
            at: CGPoint(x: origin.x + padX, y: origin.y + 5),
            maxWidth: maxTextW,
            attributes: titleAttrs
        )

        var y = origin.y + headerH + 4
        let maxLines = max(0, Int((size.height - headerH - 12) / 14))
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

    // MARK: - HUD (minimap / recenter / lock)

    private var minimapRect: CGRect {
        let w: CGFloat = 148
        let h: CGFloat = 110
        return CGRect(x: bounds.width - w - 10, y: 10, width: w, height: h)
    }

    private var recenterButtonRect: CGRect {
        CGRect(x: minimapRect.minX, y: minimapRect.maxY + 6, width: 72, height: 22)
    }

    private var lockButtonRect: CGRect {
        CGRect(x: recenterButtonRect.maxX + 6, y: minimapRect.maxY + 6, width: 70, height: 22)
    }

    private func drawHUD() {
        guard !model.isEmpty else { return }
        drawMinimap()
        drawChromeButton(recenterButtonRect, title: "Recenter", active: false)
        drawChromeButton(lockButtonRect, title: panLocked ? "Locked" : "Lock", active: panLocked)
    }

    private func drawChromeButton(_ rect: CGRect, title: String, active: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (active
            ? VibeChrome.ProviderSurface.nsAccent.withAlphaComponent(0.35)
            : VibeChrome.ProviderSurface.nsWindow.withAlphaComponent(0.92)).setFill()
        path.fill()
        VibeChrome.ProviderSurface.nsSeparator.setStroke()
        path.lineWidth = 1
        path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: VibeChrome.ProviderSurface.nsForeground,
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        let p = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        (title as NSString).draw(at: p, withAttributes: attrs)
    }

    private func drawMinimap() {
        let map = minimapRect
        let path = NSBezierPath(roundedRect: map, xRadius: 8, yRadius: 8)
        VibeChrome.ProviderSurface.nsWindow.withAlphaComponent(0.92).setFill()
        path.fill()
        VibeChrome.ProviderSurface.nsSeparator.setStroke()
        path.lineWidth = 1
        path.stroke()

        let content = layoutCache.contentSize
        guard content.width > 1, content.height > 1 else { return }
        let inset: CGFloat = 6
        let inner = map.insetBy(dx: inset, dy: inset)
        let scale = min(inner.width / content.width, inner.height / content.height)
        let drawW = content.width * scale
        let drawH = content.height * scale
        let origin = CGPoint(
            x: inner.minX + (inner.width - drawW) / 2,
            y: inner.minY + (inner.height - drawH) / 2
        )

        // Nodes as tiny plates.
        for n in model.nodes {
            guard let o = layoutCache.positions[n.id], let sz = layoutCache.nodeSize[n.id] else { continue }
            let r = CGRect(
                x: origin.x + o.x * scale,
                y: origin.y + o.y * scale,
                width: max(2, sz.width * scale),
                height: max(2, sz.height * scale)
            )
            let p = NSBezierPath(roundedRect: r, xRadius: 1, yRadius: 1)
            (n.kind == "entry"
                ? VibeChrome.ProviderSurface.nsAccent
                : VibeChrome.ProviderSurface.nsSecondary.withAlphaComponent(0.55)).setFill()
            p.fill()
        }

        // Viewport rectangle in content space → minimap.
        let viewContent = CGRect(
            x: -pan.x / magnification,
            y: -pan.y / magnification,
            width: bounds.width / magnification,
            height: bounds.height / magnification
        )
        let vr = CGRect(
            x: origin.x + viewContent.minX * scale,
            y: origin.y + viewContent.minY * scale,
            width: viewContent.width * scale,
            height: viewContent.height * scale
        ).intersection(CGRect(x: origin.x, y: origin.y, width: drawW, height: drawH))
        if !vr.isNull, vr.width > 1, vr.height > 1 {
            let vp = NSBezierPath(rect: vr)
            VibeChrome.ProviderSurface.nsAccent.withAlphaComponent(0.18).setFill()
            vp.fill()
            VibeChrome.ProviderSurface.nsAccent.setStroke()
            vp.lineWidth = 1.2
            vp.stroke()
        }
    }

    // MARK: - Interaction

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
        if recenterButtonRect.contains(local) {
            fitInView()
            return
        }
        if lockButtonRect.contains(local) {
            panLocked.toggle()
            needsDisplay = true
            return
        }
        if minimapRect.contains(local) {
            dragKind = .minimap
            panToMinimap(local)
            return
        }
        let content = contentPoint(for: event)
        nodeDragMoved = false
        if let n = hitTestNode(at: content), let origin = layoutCache.positions[n.id] {
            selectedId = n.id
            needsDisplay = true
            dragKind = .node(id: n.id, originAtStart: origin, mouseAtStart: content)
            return
        }
        if panLocked { dragKind = .none; return }
        dragKind = .pan(start: local, panAtStart: pan)
    }

    override func mouseDragged(with event: NSEvent) {
        switch dragKind {
        case .none:
            return
        case .minimap:
            panToMinimap(localPoint(for: event))
        case let .pan(start, panAtStart):
            let local = localPoint(for: event)
            pan = CGPoint(x: panAtStart.x + (local.x - start.x), y: panAtStart.y + (local.y - start.y))
            clampPan()
            needsDisplay = true
        case let .node(id, originAtStart, mouseAtStart):
            let content = contentPoint(for: event)
            let dx = content.x - mouseAtStart.x
            let dy = content.y - mouseAtStart.y
            if hypot(dx, dy) > 3 { nodeDragMoved = true }
            var origin = CGPoint(x: originAtStart.x + dx, y: originAtStart.y + dy)
            origin.x = max(4, origin.x)
            origin.y = max(4, origin.y)
            origin = resolveNodePosition(id: id, proposed: origin)
            positionOverrides[id] = origin
            layoutCache.positions[id] = origin
            expandContentBounds()
            clampPan()
            invalidateRoutes()
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let kind = dragKind
        dragKind = .none
        if case let .node(id, _, _) = kind {
            if nodeDragMoved {
                invalidateRoutes()
                needsDisplay = true
            } else if let n = model.nodes.first(where: { $0.id == id }) {
                onSelectAddress?(n.addr)
            }
        }
    }

    override func magnify(with event: NSEvent) {
        magnification = max(0.25, min(2.5, magnification * (1 + event.magnification)))
        clampPan()
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            let factor: CGFloat = event.scrollingDeltaY > 0 ? 1.08 : 0.92
            magnification = max(0.25, min(2.5, magnification * factor))
        } else if !panLocked {
            pan.x += event.scrollingDeltaX
            pan.y += event.scrollingDeltaY
            clampPan()
        }
        needsDisplay = true
    }

    private func panToMinimap(_ local: CGPoint) {
        let map = minimapRect
        let content = layoutCache.contentSize
        guard content.width > 1, content.height > 1 else { return }
        let inset: CGFloat = 6
        let inner = map.insetBy(dx: inset, dy: inset)
        let scale = min(inner.width / content.width, inner.height / content.height)
        let drawW = content.width * scale
        let drawH = content.height * scale
        let origin = CGPoint(
            x: inner.minX + (inner.width - drawW) / 2,
            y: inner.minY + (inner.height - drawH) / 2
        )
        let cx = (local.x - origin.x) / scale
        let cy = (local.y - origin.y) / scale
        // Center viewport on clicked content point.
        pan.x = bounds.width / 2 - cx * magnification
        pan.y = bounds.height / 2 - cy * magnification
        clampPan()
        needsDisplay = true
    }

    /// Keep some content on-screen — no infinite empty panning.
    private func clampPan() {
        let content = layoutCache.contentSize
        let contentW = content.width * magnification
        let contentH = content.height * magnification
        let margin: CGFloat = 80
        // Horizontal: left edge of content not past view right-margin; right edge not past left-margin.
        let minPanX = min(margin, bounds.width - margin) - contentW
        let maxPanX = bounds.width - margin
        let minPanY = min(margin, bounds.height - margin) - contentH
        let maxPanY = bounds.height - margin
        pan.x = min(maxPanX, max(minPanX, pan.x))
        pan.y = min(maxPanY, max(minPanY, pan.y))
    }

    // MARK: - Node separation

    private func resolveNodePosition(id: String, proposed: CGPoint) -> CGPoint {
        guard let sz = layoutCache.nodeSize[id] else { return proposed }
        var origin = proposed
        let sep = FunctionGraphLayout.nodeSeparation
        for _ in 0 ..< 8 {
            var moved = false
            var rect = CGRect(origin: origin, size: sz).insetBy(dx: -sep / 2, dy: -sep / 2)
            for (otherId, otherOrigin) in layoutCache.positions where otherId != id {
                guard let osz = layoutCache.nodeSize[otherId] else { continue }
                let other = CGRect(origin: otherOrigin, size: osz).insetBy(dx: -sep / 2, dy: -sep / 2)
                if rect.intersects(other) {
                    let overlap = rect.intersection(other)
                    if overlap.width < overlap.height {
                        origin.x += rect.midX < other.midX ? -(overlap.width + 1) : (overlap.width + 1)
                    } else {
                        origin.y += rect.midY < other.midY ? -(overlap.height + 1) : (overlap.height + 1)
                    }
                    origin.x = max(4, origin.x)
                    origin.y = max(4, origin.y)
                    rect = CGRect(origin: origin, size: sz).insetBy(dx: -sep / 2, dy: -sep / 2)
                    moved = true
                }
            }
            if !moved { break }
        }
        return origin
    }

    private func resolveAllNodeOverlaps() {
        for _ in 0 ..< 6 {
            var dirty = false
            for n in model.nodes {
                guard let o = layoutCache.positions[n.id] else { continue }
                let fixed = resolveNodePosition(id: n.id, proposed: o)
                if hypot(fixed.x - o.x, fixed.y - o.y) > 0.5 {
                    layoutCache.positions[n.id] = fixed
                    if positionOverrides[n.id] != nil {
                        positionOverrides[n.id] = fixed
                    }
                    dirty = true
                }
            }
            if !dirty { break }
        }
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
        clampPan()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if needsCameraFit, bounds.width > 1, bounds.height > 1 {
            needsCameraFit = false
            fitInView()
        }
        clampPan()
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
