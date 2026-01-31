import AppKit
import JJLib

// MARK: - Protocol

protocol SyntaxHighlighting {
    func highlight(_ textStorage: NSTextStorage)
}

// MARK: - Base Highlighter

class BaseSyntaxHighlighter: SyntaxHighlighting {
    let font = SyntaxTheme.font
    var defaultColor: NSColor { SyntaxTheme.defaultText }

    // Subclasses override these
    var keywords: [String] { [] }
    var declarationKeywords: [String] { [] }  // func, let, var, class, struct, etc. - blue in VSCode
    var keywordColor: NSColor { SyntaxTheme.keyword }
    var typeKeywords: [String] { [] }
    var singleLineCommentPrefix: String? { "//" }
    var blockCommentStart: String? { "/*" }
    var blockCommentEnd: String? { "*/" }
    var extraPatterns: [(NSRegularExpression, NSColor)] { [] }
    var selfKeywords: [String] { [] }
    var operatorPattern: NSRegularExpression? { nil }
    var attributePattern: NSRegularExpression? { nil }
    var highlightFunctionCalls: Bool { true }
    var highlightPropertyAccess: Bool { true }
    var systemFunctions: [String] { [] }  // print, NSLog, etc. - purple in Xcode

    // Precomputed
    private var _keywordSet: Set<String>?
    private var _declKeywordSet: Set<String>?
    private var _typeSet: Set<String>?
    private var _selfSet: Set<String>?
    private var _sysFuncSet: Set<String>?
    private var _stringRegex: NSRegularExpression?
    private var _numberRegex: NSRegularExpression?
    private static let _funcCallRegex = try? NSRegularExpression(pattern: "\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*(?=\\()")
    private static let _propertyRegex = try? NSRegularExpression(pattern: "\\.([a-zA-Z_][a-zA-Z0-9_]*)")

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

        // Color all identifiers first (keywords/types/strings/comments override later)
        applyIdentifiers(textStorage, text: text, range: fullRange)

        // Apply function calls early (keywords/types override known ones)
        if highlightFunctionCalls {
            applyFunctionCalls(textStorage, text: text, range: fullRange)
        }

        // Apply system function calls (override generic function call color)
        applySystemFunctions(textStorage, text: text as NSString, range: fullRange)

        // Apply property access
        if highlightPropertyAccess {
            applyPropertyAccess(textStorage, text: text, range: fullRange)
        }

        // Apply keywords
        applyKeywords(textStorage, text: nsText, range: fullRange)

        // Apply declaration keywords (override keyword color for these)
        applyDeclarationKeywords(textStorage, text: nsText, range: fullRange)

        // Apply type keywords
        applyTypes(textStorage, text: nsText, range: fullRange)

        // Apply self/this keywords
        applySelfKeywords(textStorage, text: nsText, range: fullRange)

        // Apply operators
        if let opRegex = operatorPattern {
            opRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.`operator`, range: r)
                }
            }
        }

        // Apply attributes/decorators
        if let attrRegex = attributePattern {
            attrRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttributes([.foregroundColor: SyntaxTheme.attribute, .font: SyntaxTheme.attributeFont], range: r)
                }
            }
        }

        // Apply extra patterns (language-specific)
        for (regex, color) in extraPatterns {
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: color, range: r)
                }
            }
        }

        // Apply bracket pair colorization (VSCode only)
        if SyntaxTheme.bracketPairEnabled {
            applyBracketPairColors(textStorage, text: text, range: fullRange)
        }

        // Apply numbers
        applyNumbers(textStorage, text: text, range: fullRange)

        // Apply strings (override keywords inside strings)
        applyStrings(textStorage, text: text, range: fullRange)

        // Apply comments last (override everything inside comments)
        applyComments(textStorage, text: text, nsText: nsText, range: fullRange)
    }

    private func applyBracketPairColors(_ ts: NSTextStorage, text: String, range: NSRange) {
        let colors = SyntaxTheme.bracketColors
        let openBrackets: Set<Character> = ["(", "[", "{"]
        let closeBrackets: Set<Character> = [")", "]", "}"]
        var depth = 0
        for (i, ch) in text.enumerated() {
            if openBrackets.contains(ch) {
                let color = colors[depth % colors.count]
                ts.addAttribute(.foregroundColor, value: color, range: NSRange(location: i, length: 1))
                depth += 1
            } else if closeBrackets.contains(ch) {
                depth = max(0, depth - 1)
                let color = colors[depth % colors.count]
                ts.addAttribute(.foregroundColor, value: color, range: NSRange(location: i, length: 1))
            }
        }
    }

    private static let _wordRegex = try? NSRegularExpression(pattern: "\\b(?:[a-zA-Z][a-zA-Z0-9_]*|_[a-zA-Z0-9][a-zA-Z0-9_]*)\\b")

    private func applyIdentifiers(_ ts: NSTextStorage, text: String, range: NSRange) {
        guard let pattern = Self._wordRegex else { return }
        let identColor = SyntaxTheme.identifier
        pattern.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range {
                ts.addAttribute(.foregroundColor, value: identColor, range: r)
            }
        }
    }

    private func applyKeywords(_ ts: NSTextStorage, text: NSString, range: NSRange) {
        if _keywordSet == nil { _keywordSet = Set(keywords) }
        guard let kwSet = _keywordSet, !kwSet.isEmpty, let pattern = Self._wordRegex else { return }
        pattern.enumerateMatches(in: text as String, range: range) { match, _, _ in
            guard let r = match?.range else { return }
            let word = text.substring(with: r)
            if kwSet.contains(word) {
                ts.addAttributes([.foregroundColor: keywordColor, .font: SyntaxTheme.keywordFont], range: r)
            }
        }
    }

    private func applyDeclarationKeywords(_ ts: NSTextStorage, text: NSString, range: NSRange) {
        if _declKeywordSet == nil { _declKeywordSet = Set(declarationKeywords) }
        guard let dkSet = _declKeywordSet, !dkSet.isEmpty, let pattern = Self._wordRegex else { return }
        pattern.enumerateMatches(in: text as String, range: range) { match, _, _ in
            guard let r = match?.range else { return }
            let word = text.substring(with: r)
            if dkSet.contains(word) {
                ts.addAttributes([.foregroundColor: SyntaxTheme.declarationKeyword, .font: SyntaxTheme.keywordFont], range: r)
            }
        }
    }

    private func applyTypes(_ ts: NSTextStorage, text: NSString, range: NSRange) {
        if _typeSet == nil { _typeSet = Set(typeKeywords) }
        guard let tSet = _typeSet, !tSet.isEmpty, let pattern = Self._wordRegex else { return }
        pattern.enumerateMatches(in: text as String, range: range) { match, _, _ in
            guard let r = match?.range else { return }
            let word = text.substring(with: r)
            if tSet.contains(word) {
                ts.addAttributes([.foregroundColor: SyntaxTheme.type, .font: SyntaxTheme.typeFont], range: r)
            }
        }
    }

    private func applySelfKeywords(_ ts: NSTextStorage, text: NSString, range: NSRange) {
        if _selfSet == nil { _selfSet = Set(selfKeywords) }
        guard let sSet = _selfSet, !sSet.isEmpty, let pattern = Self._wordRegex else { return }
        pattern.enumerateMatches(in: text as String, range: range) { match, _, _ in
            guard let r = match?.range else { return }
            let word = text.substring(with: r)
            if sSet.contains(word) {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.selfKeyword, range: r)
            }
        }
    }

    private func applyFunctionCalls(_ ts: NSTextStorage, text: String, range: NSRange) {
        Self._funcCallRegex?.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range(at: 1) {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.functionCall, range: r)
            }
        }
    }

    private func applyPropertyAccess(_ ts: NSTextStorage, text: String, range: NSRange) {
        Self._propertyRegex?.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range(at: 1) {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.property, range: r)
            }
        }
    }

    private func applySystemFunctions(_ ts: NSTextStorage, text: NSString, range: NSRange) {
        if _sysFuncSet == nil { _sysFuncSet = Set(systemFunctions) }
        guard let sfSet = _sysFuncSet, !sfSet.isEmpty, let pattern = Self._funcCallRegex else { return }
        pattern.enumerateMatches(in: text as String, range: range) { match, _, _ in
            guard let r = match?.range(at: 1) else { return }
            let word = text.substring(with: r)
            if sfSet.contains(word) {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.systemFunctionCall, range: r)
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
                        ts.addAttributes([.foregroundColor: SyntaxTheme.comment, .font: SyntaxTheme.commentFont], range: r)
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
                        ts.addAttributes([.foregroundColor: SyntaxTheme.comment, .font: SyntaxTheme.commentFont], range: r)
                    }
                }
            }
        }
    }
}

// MARK: - JJ Highlighter

class JJHighlighter: SyntaxHighlighting {
    let font = SyntaxTheme.font

    private static let identifierRegex = try? NSRegularExpression(pattern: "\\b(?:[a-zA-Z][a-zA-Z0-9_]*|_[a-zA-Z0-9][a-zA-Z0-9_]*)\\b")
    private static let keywordRegex = try? NSRegularExpression(pattern: JJPatterns.keyword)
    private static let blockRegex = try? NSRegularExpression(pattern: JJPatterns.block)
    private static let operatorRegex = try? NSRegularExpression(pattern: JJPatterns.operator)
    private static let specialRegex = try? NSRegularExpression(pattern: JJPatterns.special)
    private static let actionRegex = try? NSRegularExpression(pattern: JJPatterns.action)
    private static let separatorRegex = try? NSRegularExpression(pattern: JJPatterns.separator)
    private static let numberRegex = try? NSRegularExpression(pattern: JJPatterns.number)
    private static let stringRegex = try? NSRegularExpression(pattern: "\"(?:\\\\.|[^\"\\\\])*\"")
    private static let commentRegex = try? NSRegularExpression(pattern: JJPatterns.comment, options: .anchorsMatchLines)

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

        // Color all identifiers first (keywords/strings/comments override later)
        let identColor = SyntaxTheme.identifier
        Self.identifierRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: identColor, range: r)
            }
        }

        // Block structures (orange)
        Self.blockRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttributes([.foregroundColor: SyntaxTheme.block, .font: SyntaxTheme.keywordFont], range: r)
            }
        }

        // Operators (cyan)
        Self.operatorRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.`operator`, range: r)
            }
        }

        // Separators (gray)
        Self.separatorRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.comment, range: r)
            }
        }

        // Keywords (purple)
        Self.keywordRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttributes([.foregroundColor: SyntaxTheme.keyword, .font: SyntaxTheme.keywordFont], range: r)
            }
        }

        // Action names (blue)
        Self.actionRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range(at: 1) {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.action, range: r)
            }
        }

        // Special values (green)
        Self.specialRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.specialValue, range: r)
            }
        }

        // Bracket pair colorization (VSCode only)
        if SyntaxTheme.bracketPairEnabled {
            let colors = SyntaxTheme.bracketColors
            let openBrackets: Set<Character> = ["(", "[", "{"]
            let closeBrackets: Set<Character> = [")", "]", "}"]
            var depth = 0
            for (i, ch) in text.enumerated() {
                if openBrackets.contains(ch) {
                    let color = colors[depth % colors.count]
                    textStorage.addAttribute(.foregroundColor, value: color, range: NSRange(location: i, length: 1))
                    depth += 1
                } else if closeBrackets.contains(ch) {
                    depth = max(0, depth - 1)
                    let color = colors[depth % colors.count]
                    textStorage.addAttribute(.foregroundColor, value: color, range: NSRange(location: i, length: 1))
                }
            }
        }

        // Numbers (gold)
        Self.numberRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.number, range: r)
            }
        }

        // Strings (red) - override keywords inside strings
        Self.stringRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.string, range: r)
            }
        }

        // Comments (gray) - override everything
        Self.commentRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttributes([.foregroundColor: SyntaxTheme.comment, .font: SyntaxTheme.commentFont], range: r)
            }
        }
    }
}

// MARK: - Python Highlighter

class PythonHighlighter: BaseSyntaxHighlighter {
    private let T = loadTarget("py")
    override var keywords: [String] { T.highlightKeywords }
    override var declarationKeywords: [String] { T.highlightDeclKeywords }
    override var typeKeywords: [String] { T.highlightTypeKeywords }
    override var selfKeywords: [String] { T.highlightSelfKeywords }
    override var systemFunctions: [String] { T.highlightSystemFunctions }
    override var singleLineCommentPrefix: String? { T.highlightCommentPrefix }
    override var blockCommentStart: String? { nil }
    override var blockCommentEnd: String? { nil }

    private static let _opRegex = try? NSRegularExpression(pattern: "->|==|!=|<=|>=|\\*\\*|//|<<|>>|[+\\-*/%<>&|^~]|\\b(?:and|or|not|in|is)\\b")
    override var operatorPattern: NSRegularExpression? { Self._opRegex }

    private static let _attrRegex = try? NSRegularExpression(pattern: "@[a-zA-Z_][a-zA-Z0-9_.]*")
    override var attributePattern: NSRegularExpression? { Self._attrRegex }

    override func applyStrings(_ ts: NSTextStorage, text: String, range: NSRange) {
        let regex = try? NSRegularExpression(pattern: "\"\"\"[\\s\\S]*?\"\"\"|'''[\\s\\S]*?'''|\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'", options: .dotMatchesLineSeparators)
        regex?.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.string, range: r)
            }
        }
    }
}

// MARK: - JavaScript Highlighter

class JavaScriptHighlighter: BaseSyntaxHighlighter {
    private let T = loadTarget("js")
    override var keywords: [String] { T.highlightKeywords }
    override var declarationKeywords: [String] { T.highlightDeclKeywords }
    override var typeKeywords: [String] { T.highlightTypeKeywords }
    override var selfKeywords: [String] { T.highlightSelfKeywords }
    override var systemFunctions: [String] { T.highlightSystemFunctions }
    override var singleLineCommentPrefix: String? { T.highlightCommentPrefix }

    private static let _opRegex = try? NSRegularExpression(pattern: "=>|===|!==|==|!=|<=|>=|&&|\\|\\||\\?\\?|\\?\\.|\\.\\.\\.|\\.\\.|\\*\\*|<<|>>>|>>|[+\\-*/%<>&|^~!]")
    override var operatorPattern: NSRegularExpression? { Self._opRegex }

    override func applyStrings(_ ts: NSTextStorage, text: String, range: NSRange) {
        let regex = try? NSRegularExpression(pattern: "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`")
        regex?.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.string, range: r)
            }
        }
    }
}

// MARK: - C Highlighter

class CHighlighter: BaseSyntaxHighlighter {
    private let T = loadTarget("c")
    override var keywords: [String] { T.highlightKeywords }
    override var declarationKeywords: [String] { T.highlightDeclKeywords }
    override var typeKeywords: [String] { T.highlightTypeKeywords }
    override var systemFunctions: [String] { T.highlightSystemFunctions }
    override var singleLineCommentPrefix: String? { T.highlightCommentPrefix }

    private static let preprocessorRegex = try? NSRegularExpression(pattern: "^\\s*#\\s*\\w+.*$", options: .anchorsMatchLines)
    private static let _opRegex = try? NSRegularExpression(pattern: "->|==|!=|<=|>=|&&|\\|\\||<<|>>|\\+\\+|--|[+\\-*/%<>&|^~!]")
    override var operatorPattern: NSRegularExpression? { Self._opRegex }

    override var extraPatterns: [(NSRegularExpression, NSColor)] {
        guard let regex = Self.preprocessorRegex else { return [] }
        return [(regex, SyntaxTheme.preprocessor)]
    }
}

// MARK: - C++ Highlighter

class CppHighlighter: BaseSyntaxHighlighter {
    private let T = loadTarget("cpp")
    override var keywords: [String] { T.highlightKeywords }
    override var declarationKeywords: [String] { T.highlightDeclKeywords }
    override var typeKeywords: [String] { T.highlightTypeKeywords }
    override var selfKeywords: [String] { T.highlightSelfKeywords }
    override var systemFunctions: [String] { T.highlightSystemFunctions }
    override var singleLineCommentPrefix: String? { T.highlightCommentPrefix }

    private static let preprocessorRegex = try? NSRegularExpression(pattern: "^\\s*#\\s*\\w+.*$", options: .anchorsMatchLines)
    private static let _opRegex = try? NSRegularExpression(pattern: "->|::|==|!=|<=|>=|&&|\\|\\||<<|>>|\\+\\+|--|[+\\-*/%<>&|^~!]")
    override var operatorPattern: NSRegularExpression? { Self._opRegex }

    override var extraPatterns: [(NSRegularExpression, NSColor)] {
        guard let regex = Self.preprocessorRegex else { return [] }
        return [(regex, SyntaxTheme.preprocessor)]
    }
}

// MARK: - Swift Highlighter

class SwiftHighlighter: BaseSyntaxHighlighter {
    private let T = loadTarget("swift")
    override var keywords: [String] { T.highlightKeywords }
    override var declarationKeywords: [String] { T.highlightDeclKeywords }
    override var typeKeywords: [String] { T.highlightTypeKeywords }
    override var selfKeywords: [String] { T.highlightSelfKeywords }
    override var systemFunctions: [String] { T.highlightSystemFunctions }
    override var singleLineCommentPrefix: String? { T.highlightCommentPrefix }

    private static let _opRegex = try? NSRegularExpression(pattern: "->|==|!=|<=|>=|&&|\\|\\||\\?\\.|\\.\\.<|\\.\\.\\.|\\?\\?|[+\\-*/%<>&|^~!?]")
    override var operatorPattern: NSRegularExpression? { Self._opRegex }

    private static let _attrRegex = try? NSRegularExpression(pattern: "@[a-zA-Z_][a-zA-Z0-9_]*")
    override var attributePattern: NSRegularExpression? { Self._attrRegex }
}

// MARK: - Objective-C Highlighter

class ObjCHighlighter: BaseSyntaxHighlighter {
    private let T = loadTarget("objc")
    override var keywords: [String] { T.highlightKeywords }
    override var declarationKeywords: [String] { T.highlightDeclKeywords }
    override var selfKeywords: [String] { T.highlightSelfKeywords }
    override var systemFunctions: [String] { T.highlightSystemFunctions }
    override var singleLineCommentPrefix: String? { T.highlightCommentPrefix }
    override var typeKeywords: [String] { T.highlightTypeKeywords }

    private static let _opRegex = try? NSRegularExpression(pattern: "->|==|!=|<=|>=|&&|\\|\\||<<|>>|\\+\\+|--|[+\\-*/%<>&|^~!]")
    override var operatorPattern: NSRegularExpression? { Self._opRegex }

    private static let preprocessorRegex = try? NSRegularExpression(pattern: "^\\s*#\\s*\\w+.*$", options: .anchorsMatchLines)
    private static let objcDirectiveRegex = try? NSRegularExpression(pattern: "@\\w+")
    private static let objcStringRegex = try? NSRegularExpression(pattern: "@\"(?:\\\\.|[^\"\\\\])*\"")

    override var extraPatterns: [(NSRegularExpression, NSColor)] {
        var patterns: [(NSRegularExpression, NSColor)] = []
        if let r = Self.preprocessorRegex { patterns.append((r, SyntaxTheme.preprocessor)) }
        if let r = Self.objcDirectiveRegex { patterns.append((r, SyntaxTheme.objcDirective)) }
        return patterns
    }

    override func applyStrings(_ ts: NSTextStorage, text: String, range: NSRange) {
        // ObjC @"..." strings and regular "..." strings
        let regex = try? NSRegularExpression(pattern: "@?\"(?:\\\\.|[^\"\\\\])*\"")
        regex?.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.string, range: r)
            }
        }
    }
}

// MARK: - Objective-C++ Highlighter

class ObjCppHighlighter: BaseSyntaxHighlighter {
    private let T = loadTarget("objcpp")
    override var keywords: [String] { T.highlightKeywords }
    override var declarationKeywords: [String] { T.highlightDeclKeywords }
    override var selfKeywords: [String] { T.highlightSelfKeywords }
    override var systemFunctions: [String] { T.highlightSystemFunctions }
    override var singleLineCommentPrefix: String? { T.highlightCommentPrefix }
    override var typeKeywords: [String] { T.highlightTypeKeywords }

    private static let _opRegex = try? NSRegularExpression(pattern: "->|::|==|!=|<=|>=|&&|\\|\\||<<|>>|\\+\\+|--|[+\\-*/%<>&|^~!]")
    override var operatorPattern: NSRegularExpression? { Self._opRegex }

    private static let preprocessorRegex = try? NSRegularExpression(pattern: "^\\s*#\\s*\\w+.*$", options: .anchorsMatchLines)
    private static let objcDirectiveRegex = try? NSRegularExpression(pattern: "@\\w+")

    override var extraPatterns: [(NSRegularExpression, NSColor)] {
        var patterns: [(NSRegularExpression, NSColor)] = []
        if let r = Self.preprocessorRegex { patterns.append((r, SyntaxTheme.preprocessor)) }
        if let r = Self.objcDirectiveRegex { patterns.append((r, SyntaxTheme.objcDirective)) }
        return patterns
    }

    override func applyStrings(_ ts: NSTextStorage, text: String, range: NSRange) {
        let regex = try? NSRegularExpression(pattern: "@?\"(?:\\\\.|[^\"\\\\])*\"")
        regex?.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.string, range: r)
            }
        }
    }
}

// MARK: - Go Highlighter

class GoHighlighter: BaseSyntaxHighlighter {
    private let T = loadTarget("go")
    override var keywords: [String] { T.highlightKeywords }
    override var declarationKeywords: [String] { T.highlightDeclKeywords }
    override var typeKeywords: [String] { T.highlightTypeKeywords }
    override var systemFunctions: [String] { T.highlightSystemFunctions }
    override var singleLineCommentPrefix: String? { T.highlightCommentPrefix }

    private static let _opRegex = try? NSRegularExpression(pattern: ":=|<-|==|!=|<=|>=|&&|\\|\\||<<|>>|\\+\\+|--|[+\\-*/%<>&|^!]")
    override var operatorPattern: NSRegularExpression? { Self._opRegex }

    override func applyStrings(_ ts: NSTextStorage, text: String, range: NSRange) {
        let regex = try? NSRegularExpression(pattern: "\"(?:\\\\.|[^\"\\\\])*\"|`[^`]*`")
        regex?.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range {
                ts.addAttribute(.foregroundColor, value: SyntaxTheme.string, range: r)
            }
        }
    }
}

// MARK: - ARM64 Assembly Highlighter

class AsmHighlighter: SyntaxHighlighting {
    let font = SyntaxTheme.font

    private static let identifierRegex = try? NSRegularExpression(pattern: "\\b(?:[a-zA-Z][a-zA-Z0-9_]*|_[a-zA-Z0-9][a-zA-Z0-9_]*)\\b")
    private static let directiveRegex = try? NSRegularExpression(pattern: "\\.[a-zA-Z_][a-zA-Z0-9_]*")
    private static let registerRegex = try? NSRegularExpression(pattern: "\\b(?:x[0-9]|x[12][0-9]|x30|w[0-9]|w[12][0-9]|w30|sp|lr|xzr|wzr|pc|fp)\\b")
    private static let instructionRegex = try? NSRegularExpression(
        pattern: "\\b(?:mov|movz|movk|movn|add|adds|sub|subs|mul|madd|msub|sdiv|udiv|and|ands|orr|eor|bic|lsl|lsr|asr|ror|stp|ldp|str|ldr|strb|ldrb|strh|ldrh|adrp|adr|b|bl|br|blr|ret|cbz|cbnz|tbz|tbnz|cmp|cmn|tst|cset|csel|beq|bne|blt|ble|bgt|bge|blo|bhi|bls|bhs|b\\.eq|b\\.ne|b\\.lt|b\\.le|b\\.gt|b\\.ge|b\\.lo|b\\.hi|b\\.ls|b\\.hs|svc|brk|nop|neg|negs|mvn)\\b"
    )
    private static let numberRegex = try? NSRegularExpression(pattern: "#-?(?:0x[0-9a-fA-F]+|\\d+)")
    private static let labelRegex = try? NSRegularExpression(pattern: "^[a-zA-Z_][a-zA-Z0-9_]*:", options: .anchorsMatchLines)
    private static let stringRegex = try? NSRegularExpression(pattern: "\"(?:\\\\.|[^\"\\\\])*\"")
    private static let commentRegex = try? NSRegularExpression(pattern: "(?://|;).*$", options: .anchorsMatchLines)

    func highlight(_ textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string

        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        textStorage.addAttributes([
            .foregroundColor: SyntaxTheme.defaultText,
            .font: font
        ], range: fullRange)

        // Color all identifiers first
        let identColor = SyntaxTheme.identifier
        Self.identifierRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: identColor, range: r)
            }
        }

        // Directives
        Self.directiveRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.directive, range: r)
            }
        }

        // Instructions
        Self.instructionRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttributes([.foregroundColor: SyntaxTheme.keyword, .font: SyntaxTheme.keywordFont], range: r)
            }
        }

        // Registers
        Self.registerRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.register, range: r)
            }
        }

        // Labels
        Self.labelRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttributes([.foregroundColor: SyntaxTheme.type, .font: SyntaxTheme.typeFont], range: r)
            }
        }

        // Numbers
        Self.numberRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.number, range: r)
            }
        }

        // Bracket pair colorization (VSCode only)
        if SyntaxTheme.bracketPairEnabled {
            let colors = SyntaxTheme.bracketColors
            let openBrackets: Set<Character> = ["(", "[", "{"]
            let closeBrackets: Set<Character> = [")", "]", "}"]
            var depth = 0
            for (i, ch) in text.enumerated() {
                if openBrackets.contains(ch) {
                    let color = colors[depth % colors.count]
                    textStorage.addAttribute(.foregroundColor, value: color, range: NSRange(location: i, length: 1))
                    depth += 1
                } else if closeBrackets.contains(ch) {
                    depth = max(0, depth - 1)
                    let color = colors[depth % colors.count]
                    textStorage.addAttribute(.foregroundColor, value: color, range: NSRange(location: i, length: 1))
                }
            }
        }

        // Strings
        Self.stringRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttribute(.foregroundColor, value: SyntaxTheme.string, range: r)
            }
        }

        // Comments (last)
        Self.commentRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let r = match?.range {
                textStorage.addAttributes([.foregroundColor: SyntaxTheme.comment, .font: SyntaxTheme.commentFont], range: r)
            }
        }
    }
}

// MARK: - AppleScript Highlighter

class AppleScriptHighlighter: BaseSyntaxHighlighter {
    override var keywords: [String] {
        ["if", "then", "else", "repeat",
         "while", "until", "return", "try", "error",
         "exit", "not", "and", "or", "is", "as", "of", "in",
         "the", "a", "an", "do"]
    }
    override var declarationKeywords: [String] {
        ["tell", "end", "set", "to", "get", "on",
         "with", "considering", "ignoring", "timeout", "transaction",
         "using", "terms", "from",
         "local", "global", "property", "script", "my", "it", "its",
         "application", "display", "dialog", "log", "shell"]
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
