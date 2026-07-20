import Foundation

/// Typed Agent tool schemas (OpenAI tools[]) — keep few for small local models.
enum AgentTools {
    static let systemPrompt = """
    You are the GhidraVibe reverse-engineering agent. You help rename symbols, improve \
    decompile readability, navigate the GUI, and run Autonomous RE playbooks.
    Always reason from the JSpace discovery pack first. Prefer tools over guessing.
    When renaming, use clear RE names (verbs, ObjC/Swift idioms). Never invent addresses.
    For improve_decompile: propose renames + plate/EOL comments; do not invent fake source.
    """

    /// OpenAI-compatible `tools` array.
    static var openAITools: [[String: Any]] {
        [
            tool("gui_state", "Get current GUI/selection/program state", [:]),
            tool(
                "gui_navigate",
                "Navigate to a pane (decompiler, functions, listing, agent, …)",
                ["pane": prop("string", "Pane id or title")]
            ),
            tool(
                "gui_select_function",
                "Select a function by name or address",
                [
                    "name": prop("string", "Function name"),
                    "address": prop("string", "Entry address"),
                ]
            ),
            tool(
                "gui_action",
                "Run a GuiControl action id (fetch_functions, decompile, auto_analyze, …)",
                ["id": prop("string", "Action id")]
            ),
            tool(
                "list_functions",
                "List functions from analysis MCP",
                ["limit": prop("integer", "Max rows", default: 80)]
            ),
            tool(
                "decompile_function",
                "Decompile selected or named function",
                [
                    "name": prop("string", "Function name"),
                    "address": prop("string", "Address"),
                ]
            ),
            tool(
                "get_xrefs",
                "Get xrefs to a function/address",
                [
                    "name": prop("string", "Function name"),
                    "address": prop("string", "Address"),
                ]
            ),
            tool(
                "rename_function",
                "Rename a function (writes into the open program)",
                [
                    "address": prop("string", "Function entry address"),
                    "name": prop("string", "Current name (optional)"),
                    "new_name": prop("string", "New symbol name"),
                ]
            ),
            tool(
                "set_comment",
                "Set plate or EOL comment at an address",
                [
                    "address": prop("string", "Address"),
                    "comment": prop("string", "Comment text"),
                    "kind": prop("string", "plate or eol"),
                ]
            ),
            tool(
                "rag_discover",
                "JSpace discovery pack for a query",
                ["query": prop("string", "RE question")]
            ),
            tool(
                "rag_index",
                "Index the current program into JSpace",
                [
                    "limit": prop("integer", "Function cap", default: 120),
                    "decompile_top": prop("integer", "Decompile top N", default: 24),
                ]
            ),
            tool(
                "improve_decompile",
                "Propose readability renames/comments for the current or named function",
                [
                    "name": prop("string", "Function name"),
                    "address": prop("string", "Address"),
                    "apply": prop("boolean", "Apply immediately if true"),
                ]
            ),
            tool(
                "autonomous_re",
                "Run Autonomous RE playbook over the current program (budgeted)",
                [
                    "budget": prop("integer", "Max functions to rewrite", default: 8),
                    "apply": prop("boolean", "Apply renames/comments", default: true),
                ]
            ),
        ]
    }

    /// Parse JSON object arguments from a tool call.
    static func parseArgs(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    /// Fallback when the model fails tool schema: extract rename pairs from prose.
    static func parseRenameTable(from text: String) -> [(old: String, new: String)] {
        var out: [(String, String)] = []
        let lines = text.split(separator: "\n").map(String.init)
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            // `foo` → `bar` or foo -> bar
            if let arrow = t.range(of: "→") ?? t.range(of: "->") {
                let left = String(t[..<arrow.lowerBound])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "`*- \t|"))
                let right = String(t[arrow.upperBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "`*- \t|"))
                if !left.isEmpty, !right.isEmpty, left != right, right.count < 80 {
                    out.append((left, right))
                }
            }
        }
        return out
    }

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any]) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "additionalProperties": true,
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    private static func prop(_ type: String, _ description: String, default defaultValue: Any? = nil) -> [String: Any] {
        var p: [String: Any] = ["type": type, "description": description]
        if let defaultValue { p["default"] = defaultValue }
        return p
    }
}

struct AgentPendingEdit: Identifiable, Hashable {
    enum Kind: String { case rename, comment }
    var id = UUID()
    var kind: Kind
    var address: String
    var oldName: String
    var newName: String
    var comment: String
    var commentKind: String
}
