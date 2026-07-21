import AppKit
import SwiftUI

/// Whisperer-style share/copy helpers for Agent chat (message + full transcript).
enum AgentShare {
    /// Plain text for one bubble (role label + body).
    static func formatMessage(_ message: AgentMessage) -> String {
        let role = message.role == .user ? "You" : "Agent"
        let body = cleanBody(message.text)
        guard !body.isEmpty else { return "" }
        return "\(role): \(body)"
    }

    /// Full conversation export, Whisperer Chat Options style.
    static func formatChat(title: String, messages: [AgentMessage]) -> String {
        let headline = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titled = headline.isEmpty ? "Agent chat" : headline
        let body = messages
            .map(formatMessage)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !body.isEmpty else { return "\"\(titled)\"" }
        return "\"\(titled)\"\n\n\(body)"
    }

    static func cleanBody(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func copyToPasteboard(_ text: String) {
        let trimmed = cleanBody(text)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
    }

    /// System share sheet (NSSharingServicePicker), same surface ShareLink uses under the hood.
    @MainActor
    static func presentShareSheet(text: String, relativeTo view: NSView? = nil) {
        let item = cleanBody(text)
        guard !item.isEmpty else { return }
        let picker = NSSharingServicePicker(items: [item])
        let anchor = view
            ?? NSApp.keyWindow?.contentView
            ?? NSApp.mainWindow?.contentView
        guard let anchor else {
            copyToPasteboard(item)
            return
        }
        let rect = NSRect(
            x: anchor.bounds.midX - 1,
            y: anchor.bounds.midY - 1,
            width: 2,
            height: 2
        )
        picker.show(relativeTo: rect, of: anchor, preferredEdge: .minY)
    }
}

/// Bordered share control that opens the macOS share sheet (Whisperer ReactionSheet parity).
struct AgentShareButton: View {
    let text: String
    var label: String = "Share"
    var helpText: String = "Share via the system share sheet"

    var body: some View {
        ShareLink(item: text) {
            Label(label, systemImage: "square.and.arrow.up")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Capsule())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .help(helpText)
    }
}
