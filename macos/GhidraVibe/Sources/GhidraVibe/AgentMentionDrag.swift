import AppKit
import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Drag payload for Agent `@` mentions — same tokens as the mention picker.
struct AgentMentionDrag: Codable, Transferable, Hashable, Sendable {
    /// Discriminator so JSON drops are not confused with `ProviderDockDrag`.
    var kind: String = "agent.mention"
    /// Composer token, e.g. `@Functions:entry`, `@Providers:decompiler`, `@Program`.
    var token: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
        ProxyRepresentation(exporting: \.token)
    }

    static func function(_ name: String) -> AgentMentionDrag {
        AgentMentionDrag(token: "@Functions:\(AgentMentions.sanitizeToken(name))")
    }

    static func provider(_ kind: ProviderKind) -> AgentMentionDrag {
        AgentMentionDrag(token: "@Providers:\(kind.rawValue)")
    }

    static func className(_ name: String) -> AgentMentionDrag {
        AgentMentionDrag(token: "@Classes:\(AgentMentions.sanitizeToken(name))")
    }

    static var program: AgentMentionDrag { AgentMentionDrag(token: "@Program") }

    static var selection: AgentMentionDrag { AgentMentionDrag(token: "@Selection") }

    static func docs(_ id: String) -> AgentMentionDrag {
        AgentMentionDrag(token: "@Docs:\(AgentMentions.sanitizeToken(id))")
    }

    static func pastChat(_ tokenSuffix: String) -> AgentMentionDrag {
        AgentMentionDrag(token: "@PastChats:\(tokenSuffix)")
    }

    static func decode(from data: Data) -> AgentMentionDrag? {
        guard let drag = try? JSONDecoder().decode(AgentMentionDrag.self, from: data),
              drag.kind == "agent.mention",
              !drag.token.isEmpty
        else { return nil }
        return drag
    }

    /// AppKit item provider — avoids SwiftUI `.draggable` focus rings on list rows.
    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        if let data = try? JSONEncoder().encode(self) {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.json.identifier,
                visibility: .all
            ) { completion in
                completion(data, nil)
                return nil
            }
        }
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.plainText.identifier,
            visibility: .all
        ) { completion in
            completion(self.token.data(using: .utf8), nil)
            return nil
        }
        return provider
    }
}

/// Optional outline-row drag (mention token or filesystem URL for attachments).
enum OutlineAgentDrag: Hashable {
    case mention(AgentMentionDrag)
    case file(URL)

    func itemProvider() -> NSItemProvider {
        switch self {
        case .mention(let drag):
            return drag.itemProvider()
        case .file(let url):
            return NSItemProvider(object: url as NSURL)
        }
    }
}

/// Non-function wrapper so `NativeOutlineTree` trailing closures still bind to `onSelect`.
struct OutlineAgentDragSource {
    let resolve: (OutlineTreeNode) -> OutlineAgentDrag?

    init(_ resolve: @escaping (OutlineTreeNode) -> OutlineAgentDrag?) {
        self.resolve = resolve
    }
}

extension View {
    /// Drag a mention token without SwiftUI `.draggable` blue focus outlines.
    @ViewBuilder
    func agentMentionDraggable(_ drag: AgentMentionDrag?, title: String? = nil) -> some View {
        if let drag {
            self
                .onDrag { drag.itemProvider() }
                .focusEffectDisabled()
                .help(title.map { "Drag onto Agent: \(drag.token) (\($0))" } ?? "Drag onto Agent: \(drag.token)")
        } else {
            self
        }
    }

    @ViewBuilder
    func outlineAgentDraggable(_ payload: OutlineAgentDrag?) -> some View {
        if let payload {
            self
                .onDrag { payload.itemProvider() }
                .focusEffectDisabled()
        } else {
            self
        }
    }
}
