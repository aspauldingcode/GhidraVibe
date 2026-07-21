import AppKit
import Foundation
import SwiftUI
import TintedThemingSwift

enum AgentDiagramRender {
    /// Rasterize Graphviz DOT via `dot` if available.
    static func renderDOT(_ source: String, theme: Base16Theme) -> NSImage? {
        guard let dot = which("dot") else { return nil }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghidravibe-dot-\(UUID().uuidString)")
        let dotFile = tmp.appendingPathExtension("dot")
        let pngFile = tmp.appendingPathExtension("png")
        let themed = """
        digraph G {
          bgcolor="\(theme.base00)";
          node [color="\(theme.base0D)", fontcolor="\(theme.base05)", style=filled, fillcolor="\(theme.base01)"];
          edge [color="\(theme.base04)"];
          \(stripOuterDigraph(source))
        }
        """
        do {
            try themed.write(to: dotFile, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: dot)
        proc.arguments = ["-Tpng", "-o", pngFile.path, dotFile.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        guard proc.terminationStatus == 0, let img = NSImage(contentsOf: pngFile) else { return nil }
        try? FileManager.default.removeItem(at: dotFile)
        try? FileManager.default.removeItem(at: pngFile)
        return img
    }

    /// Best-effort Mermaid via `@mermaid-js/mermaid-cli` (`mmdc`) when installed.
    static func renderMermaid(_ source: String) -> NSImage? {
        guard let mmdc = which("mmdc") else { return nil }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghidravibe-mmd-\(UUID().uuidString)")
        let inFile = tmp.appendingPathExtension("mmd")
        let outFile = tmp.appendingPathExtension("png")
        do {
            try source.write(to: inFile, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: mmdc)
        proc.arguments = ["-i", inFile.path, "-o", outFile.path, "-b", "transparent"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        guard proc.terminationStatus == 0, let img = NSImage(contentsOf: outFile) else { return nil }
        try? FileManager.default.removeItem(at: inFile)
        try? FileManager.default.removeItem(at: outFile)
        return img
    }

    private static func which(_ name: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [name]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    private static func stripOuterDigraph(_ source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("digraph") || trimmed.lowercased().hasPrefix("graph") {
            // Keep as-is — wrapped again; prefer inner body if braces present.
            if let open = trimmed.firstIndex(of: "{"), let close = trimmed.lastIndex(of: "}") {
                return String(trimmed[trimmed.index(after: open)..<close])
            }
        }
        return trimmed
    }
}

struct AgentDiagramView: View {
    @Environment(\.vibeTheme) private var themes
    let language: String
    let source: String
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        let t = themes.theme
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.vibeSecondary)
                Spacer()
                if failed || image == nil {
                    Button("Retry") { render() }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(t.vibeSelection)

            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                } else if failed {
                    AgentCodeBlockView(language: language, code: source)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(t.vibeContentAlt)
        )
        .onAppear { render() }
        .a11yCatalog("ghidra.vibe.agent.diagram")
    }

    private func render() {
        failed = false
        image = nil
        let lang = language.lowercased()
        let theme = themes.theme
        Task.detached {
            let img: NSImage?
            if lang == "mermaid" {
                img = AgentDiagramRender.renderMermaid(source)
            } else {
                img = AgentDiagramRender.renderDOT(source, theme: theme)
            }
            await MainActor.run {
                if let img {
                    image = img
                } else {
                    failed = true
                }
            }
        }
    }
}
