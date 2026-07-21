import SwiftUI
import TintedThemingSwift

/// Pure-Swift syntax highlighter for fenced code blocks (ported from Whisperer).
/// No JavaScriptCore — works in the macOS app sandbox.
enum AgentSyntaxHighlighter {
    /// Builds a syntax-highlighted `AttributedString` for `code`, colored using `theme`.
    /// The highlighter is language-agnostic: it understands comments, strings, numbers,
    /// keywords, types, function calls, attributes and preprocessor directives across most
    /// C-family, scripting and markup languages, falling back to plain text when in doubt.
    static func highlight(
        code: String,
        language: String?,
        theme: Base16Theme,
        fontSize: CGFloat
    ) -> AttributedString {
        let font = Font.system(size: fontSize, design: .monospaced)
        let lang = (language ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        let lineComment = lineCommentToken(for: lang)
        let allowBlock = allowsBlockComment(for: lang)
        let allowHashPreprocessor = lineComment != "#"

        // Color palette (mirrors the Textual HighlighterTheme mapping in StructuredMessageView).
        let plainColor = theme.swiftUIBase05Color
        let keywordColor = theme.swiftUIBase0EColor
        let typeColor = theme.swiftUIBase0AColor
        let funcColor = theme.swiftUIBase0DColor
        let stringColor = theme.swiftUIBase0BColor
        let numberColor = theme.swiftUIBase09Color
        let constantColor = theme.swiftUIBase09Color
        let commentColor = theme.swiftUIBase03Color
        let attributeColor = theme.swiftUIBase0AColor
        let preprocessorColor = theme.swiftUIBase0FColor

        let chars = Array(code)
        let n = chars.count
        var i = 0

        var result = AttributedString()
        var plainBuffer = ""

        func flushPlain() {
            guard !plainBuffer.isEmpty else { return }
            var run = AttributedString(plainBuffer)
            run.font = font
            run.foregroundColor = plainColor
            result.append(run)
            plainBuffer.removeAll(keepingCapacity: true)
        }

        func emit(_ text: String, _ color: Color, semibold: Bool = false) {
            flushPlain()
            var run = AttributedString(text)
            run.font = semibold ? font.weight(.semibold) : font
            run.foregroundColor = color
            result.append(run)
        }

        func matches(_ token: String, at index: Int) -> Bool {
            let t = Array(token)
            guard index + t.count <= n else { return false }
            for k in 0..<t.count where chars[index + k] != t[k] { return false }
            return true
        }

        func isIdentifierStart(_ c: Character) -> Bool { c.isLetter || c == "_" }
        func isIdentifierBody(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

        while i < n {
            let c = chars[i]

            // Line comments
            if let lc = lineComment, matches(lc, at: i) {
                var j = i
                while j < n && chars[j] != "\n" { j += 1 }
                emit(String(chars[i..<j]), commentColor)
                i = j
                continue
            }

            // Block comments
            if allowBlock, c == "/", i + 1 < n, chars[i + 1] == "*" {
                var j = i + 2
                while j < n && !(chars[j] == "*" && j + 1 < n && chars[j + 1] == "/") { j += 1 }
                j = min(j + 2, n)
                emit(String(chars[i..<j]), commentColor)
                i = j
                continue
            }

            // Strings (triple-quoted, then single-delimiter)
            if c == "\"" || c == "'" || c == "`" {
                let delim = c
                if i + 2 < n, chars[i + 1] == delim, chars[i + 2] == delim {
                    var j = i + 3
                    while j < n && !(chars[j] == delim && j + 1 < n && chars[j + 1] == delim && j + 2 < n && chars[j + 2] == delim) {
                        j += 1
                    }
                    j = min(j + 3, n)
                    emit(String(chars[i..<j]), stringColor)
                    i = j
                    continue
                }
                var j = i + 1
                let allowNewline = (delim == "`")
                while j < n {
                    if chars[j] == "\\" { j += 2; continue }
                    if chars[j] == delim { j += 1; break }
                    if !allowNewline && chars[j] == "\n" { break }
                    j += 1
                }
                j = min(j, n)
                emit(String(chars[i..<j]), stringColor)
                i = j
                continue
            }

            // Numbers
            if c.isNumber || (c == "." && i + 1 < n && chars[i + 1].isNumber) {
                var j = i
                if c == "0", i + 1 < n, "xXbBoO".contains(chars[i + 1]) {
                    j = i + 2
                    while j < n && (chars[j].isHexDigit || chars[j] == "_") { j += 1 }
                } else {
                    while j < n && (chars[j].isNumber || chars[j] == "_") { j += 1 }
                    if j < n && chars[j] == "." && j + 1 < n && chars[j + 1].isNumber {
                        j += 1
                        while j < n && (chars[j].isNumber || chars[j] == "_") { j += 1 }
                    }
                    if j < n && (chars[j] == "e" || chars[j] == "E") {
                        var k = j + 1
                        if k < n && (chars[k] == "+" || chars[k] == "-") { k += 1 }
                        if k < n && chars[k].isNumber {
                            j = k
                            while j < n && chars[j].isNumber { j += 1 }
                        }
                    }
                    while j < n && chars[j].isLetter { j += 1 } // numeric suffix (f, L, u, ...)
                }
                emit(String(chars[i..<j]), numberColor)
                i = j
                continue
            }

            // Attributes (@Foo) and preprocessor directives (#include)
            if (c == "@") || (c == "#" && allowHashPreprocessor) {
                if i + 1 < n && isIdentifierStart(chars[i + 1]) {
                    var j = i + 1
                    while j < n && isIdentifierBody(chars[j]) { j += 1 }
                    emit(String(chars[i..<j]), c == "@" ? attributeColor : preprocessorColor)
                    i = j
                    continue
                }
            }

            // Identifiers / keywords
            if isIdentifierStart(c) {
                var j = i
                while j < n && isIdentifierBody(chars[j]) { j += 1 }
                let word = String(chars[i..<j])

                if Self.keywords.contains(word) {
                    emit(word, keywordColor, semibold: true)
                } else if Self.constants.contains(word) {
                    emit(word, constantColor, semibold: true)
                } else if let first = word.first, first.isUppercase {
                    emit(word, typeColor)
                } else {
                    var k = j
                    while k < n && (chars[k] == " " || chars[k] == "\t") { k += 1 }
                    if k < n && chars[k] == "(" {
                        emit(word, funcColor)
                    } else {
                        plainBuffer.append(word)
                    }
                }
                i = j
                continue
            }

            // Everything else (operators, punctuation, whitespace)
            plainBuffer.append(c)
            i += 1
        }

        flushPlain()
        return result
    }

    // MARK: - Language configuration

    private static func lineCommentToken(for lang: String) -> String? {
        switch lang {
        case "python", "py", "ruby", "rb", "sh", "bash", "shell", "zsh", "fish",
             "yaml", "yml", "toml", "ini", "conf", "r", "perl", "pl", "makefile",
             "make", "dockerfile", "elixir", "ex", "exs", "nim", "crystal", "cr":
            return "#"
        case "sql", "lua", "haskell", "hs", "elm", "ada", "vhdl", "applescript":
            return "--"
        case "json", "css", "scss", "less":
            return nil
        default:
            return "//"
        }
    }

    private static func allowsBlockComment(for lang: String) -> Bool {
        switch lang {
        case "python", "py", "ruby", "rb", "sh", "bash", "shell", "zsh", "fish",
             "yaml", "yml", "toml", "ini", "conf", "r", "perl", "pl", "makefile",
             "make", "dockerfile", "elixir", "ex", "exs", "nim", "haskell", "hs",
             "elm", "applescript", "json":
            return false
        default:
            return true
        }
    }

    // MARK: - Token vocabularies (a broad union across common languages)

    private static let keywords: Set<String> = [
        // Declarations / structure
        "func", "function", "fn", "def", "fun", "let", "var", "val", "const", "static",
        "class", "struct", "enum", "interface", "protocol", "trait", "impl", "extension",
        "typealias", "type", "typedef", "namespace", "module", "package", "import", "from",
        "export", "use", "using", "include", "require", "extends", "implements", "inherits",
        "abstract", "final", "sealed", "open", "public", "private", "protected", "internal",
        "fileprivate", "friend", "virtual", "override", "operator", "init", "deinit",
        "constructor", "destructor", "associatedtype", "where", "lazy", "weak", "unowned",
        "mutating", "nonmutating", "indirect", "convenience", "required", "dynamic",
        // Control flow
        "if", "else", "elif", "elseif", "unless", "switch", "case", "default", "match",
        "for", "foreach", "while", "do", "loop", "repeat", "break", "continue", "fallthrough",
        "return", "yield", "guard", "defer", "goto", "then", "begin", "end",
        // Concurrency / error handling
        "async", "await", "actor", "throw", "throws", "rethrows", "try", "catch", "finally",
        "except", "raise", "ensure", "spawn", "go", "select", "chan", "sync", "lock", "atomic",
        // Types / modifiers
        "void", "int", "long", "short", "char", "float", "double", "bool", "boolean", "byte",
        "string", "str", "object", "any", "auto", "unsigned", "signed", "mut",
        "ref", "out", "in", "inout", "as", "is", "new", "delete", "sizeof", "typeof",
        // Scripting / misc
        "lambda", "pass", "with", "global", "nonlocal", "del", "and", "or", "not", "echo",
        "print", "puts", "set", "dim", "pub", "mod", "macro", "unsafe", "extern",
        "self", "super", "this", "base",
    ]

    private static let constants: Set<String> = [
        "true", "false", "True", "False", "TRUE", "FALSE",
        "nil", "null", "NULL", "None", "none", "undefined", "NaN", "Infinity",
    ]
}
