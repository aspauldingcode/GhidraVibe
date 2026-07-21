import Foundation

/// Cursor-style Agent interaction modes.
enum AgentInteractionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case ask
    case agent
    case plan
    case debug
    case multitask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "Ask"
        case .agent: "Agent"
        case .plan: "Plan"
        case .debug: "Debug"
        case .multitask: "Multitask"
        }
    }

    var systemImage: String {
        switch self {
        case .ask: "bubble.left"
        case .agent: "hammer"
        case .plan: "list.bullet.clipboard"
        case .debug: "ant"
        case .multitask: "rectangle.split.2x1"
        }
    }

    var subtitle: String {
        switch self {
        case .ask: "Answer only — no tools"
        case .agent: "Full RE tool loop"
        case .plan: "Research + build a plan (no writes until Build)"
        case .debug: "Debugger / listing focused tools"
        case .multitask: "Agent tools + labeled send queue"
        }
    }

    /// Tools allowed for this mode. `nil` = all Agent tools.
    var allowedToolNames: Set<String>? {
        switch self {
        case .ask:
            return []
        case .agent, .multitask:
            return nil
        case .plan:
            // Read-only research — writes gated until Build.
            return [
                "gui_state", "gui_navigate", "gui_select_function", "gui_action",
                "list_functions", "decompile_function", "get_xrefs",
                "rag_discover", "web_search",
            ]
        case .debug:
            return [
                "gui_state", "gui_navigate", "gui_select_function", "gui_action",
                "list_functions", "decompile_function", "get_xrefs",
                "rag_discover", "web_search",
            ]
        }
    }

    /// Tools that mutate the program — blocked in Ask/Plan until Build.
    static let writeToolNames: Set<String> = [
        "rename_function", "set_comment", "improve_decompile", "autonomous_re", "rag_index",
    ]

    var allowsWrites: Bool {
        switch self {
        case .ask, .plan: false
        case .agent, .debug, .multitask: true
        }
    }

    var showsQueueLanes: Bool { self == .multitask }

    func systemPromptAppendix() -> String {
        switch self {
        case .ask:
            return """
            ## Interaction mode: Ask
            Answer questions only. Do **not** call tools. No renames, comments, or navigation.
            """
        case .agent:
            return """
            ## Interaction mode: Agent
            Use tools as needed to reverse engineer. Prefer JSpace discover before deep decompiles.
            """
        case .plan:
            return """
            ## Interaction mode: Plan
            Research with read-only tools, then propose a structured plan.
            End with a fenced block:
            ```plan
            title: Short plan title
            - [ ] Step one
            - [ ] Step two
            ```
            Do **not** apply renames/comments until the user clicks Build.
            """
        case .debug:
            return """
            ## Interaction mode: Debug
            Focus on runtime / listing / breakpoints / emulator. Prefer concrete addresses and steps.
            """
        case .multitask:
            return """
            ## Interaction mode: Multitask
            Same tools as Agent. The user may queue parallel follow-ups; keep replies scoped per turn.
            """
        }
    }
}
