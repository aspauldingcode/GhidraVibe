import AppKit
import SwiftUI

/// Native SwiftUI stand-in for Malimite’s ANTLR C++ lexer/highlighter on Ghidra decompile output.
enum DecompileSyntax {
    private static let keywords: Set<String> = [
        "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue",
        "return", "goto", "sizeof", "typedef", "struct", "union", "enum", "const", "static",
        "extern", "volatile", "register", "inline", "true", "false", "NULL", "nullptr",
        "class", "public", "private", "protected", "virtual", "namespace", "using", "template",
        "try", "catch", "throw", "new", "delete", "this", "operator",
    ]

    private static let types: Set<String> = [
        "void", "char", "short", "int", "long", "float", "double", "signed", "unsigned",
        "bool", "boolean", "byte", "word", "dword", "qword", "undefined", "undefined1",
        "undefined2", "undefined4", "undefined8", "pointer", "code", "float10",
        "size_t", "ssize_t", "uint", "uint8_t", "uint16_t", "uint32_t", "uint64_t",
        "int8_t", "int16_t", "int32_t", "int64_t", "uintptr_t", "intptr_t",
        "id", "SEL", "BOOL", "NSInteger", "NSUInteger", "CGFloat",
    ]

    static func attributed(_ source: String, fontSize: CGFloat = 12) -> AttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let ns = NSMutableAttributedString(
            string: source,
            attributes: [
                .font: mono,
                .foregroundColor: NSColor.labelColor,
            ]
        )
        let full = NSRange(location: 0, length: ns.length)

        func paint(_ pattern: String, color: NSColor, font: NSFont? = nil, options: NSRegularExpression.Options = []) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for m in re.matches(in: source, range: full) {
                ns.addAttribute(.foregroundColor, value: color, range: m.range)
                if let font {
                    ns.addAttribute(.font, value: font, range: m.range)
                }
            }
        }

        paint(#"/\*[\s\S]*?\*/"#, color: .systemGreen)
        paint(#"//[^\n]*"#, color: .systemGreen)
        paint(#""([^"\\]|\\.)*""#, color: .systemRed)
        paint(#"'([^'\\]|\\.)*'"#, color: .systemRed)
        paint(#"\b0x[0-9A-Fa-f]+\b"#, color: .systemPurple)
        paint(#"\b\d+\b"#, color: .systemPurple)
        paint(#"^\s*#\s*\w+.*"#, color: .systemOrange, options: [.anchorsMatchLines])

        if let idRe = try? NSRegularExpression(pattern: #"\b[A-Za-z_][A-Za-z0-9_]*\b"#) {
            for m in idRe.matches(in: source, range: full) {
                let word = (source as NSString).substring(with: m.range)
                if keywords.contains(word) {
                    ns.addAttribute(.foregroundColor, value: NSColor.systemPink, range: m.range)
                    ns.addAttribute(.font, value: bold, range: m.range)
                } else if types.contains(word) {
                    ns.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: m.range)
                }
            }
        }

        return AttributedString(ns)
    }

    /// Lightweight Malimite SyntaxParser-style local/type harvest from decompile text.
    static func extractSymbols(_ source: String) -> (types: [String], locals: [String]) {
        var typesFound: [String] = []
        var locals: [String] = []
        let decl = try? NSRegularExpression(
            pattern: #"^\s*((?:const\s+|static\s+|unsigned\s+|signed\s+)*(?:[A-Za-z_][\w:]*)\s*\*?)\s+([A-Za-z_]\w*)\s*[=;,\[]"#
        )
        for (i, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let s = String(line)
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let decl, let m = decl.firstMatch(in: s, range: range), m.numberOfRanges >= 3 else { continue }
            let ty = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let name = ns.substring(with: m.range(at: 2))
            if !ty.isEmpty { typesFound.append("L\(i + 1): \(ty)") }
            if !name.isEmpty { locals.append("L\(i + 1): \(name)") }
        }
        return (Array(typesFound.prefix(40)), Array(locals.prefix(40)))
    }
}

/// Read-only highlighted decompile / C view (Malimite AnalysisWindow code pane).
struct SyntaxHighlightedCodeView: View {
    let text: String
    var fontSize: CGFloat = 12

    var body: some View {
        ScrollView {
            Text(DecompileSyntax.attributed(text, fontSize: fontSize))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
    }
}

/// Editable source with live highlighted preview (Code Editor / LLM).
struct SyntaxCodeEditor: View {
    @Binding var text: String
    @State private var showHighlight = true

    var body: some View {
        VStack(spacing: 0) {
            Toggle("Syntax highlight (Malimite ANTLR parity)", isOn: $showHighlight)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            if showHighlight {
                SyntaxHighlightedCodeView(text: text)
                    .frame(maxHeight: .infinity)
                TextEditor(text: $text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 72, maxHeight: 100)
            } else {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }
}
