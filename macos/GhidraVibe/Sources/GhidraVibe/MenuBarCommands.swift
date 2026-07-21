import SwiftUI

/// Tahoe menubar policy for GhidraVibe:
/// - **Icons** only on items where the symbol clarifies the action (File/Edit standards,
///   Go To / nav, tool windows, sidebar toggles) — not on every Window → module row.
/// - **Shortcuts** declared with `.keyboardShortcut` so the system draws them right-aligned.
/// - **Window modules** use `Toggle` (checkmark column) so titles left-align; plain `Button`
///   rows mixed with system icon items were misaligned under macOS 26.
enum MenuBarCommands {
    /// SF Symbol for standard actions that warrant a Tahoe menu icon.
    static func fileSymbol(for action: String) -> String? {
        switch action {
        case "new_project": return "plus.doc"
        case "open_project": return "folder"
        case "import_file": return "square.and.arrow.down.on.square"
        case "open_framework_from_dsc": return "internaldrive"
        case "open_app_bundle": return "apple.logo"
        case "import_apple": return "shippingbox"
        case "open_shared_cache": return "externaldrive"
        case "save_program": return "square.and.arrow.down"
        case "close_program": return "xmark.circle"
        default: return nil
        }
    }

    static func editSymbol(for action: String) -> String? {
        switch action {
        case "undo": return "arrow.uturn.backward"
        case "redo": return "arrow.uturn.forward"
        case "edit_cut": return "scissors"
        case "edit_copy": return "doc.on.doc"
        case "edit_paste": return "doc.on.clipboard"
        default: return nil
        }
    }
}

/// Shared Window-menu module toggles (checkmark alignment, no per-row SF Symbol clutter).
struct WindowModuleToggles: View {
    @Bindable var model: AppModel
    let kinds: [ProviderKind]

    var body: some View {
        ForEach(kinds) { kind in
            Toggle(
                kind.title,
                isOn: Binding(
                    get: { model.isProviderMenuOn(kind) },
                    set: { want in
                        if want != model.isProviderMenuOn(kind) {
                            model.toggleProvider(kind)
                        }
                    }
                )
            )
            .help(model.isProviderMenuOn(kind) ? "Hide \(kind.title)" : "Show \(kind.title)")
        }
    }
}
