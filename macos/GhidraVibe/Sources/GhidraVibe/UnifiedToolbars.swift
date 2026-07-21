import SwiftUI

/// Shared Tahoe unified-toolbar helpers for main Ghidra windows.
/// Tools belong in SwiftUI `.toolbar` / NSToolbar — never an in-content strip.
enum UnifiedToolbars {
    /// FrontEnd / Project Window docking toolbar (stock order; matches Tahoe glass pill).
    static let projectWindow: [(id: String, symbol: String, label: String)] = [
        ("ghidra.vibe.project.toolbar.vc_add", "folder.badge.plus", "Add to Version Control"),
        ("ghidra.vibe.project.toolbar.vc_checkout", "arrow.down.doc", "CheckOut"),
        ("ghidra.vibe.project.toolbar.vc_update", "arrow.triangle.2.circlepath", "Update"),
        ("ghidra.vibe.project.toolbar.vc_checkin", "arrow.up.doc", "CheckIn"),
        ("ghidra.vibe.project.toolbar.vc_undo", "arrow.uturn.backward", "UndoCheckOut"),
        ("ghidra.vibe.project.toolbar.vc_find", "magnifyingglass", "Find Checkouts"),
        ("ghidra.vibe.project.toolbar.refresh", "arrow.uturn.forward", "Refresh"),
        ("ghidra.vibe.toolbar.mcp_health", "heart.text.square", "Engine Status"),
        ("ghidra.vibe.toolbar.start_mcp", "bolt.horizontal.circle", "Restart Engine"),
    ]

    static func stockToolSymbol(for group: String) -> String {
        switch group {
        case "Launch", "Emulate", "Resume": return "play.fill"
        case "Interrupt": return "stop.fill"
        case "Step Into": return "arrow.down.to.line"
        case "Step Over", "Step": return "arrow.right.to.line"
        case "Step Out": return "arrow.up.to.line"
        case "Skip": return "forward.end"
        case "Finish": return "checkmark.circle"
        case "TraceRmi Connect": return "link"
        case "Save", "Save Session": return "square.and.arrow.down"
        case "Create Session": return "plus.rectangle.on.folder"
        case "Run Correlators": return "point.3.connected.trianglepath.dotted"
        case "Apply Markup": return "checkmark.seal"
        default: return "wrench.and.screwdriver"
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
