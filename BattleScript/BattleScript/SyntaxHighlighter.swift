import AppKit

// MARK: - Protocol

protocol SyntaxHighlighting {
    func highlight(_ textStorage: NSTextStorage)
}

// MARK: - Base Highlighter

class BaseSyntaxHighlighter: SyntaxHighlighting {
    let font = SyntaxTheme.font
    let defaultColor = SyntaxTheme.defaultText

    // Subclasses override these
    var keywords: [String] { [] }
    var keywordColor: NSColor { SyntaxTheme.keyword }
    var typeKeywords: [String] { [] }
    var singleLineCommentPrefix: String? { "//" }
    var blockCommentStart: String? { "/*" }
    var blockCommentEnd: String? { "*/" }
    var extraPatterns: [(NSRegularExpression, NSColor)] { [] }

    // Precomputed
    private var _keywordSet: Set<String>?
    private var _typeSet: Set<String>?
    private var _stringRegex: NSRegularExpression?
    private var _numberRegex: NSRegularExpression?

    func highlight(_ textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string
        let nsText = text as NSString

        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        // Reset to default
        textStorage.addAttributes([
            .foregroundColor: defaultColor,
            .font: font
        ], range: fullRange)

        // Apply keywords
        applyKeywords(textStorage, text: nsText, range: fullRange)

        // Apply type keywords
        applyTypes(textStorage, text: nsText, range: fullRange)

        // Apply extra patterns (language-specific)
        for (regex, color) in extraPatterns {
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: color, range: r)
                }
            }
        }

        // Apply numbers
        applyNumbers(textStorage, text: text, range: fullRange)

        // Apply strings (override keywords inside strings)
        applyStrings(textStorage, text: text, range: fullRange)

        // Apply comments last (override everything inside comments)
        applyComments(textStorage, text: text, nsText: nsText, range: fullRange)
    }

    private func applyKeywords(_ ts: NSTextStorage, text: NSString, range: NSRange) {
        if _keywordSet == nil { _keywordSet = Set(keywords) }
        guard let kwSet = _keywordSet, !kwSet.isEmpty else { return }
        let pattern = try! NSRegularExpression(pattern: "\\b[a-zA-Z_][a-zA-Z0-9_]*\\b")
        pattern.enumerateMatches(in: text as String, range: range) { match, _, _ in
            guard let r = match?.range else { return }
            let word = text.substring(with: r)
            if kwSet.contains(word) {
                ts.addAttribute(.foregroundColor, value: keywordColor, range: r)
            }
        }
    }

    private func applyTypes(_ ts: NSTextStorage, text: NSString, range: NSRange) {
        if _typeSet == nil { _typeSet = Set(typeKeywords) }
        guard let tSet = _typeSet, !tSet.isEmpty else { return }
        let pattern = try! NSRegularExpression(pattern: "\\b[a-zA-Z_][a-zA-Z0-9_]*\\b")
        pattern.enumerateMatches(in: text as String, range: range) { match, _, _ in
            guard let r = match?.range else { return }
            let word = text.substring(with: r)
            if tSet.contains(word) {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.type, range: r)
            }
        }
    }

    func applyStrings(_ ts: NSTextStorage, text: String, range: NSRange) {
        if _stringRegex == nil {
            _stringRegex = try? NSRegularExpression(pattern: "\"(?:\\\\.|[^\"\\\\])*\"")
        }
        _stringRegex?.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.string, range: r)
            }
        }
    }

    func applyNumbers(_ ts: NSTextStorage, text: String, range: NSRange) {
        if _numberRegex == nil {
            _numberRegex = try? NSRegularExpression(
                pattern: "\\b(?:0x[0-9a-fA-F]+|0b[01]+|0o[0-7]+|(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][+-]?\\d+)?)\\b"
            )
        }
        _numberRegex?.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.number, range: r)
            }
        }
    }

    func applyComments(_ ts: NSTextStorage, text: String, nsText: NSString, range: NSRange) {
        // Block comments
        if let start = blockCommentStart, let end = blockCommentEnd {
            let escaped1 = NSRegularExpression.escapedPattern(for: start)
            let escaped2 = NSRegularExpression.escapedPattern(for: end)
            if let regex = try? NSRegularExpression(pattern: "\(escaped1)[\\s\\S]*?\(escaped2)", options: .dotMatchesLineSeparators) {
                regex.enumerateMatches(in: text, range: range) { match, _, _ in
                    if let r = match?.range {
                        ts.addAttribute(.foregroundColor, value: SyntaxTheme.comment, range: r)
                    }
                }
            }
        }
        // Single-line comments
        if let prefix = singleLineCommentPrefix {
            let escaped = NSRegularExpression.escapedPattern(for: prefix)
            if let regex = try? NSRegularExpression(pattern: "\(escaped).*$", options: .anchorsMatchLines) {
                regex.enumerateMatches(in: text, range: range) { match, _, _ in
                    if let r = match?.range {
                        ts.addAttribute(.foregroundColor, value: SyntaxTheme.comment, range: r)
                    }
                }
            }
        }
    }
}

// MARK: - JJ Highlighter

class JJHighlighter: SyntaxHighlighting {
    let font = SyntaxTheme.font

    private static let keywordRegex = try! NSRegularExpression(pattern: "~>frob\\{[a-zA-Z0-9]*\\}|~>snag|~>slurp\\{[a-zA-Z0-9]*\\}|~>invoke|~>yeet|~>enum")
    private static let blockRegex = try! NSRegularExpression(pattern: "<~loop\\{|<~when\\{|<~else>>|<~morph\\{|<~try>>|<~oops>>|<~>>|\\}>>")
    private static let operatorRegex = try! NSRegularExpression(pattern: "<\\+>|<->|<\\*>|</>|<%>|<=>|<!=>|<lt>|<lte>|<gt>|<gte>|<&&>|<\\|\\|>|<!>")
    private static let specialRegex = try! NSRegularExpression(pattern: "~yep|~nope|~nil")
    private static let actionRegex = try! NSRegularExpression(pattern: "::(emit|grab|val|with|cases)")
    private static let separatorRegex = try! NSRegularExpression(pattern: "::")
    private static let numberRegex = try! NSRegularExpression(pattern: "#-?\\d+\\.?\\d*")
    private static let stringRegex = try! NSRegularExpression(pattern: "\"(?:\\\\.|[^\"\\\\])*\"")
    private static let commentRegex = try! NSRegularExpression(pattern: "@@.*$", options: .anchorsMatchLines)

    func highlight(_ textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string

        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        // Reset
        textStorage.addAttributes([
            .foregroundColor: SyntaxTheme.defaultText,
            .font: font
        ], range: fullRange)

        // Block structures (orange)
        Self.blockRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.block, range: r)
            }
        }

        // Operators (cyan)
        Self.operatorRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.`operator`, range: r)
            }
        }

        // Separators (gray)
        Self.separatorRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.comment, range: r)
            }
        }

        // Keywords (purple)
        Self.keywordRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.keyword, range: r)
            }
        }

        // Action names (blue)
        Self.actionRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range(at: 1) {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.action, range: r)
            }
        }

        // Special values (green)
        Self.specialRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.specialValue, range: r)
            }
        }

        // Numbers (gold)
        Self.numberRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.number, range: r)
            }
        }

        // Strings (red) - override keywords inside strings
        Self.stringRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.string, range: r)
            }
        }

        // Comments (gray) - override everything
        Self.commentRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.comment, range: r)
            }
        }
    }
}

// MARK: - Python Highlighter

class PythonHighlighter: BaseSyntaxHighlighter {
    override var keywords: [String] {
        ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
         "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in",
         "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while",
         "with", "yield", "print"]
    }
    override var typeKeywords: [String] {
        ["int", "float", "str", "bool", "list", "dict", "tuple", "set", "None", "True", "False",
         "range", "len", "type", "object", "Exception"]
    }
    override var singleLineCommentPrefix: String? { "#" }
    override var blockCommentStart: String? { nil }
    override var blockCommentEnd: String? { nil }

    override func applyStrings(_ ts: NSTextStorage, text: String, range: NSRange) {
        // Python supports both ' and " strings
        let regex = try! NSRegularExpression(pattern: "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'")
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.string, range: r)
            }
        }
    }
}

// MARK: - JavaScript Highlighter

class JavaScriptHighlighter: BaseSyntaxHighlighter {
    override var keywords: [String] {
        ["function", "var", "let", "const", "if", "else", "for", "while", "do", "return",
         "break", "continue", "switch", "case", "default", "try", "catch", "finally",
         "throw", "new", "this", "class", "extends", "static", "async", "await",
         "import", "export", "from", "typeof", "instanceof", "in", "of", "delete", "void",
         "yield", "console", "log"]
    }
    override var typeKeywords: [String] {
        ["true", "false", "null", "undefined", "NaN", "Infinity",
         "Array", "Object", "String", "Number", "Boolean", "Map", "Set", "Promise"]
    }

    override func applyStrings(_ ts: NSTextStorage, text: String, range: NSRange) {
        let regex = try! NSRegularExpression(pattern: "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`")
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.string, range: r)
            }
        }
    }
}

// MARK: - C Highlighter

class CHighlighter: BaseSyntaxHighlighter {
    override var keywords: [String] {
        ["auto", "break", "case", "const", "continue", "default", "do", "else", "enum",
         "extern", "for", "goto", "if", "inline", "register", "return", "sizeof",
         "static", "struct", "switch", "typedef", "union", "volatile", "while",
         "printf", "scanf", "malloc", "free", "NULL", "main"]
    }
    override var typeKeywords: [String] {
        ["int", "char", "void", "float", "double", "short", "long", "unsigned", "signed",
         "size_t", "bool", "FILE"]
    }

    private static let preprocessorRegex = try! NSRegularExpression(pattern: "^\\s*#\\s*\\w+.*$", options: .anchorsMatchLines)

    override var extraPatterns: [(NSRegularExpression, NSColor)] {
        [(Self.preprocessorRegex, SyntaxTheme.preprocessor)]
    }
}

// MARK: - C++ Highlighter

class CppHighlighter: BaseSyntaxHighlighter {
    override var keywords: [String] {
        ["auto", "break", "case", "catch", "class", "const", "constexpr", "continue",
         "default", "delete", "do", "else", "enum", "explicit", "export", "extern",
         "final", "for", "friend", "goto", "if", "inline", "mutable", "namespace",
         "new", "noexcept", "operator", "override", "private", "protected", "public",
         "register", "return", "sizeof", "static", "static_cast", "struct", "switch",
         "template", "this", "throw", "try", "typedef", "typeid", "typename",
         "union", "using", "virtual", "volatile", "while",
         "cout", "cin", "endl", "cerr", "printf", "main", "nullptr"]
    }
    override var typeKeywords: [String] {
        ["int", "char", "void", "float", "double", "short", "long", "unsigned", "signed",
         "bool", "string", "vector", "map", "set", "pair", "size_t",
         "true", "false", "NULL"]
    }

    private static let preprocessorRegex = try! NSRegularExpression(pattern: "^\\s*#\\s*\\w+.*$", options: .anchorsMatchLines)

    override var extraPatterns: [(NSRegularExpression, NSColor)] {
        [(Self.preprocessorRegex, SyntaxTheme.preprocessor)]
    }
}

// MARK: - Swift Highlighter

class SwiftHighlighter: BaseSyntaxHighlighter {
    override var keywords: [String] {
        ["func", "var", "let", "class", "struct", "enum", "extension", "protocol",
         "mutating", "inout", "if", "else", "guard", "for", "while", "repeat",
         "switch", "case", "default", "break", "continue", "return", "defer",
         "do", "try", "catch", "throw", "throws", "import", "public", "private",
         "internal", "fileprivate", "open", "final", "required", "convenience",
         "static", "subscript", "init", "deinit", "override", "where", "as", "is",
         "in", "self", "Self", "super", "print", "typealias", "associatedtype"]
    }
    override var typeKeywords: [String] {
        ["Int", "String", "Double", "Float", "Bool", "Character", "Array", "Dictionary",
         "Set", "Optional", "Any", "AnyObject", "Void", "Error",
         "true", "false", "nil"]
    }
}

// MARK: - Objective-C Highlighter

class ObjCHighlighter: BaseSyntaxHighlighter {
    override var keywords: [String] {
        ["auto", "break", "case", "const", "continue", "default", "do", "else", "enum",
         "extern", "for", "goto", "if", "inline", "register", "return", "sizeof",
         "static", "struct", "switch", "typedef", "union", "volatile", "while",
         "self", "super", "nil", "Nil", "YES", "NO", "NULL",
         "printf", "main", "NSLog"]
    }
    override var typeKeywords: [String] {
        ["int", "char", "void", "float", "double", "short", "long", "unsigned", "signed",
         "id", "BOOL", "NSString", "NSArray", "NSDictionary", "NSNumber", "NSObject",
         "NSInteger", "NSUInteger", "CGFloat", "instancetype", "SEL", "IMP", "Class"]
    }

    private static let preprocessorRegex = try! NSRegularExpression(pattern: "^\\s*#\\s*\\w+.*$", options: .anchorsMatchLines)
    private static let objcDirectiveRegex = try! NSRegularExpression(pattern: "@\\w+")
    private static let objcStringRegex = try! NSRegularExpression(pattern: "@\"(?:\\\\.|[^\"\\\\])*\"")

    override var extraPatterns: [(NSRegularExpression, NSColor)] {
        [
            (Self.preprocessorRegex, SyntaxTheme.preprocessor),
            (Self.objcDirectiveRegex, SyntaxTheme.objcDirective),
        ]
    }

    override func applyStrings(_ ts: NSTextStorage, text: String, range: NSRange) {
        // ObjC @"..." strings and regular "..." strings
        let regex = try! NSRegularExpression(pattern: "@?\"(?:\\\\.|[^\"\\\\])*\"")
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.string, range: r)
            }
        }
    }
}

// MARK: - Objective-C++ Highlighter

class ObjCppHighlighter: BaseSyntaxHighlighter {
    override var keywords: [String] {
        ["auto", "break", "case", "catch", "class", "const", "constexpr", "continue",
         "default", "delete", "do", "else", "enum", "explicit", "export", "extern",
         "final", "for", "friend", "goto", "if", "inline", "mutable", "namespace",
         "new", "noexcept", "operator", "override", "private", "protected", "public",
         "register", "return", "sizeof", "static", "struct", "switch",
         "template", "this", "throw", "try", "typedef", "typename",
         "union", "using", "virtual", "volatile", "while",
         "self", "super", "nil", "Nil", "YES", "NO", "NULL", "nullptr",
         "printf", "cout", "main", "NSLog"]
    }
    override var typeKeywords: [String] {
        ["int", "char", "void", "float", "double", "short", "long", "unsigned", "signed",
         "bool", "string", "vector", "id", "BOOL",
         "NSString", "NSArray", "NSDictionary", "NSNumber", "NSObject",
         "true", "false"]
    }

    private static let preprocessorRegex = try! NSRegularExpression(pattern: "^\\s*#\\s*\\w+.*$", options: .anchorsMatchLines)
    private static let objcDirectiveRegex = try! NSRegularExpression(pattern: "@\\w+")

    override var extraPatterns: [(NSRegularExpression, NSColor)] {
        [
            (Self.preprocessorRegex, SyntaxTheme.preprocessor),
            (Self.objcDirectiveRegex, SyntaxTheme.objcDirective),
        ]
    }

    override func applyStrings(_ ts: NSTextStorage, text: String, range: NSRange) {
        let regex = try! NSRegularExpression(pattern: "@?\"(?:\\\\.|[^\"\\\\])*\"")
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.string, range: r)
            }
        }
    }
}

// MARK: - Go Highlighter

class GoHighlighter: BaseSyntaxHighlighter {
    override var keywords: [String] {
        ["func", "var", "const", "package", "import", "if", "else", "for", "range",
         "switch", "case", "default", "break", "continue", "return", "defer",
         "go", "chan", "select", "type", "struct", "interface", "map",
         "fallthrough", "goto", "fmt", "Println", "Printf", "Sprintf", "main"]
    }
    override var typeKeywords: [String] {
        ["int", "int8", "int16", "int32", "int64",
         "uint", "uint8", "uint16", "uint32", "uint64",
         "float32", "float64", "complex64", "complex128",
         "string", "bool", "byte", "rune", "error", "any",
         "true", "false", "nil", "iota"]
    }

    override func applyStrings(_ ts: NSTextStorage, text: String, range: NSRange) {
        let regex = try! NSRegularExpression(pattern: "\"(?:\\\\.|[^\"\\\\])*\"|`[^`]*`")
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.string, range: r)
            }
        }
    }
}

// MARK: - ARM64 Assembly Highlighter

class AsmHighlighter: SyntaxHighlighting {
    let font = SyntaxTheme.font

    private static let directiveRegex = try! NSRegularExpression(pattern: "\\.[a-zA-Z_][a-zA-Z0-9_]*")
    private static let registerRegex = try! NSRegularExpression(pattern: "\\b(?:x[0-9]|x[12][0-9]|x30|w[0-9]|w[12][0-9]|w30|sp|lr|xzr|wzr|pc|fp)\\b")
    private static let instructionRegex = try! NSRegularExpression(
        pattern: "\\b(?:mov|movz|movk|movn|add|adds|sub|subs|mul|madd|msub|sdiv|udiv|and|ands|orr|eor|bic|lsl|lsr|asr|ror|stp|ldp|str|ldr|strb|ldrb|strh|ldrh|adrp|adr|b|bl|br|blr|ret|cbz|cbnz|tbz|tbnz|cmp|cmn|tst|cset|csel|beq|bne|blt|ble|bgt|bge|blo|bhi|bls|bhs|b\\.eq|b\\.ne|b\\.lt|b\\.le|b\\.gt|b\\.ge|b\\.lo|b\\.hi|b\\.ls|b\\.hs|svc|brk|nop|neg|negs|mvn)\\b"
    )
    private static let numberRegex = try! NSRegularExpression(pattern: "#-?(?:0x[0-9a-fA-F]+|\\d+)")
    private static let labelRegex = try! NSRegularExpression(pattern: "^[a-zA-Z_][a-zA-Z0-9_]*:", options: .anchorsMatchLines)
    private static let stringRegex = try! NSRegularExpression(pattern: "\"(?:\\\\.|[^\"\\\\])*\"")
    private static let commentRegex = try! NSRegularExpression(pattern: "(?://|;).*$", options: .anchorsMatchLines)

    func highlight(_ textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string

        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        textStorage.addAttributes([
            .foregroundColor: SyntaxTheme.defaultText,
            .font: font
        ], range: fullRange)

        // Directives
        Self.directiveRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.directive, range: r)
            }
        }

        // Instructions
        Self.instructionRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.keyword, range: r)
            }
        }

        // Registers
        Self.registerRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.register, range: r)
            }
        }

        // Labels
        Self.labelRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.type, range: r)
            }
        }

        // Numbers
        Self.numberRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.number, range: r)
            }
        }

        // Strings
        Self.stringRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.string, range: r)
            }
        }

        // Comments (last)
        Self.commentRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.comment, range: r)
            }
        }
    }
}

// MARK: - AppleScript Highlighter

class AppleScriptHighlighter: BaseSyntaxHighlighter {
    override var keywords: [String] {
        ["tell", "end", "set", "to", "get", "on", "if", "then", "else", "repeat",
         "while", "until", "with", "return", "try", "error", "considering",
         "ignoring", "timeout", "transaction", "using", "terms", "from",
         "exit", "local", "global", "property", "script", "my", "it", "its",
         "not", "and", "or", "is", "as", "of", "in", "the", "a", "an",
         "application", "display", "dialog", "log", "do", "shell"]
    }
    override var typeKeywords: [String] {
        ["true", "false", "missing", "value", "text", "integer", "real", "number",
         "list", "record", "date", "file", "alias", "string", "boolean",
         "class", "reference"]
    }
    override var singleLineCommentPrefix: String? { "--" }
    override var blockCommentStart: String? { nil }
    override var blockCommentEnd: String? { nil }
}

// MARK: - Highlighter Factory

struct SyntaxHighlighterFactory {
    private static let highlighters: [String: SyntaxHighlighting] = [
        "jj": JJHighlighter(),
        "py": PythonHighlighter(),
        "js": JavaScriptHighlighter(),
        "c": CHighlighter(),
        "cpp": CppHighlighter(),
        "swift": SwiftHighlighter(),
        "objc": ObjCHighlighter(),
        "objcpp": ObjCppHighlighter(),
        "go": GoHighlighter(),
        "asm": AsmHighlighter(),
        "applescript": AppleScriptHighlighter(),
    ]

    static func highlighter(for language: String) -> SyntaxHighlighting? {
        highlighters[language]
    }
}
