import SwiftUI

struct TipOfTheDay {
    static let defaultsKey = "ghidra.vibe.showTips"
    static let seenKey = "ghidra.vibe.tipIndex"

    static var showOnStartup: Bool {
        if UserDefaults.standard.object(forKey: defaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static let tips: [String] = [
        "Open a program from the Active Project tree, then use the Tool Chest CodeBrowser icon — same flow as stock Ghidra.",
        "Window menu lists every provider (Functions, Strings, Memory Map, …). Inactive panes open as tabs on the right of Listing.",
        "File → Open Shared Cache… is IDA’s DSC flow: filter the index, Load selected (or double-click) to import one module with Apple symbols.",
        "Analysis MCP (toolbar) must be running before Fetch Functions / Decompile work.",
        "Help → Tip of the Day can be turned off; Help → Ghidra Help reopens the Welcome screen.",
        "GuiControl on :8091 and accessibility ids (ghidra.vibe.*) drive agent-device automation.",
    ]

    static func nextTip() -> String {
        let i = UserDefaults.standard.integer(forKey: seenKey)
        let tip = tips[i % tips.count]
        UserDefaults.standard.set(i + 1, forKey: seenKey)
        return tip
    }

    static func currentTip() -> String {
        let i = UserDefaults.standard.integer(forKey: seenKey)
        return tips[i % tips.count]
    }
}

struct TipOfTheDayAlert: ViewModifier {
    @Binding var isPresented: Bool
    @State private var tip = TipOfTheDay.currentTip()

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tip of the Day")
                        .font(.headline)
                    Text(tip)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LiquidGlass.Bar(spacing: 8) {
                        HStack {
                            Button("Don't Show Again") {
                                UserDefaults.standard.set(false, forKey: TipOfTheDay.defaultsKey)
                                isPresented = false
                            }
                            .buttonStyle(.glass)
                            .a11yCatalog("ghidra.vibe.tip.dont_show")
                            Spacer()
                            Button("Next Tip") { tip = TipOfTheDay.nextTip() }
                                .buttonStyle(.glass)
                                .a11yCatalog("ghidra.vibe.tip.next")
                            Button("Close") { isPresented = false }
                                .buttonStyle(.glassProminent)
                                .a11yCatalog("ghidra.vibe.tip.close")
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
                .padding(24)
                .frame(minWidth: 420)
                .onAppear { tip = TipOfTheDay.currentTip() }
            }
    }
}
