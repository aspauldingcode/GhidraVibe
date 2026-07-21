import SwiftUI

/// Debugger/Emulator-unique provider panes (breakpoints, stack, threads, …).
/// Backed by in-process `debugger_list` — stock-empty until TraceRmi target connected.
struct DebugUniqueProviderView: View {
    @Environment(AppModel.self) private var model
    let title: String
    let toolSlug: String

    @State private var rows: [String] = []
    @State private var banner: String = ""

    private var a11yId: String {
        let slug = StockToolChrome.canonicalProviderSlug(title)
        return "ghidra.vibe.\(toolSlug).provider.\(slug)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Refresh") { reload() }
                    .buttonStyle(.bordered)
                        .tint(Color.vibeAccent)
                    .a11yCatalog("\(a11yId).refresh")
            }
            .padding(8)
            if !banner.isEmpty {
                Text(banner)
                    .font(.caption)
                    .foregroundStyle(Color.vibeSecondary)
                    .padding(.horizontal, 8)
            }
            List(rows, id: \.self) { row in
                Text(row).font(.caption.monospaced())
            }
            .a11yCatalog(a11yId)
                .vibeThemedList()
        }
        .onAppear { reload() }
        .onChange(of: model.debuggerStatus) { _, _ in reload() }
    }

    private func reload() {
        let provider = title
        if InProcessEngineHost.isRunning {
            let res = InProcessEngineHost.call("debugger_list", args: ["provider": provider])
            banner = res.message
            if let arr = res.json["rows"] as? [Any] {
                rows = arr.map { "\($0)" }
            } else if res.ok {
                rows = ["(empty)"]
            } else {
                rows = ["// \(res.message)"]
            }
            if let has = res.json["has_target"] as? Bool, !has {
                rows = ["No debug target — use TraceRmi Connect / Launch"]
            }
        } else {
            banner = "Program engine not running"
            rows = ["// Start engine, then TraceRmi Connect"]
        }
    }
}
