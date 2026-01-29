import Foundation

// MARK: - Protocol

protocol ReverseTranspiling {
    func reverseTranspile(_ code: String) -> String?
}

// MARK: - Shared Helpers

private func reverseExpr(_ expr: String) -> String {
    var s = expr.trimmingCharacters(in: .whitespaces)

    // Strip outer parens if fully wrapped
    if s.hasPrefix("(") && s.hasSuffix(")") {
        let inner = String(s.dropFirst().dropLast())
        if balancedParens(inner) {
            s = inner
        }
    }

    // Reverse booleans/null per language (done by caller before this)
    // Reverse operators (order matters - longer patterns first)
    s = s.replacingOccurrences(of: " === ", with: " <=> ")
    s = s.replacingOccurrences(of: " !== ", with: " <!=> ")
    s = s.replacingOccurrences(of: " == ", with: " <=> ")
    s = s.replacingOccurrences(of: " != ", with: " <!=> ")
    s = s.replacingOccurrences(of: " <= ", with: " <lte> ")
    s = s.replacingOccurrences(of: " >= ", with: " <gte> ")
    s = s.replacingOccurrences(of: " < ", with: " <lt> ")
    s = s.replacingOccurrences(of: " > ", with: " <gt> ")
    s = s.replacingOccurrences(of: " + ", with: " <+> ")
    s = s.replacingOccurrences(of: " - ", with: " <-> ")
    s = s.replacingOccurrences(of: " * ", with: " <*> ")
    s = s.replacingOccurrences(of: " / ", with: " </> ")
    s = s.replacingOccurrences(of: " % ", with: " <%> ")
    s = s.replacingOccurrences(of: " && ", with: " <&&> ")
    s = s.replacingOccurrences(of: " || ", with: " <||> ")

    // Reverse number literals: bare integers/floats → #num
    // But not inside strings
    s = reverseNumbers(s)

    return s
}

private func reverseNumbers(_ s: String) -> String {
    // Don't touch numbers inside quotes
    var result = ""
    var inString = false
    var i = s.startIndex
    while i < s.endIndex {
        let c = s[i]
        if c == "\"" { inString.toggle(); result.append(c); i = s.index(after: i); continue }
        if inString { result.append(c); i = s.index(after: i); continue }

        // Check if this is a bare number (not already prefixed with #)
        if c.isNumber || (c == "-" && i < s.index(before: s.endIndex) && s[s.index(after: i)].isNumber) {
            // Make sure previous char isn't # already or a letter
            let prevIdx = i > s.startIndex ? s.index(before: i) : nil
            let prevChar = prevIdx != nil ? s[prevIdx!] : Character(" ")
            if prevChar == "#" || prevChar.isLetter || prevChar == "_" {
                result.append(c); i = s.index(after: i); continue
            }
            // Collect the full number
            var numStr = String(c)
            var j = s.index(after: i)
            while j < s.endIndex && (s[j].isNumber || s[j] == ".") {
                numStr.append(s[j])
                j = s.index(after: j)
            }
            // Only prefix if it's a standalone number (next char is not a letter)
            let nextChar = j < s.endIndex ? s[j] : Character(" ")
            if !nextChar.isLetter && nextChar != "_" {
                result.append("#")
            }
            result.append(numStr)
            i = j
        } else {
            result.append(c)
            i = s.index(after: i)
        }
    }
    return result
}

private func balancedParens(_ s: String) -> Bool {
    var depth = 0
    for c in s {
        if c == "(" { depth += 1 }
        if c == ")" { depth -= 1 }
        if depth < 0 { return false }
    }
    return depth == 0
}

private func reverseCallExpr(_ funcName: String, _ argsStr: String) -> String {
    let reversedArgs = reverseExpr(argsStr)
    return "~>invoke{\(funcName)}::with(\(reversedArgs))"
}

private func indent(_ level: Int) -> String {
    String(repeating: "  ", count: level)
}

// MARK: - Python Reverse Transpiler

class PythonReverseTranspiler: ReverseTranspiling {
    private static let printRegex = try! NSRegularExpression(pattern: "^(\\s*)print\\((.+)\\)$")
    private static let varRegex = try! NSRegularExpression(pattern: "^(\\s*)([a-zA-Z_][a-zA-Z0-9_]*)\\s*=\\s*(.+)$")
    private static let forRegex = try! NSRegularExpression(pattern: "^(\\s*)for\\s+(\\w+)\\s+in\\s+range\\((\\d+),\\s*(\\d+)\\):$")
    private static let ifRegex = try! NSRegularExpression(pattern: "^(\\s*)if\\s+(.+):$")
    private static let elseRegex = try! NSRegularExpression(pattern: "^(\\s*)else:$")
    private static let defRegex = try! NSRegularExpression(pattern: "^(\\s*)def\\s+(\\w+)\\(([^)]*)\\):$")
    private static let returnRegex = try! NSRegularExpression(pattern: "^(\\s*)return\\s+(.+)$")
    private static let commentRegex = try! NSRegularExpression(pattern: "^(\\s*)#\\s*(.*)$")

    func reverseTranspile(_ code: String) -> String? {
        var lines = code.components(separatedBy: "\n")

        // Strip header
        lines = lines.filter { line in
            !line.hasPrefix("#!/usr/bin/env python3") &&
            !line.hasPrefix("# Transpiled from JibJab")
        }

        // Replace Python-specific booleans
        var text = lines.joined(separator: "\n")
        text = replaceOutsideStrings(text, "True", "~yep")
        text = replaceOutsideStrings(text, "False", "~nope")
        text = replaceOutsideStrings(text, "None", "~nil")
        text = replaceOutsideStrings(text, " and ", " <&&> ")
        text = replaceOutsideStrings(text, " or ", " <||> ")
        text = replaceOutsideStrings(text, "not ", "<!> ")
        lines = text.components(separatedBy: "\n")

        var result: [String] = []
        var indentLevel = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { result.append(""); continue }

            // Calculate indentation level from source (Python uses 4 spaces)
            let spaces = line.prefix(while: { $0 == " " }).count
            let srcIndent = spaces / 4

            // Close blocks when indentation decreases
            while indentLevel > srcIndent {
                indentLevel -= 1
                result.append("\(indent(indentLevel))<~>>")
            }

            let nsLine = trimmed as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            if let m = Self.commentRegex.firstMatch(in: trimmed, range: range) {
                let comment = nsLine.substring(with: m.range(at: 2))
                result.append("\(indent(indentLevel))@@ \(comment)")
            } else if let m = Self.defRegex.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 2))
                let params = nsLine.substring(with: m.range(at: 3))
                result.append("\(indent(indentLevel))<~morph{\(name)(\(params))}>>")
                indentLevel += 1
            } else if let m = Self.forRegex.firstMatch(in: trimmed, range: range) {
                let v = nsLine.substring(with: m.range(at: 2))
                let start = nsLine.substring(with: m.range(at: 3))
                let end = nsLine.substring(with: m.range(at: 4))
                result.append("\(indent(indentLevel))<~loop{\(v):\(start)..\(end)}>>")
                indentLevel += 1
            } else if let m = Self.ifRegex.firstMatch(in: trimmed, range: range) {
                let cond = reverseExpr(nsLine.substring(with: m.range(at: 2)))
                result.append("\(indent(indentLevel))<~when{\(cond)}>>")
                indentLevel += 1
            } else if Self.elseRegex.firstMatch(in: trimmed, range: range) != nil {
                result.append("\(indent(indentLevel))<~else>>")
                indentLevel += 1
            } else if let m = Self.returnRegex.firstMatch(in: trimmed, range: range) {
                let val = reverseExpr(nsLine.substring(with: m.range(at: 2)))
                result.append("\(indent(indentLevel))~>yeet{\(reverseFuncCalls(val, style: .python))}")
            } else if let m = Self.printRegex.firstMatch(in: trimmed, range: range) {
                let expr = reverseExpr(nsLine.substring(with: m.range(at: 2)))
                result.append("\(indent(indentLevel))~>frob{7a3}::emit(\(reverseFuncCalls(expr, style: .python)))")
            } else if let m = Self.varRegex.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 2))
                // Skip if the name is a known keyword
                if ["for", "if", "else", "def", "return", "print", "while"].contains(name) { continue }
                let val = reverseExpr(nsLine.substring(with: m.range(at: 3)))
                result.append("\(indent(indentLevel))~>snag{\(name)}::val(\(reverseFuncCalls(val, style: .python)))")
            } else {
                // Try to reverse standalone function calls
                let reversed = reverseFuncCalls(trimmed, style: .python)
                result.append("\(indent(indentLevel))\(reversed)")
            }
        }

        // Close remaining blocks
        while indentLevel > 0 {
            indentLevel -= 1
            result.append("\(indent(indentLevel))<~>>")
        }

        let output = result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output + "\n"
    }
}

// MARK: - C-Family Base Reverse Transpiler

enum CallStyle {
    case python, cFamily, swift, go, javascript, applescript
}

private func reverseFuncCalls(_ expr: String, style: CallStyle) -> String {
    // Match function calls: name(args)
    // But skip known language functions (print, printf, console.log, fmt.Println)
    let knownFuncs: Set<String>
    switch style {
    case .python: knownFuncs = ["print", "range", "len", "int", "float", "str"]
    case .cFamily: knownFuncs = ["printf", "main", "scanf", "malloc", "free", "NSLog"]
    case .swift: knownFuncs = ["print", "Int", "String", "Double"]
    case .go: knownFuncs = ["main"]
    case .javascript: knownFuncs = ["console"]
    case .applescript: knownFuncs = ["log", "display"]
    }

    let pattern = try! NSRegularExpression(pattern: "\\b([a-zA-Z_][a-zA-Z0-9_]*)\\(([^)]*)\\)")
    let nsExpr = expr as NSString
    var result = expr
    let matches = pattern.matches(in: expr, range: NSRange(location: 0, length: nsExpr.length))

    // Process in reverse to preserve ranges
    for match in matches.reversed() {
        let name = nsExpr.substring(with: match.range(at: 1))
        let args = nsExpr.substring(with: match.range(at: 2))
        if !knownFuncs.contains(name) && !name.isEmpty {
            let replacement = "~>invoke{\(name)}::with(\(args))"
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
    }
    return result
}

private func replaceOutsideStrings(_ text: String, _ find: String, _ replace: String) -> String {
    var result = ""
    var inString = false
    var i = text.startIndex
    while i < text.endIndex {
        if text[i] == "\"" { inString.toggle(); result.append(text[i]); i = text.index(after: i); continue }
        if inString { result.append(text[i]); i = text.index(after: i); continue }
        let remaining = text[i...]
        if remaining.hasPrefix(find) {
            result += replace
            i = text.index(i, offsetBy: find.count)
        } else {
            result.append(text[i])
            i = text.index(after: i)
        }
    }
    return result
}

// MARK: - Brace-Based Reverse Transpiler (shared for C, C++, JS, Swift, Go, ObjC, ObjC++)

class BraceReverseTranspiler: ReverseTranspiling {
    struct Config {
        var headerPatterns: [String] = []
        var hasMainWrapper: Bool = false
        var mainPattern: String = "int main()"
        var printPattern: NSRegularExpression
        var varPattern: NSRegularExpression
        var forPattern: NSRegularExpression
        var ifPattern: NSRegularExpression
        var elsePattern = try! NSRegularExpression(pattern: "^\\}?\\s*else\\s*\\{?$")
        var funcPattern: NSRegularExpression
        var returnPattern = try! NSRegularExpression(pattern: "^return\\s+(.+?)\\s*;?$")
        var commentPrefix: String = "//"
        var trueValue: String = "true"
        var falseValue: String = "false"
        var nilValue: String = "nil"
        var callStyle: CallStyle = .cFamily
        var forwardDeclPattern: NSRegularExpression? = nil
        var stripSemicolons: Bool = true
        var autoreleasepoolWrapper: Bool = false
    }

    let config: Config

    init(config: Config) { self.config = config }

    func reverseTranspile(_ code: String) -> String? {
        var lines = code.components(separatedBy: "\n")

        // Strip header lines
        lines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for pattern in config.headerPatterns {
                if trimmed.hasPrefix(pattern) || trimmed == pattern { return false }
            }
            return true
        }

        // Strip forward declarations (C/C++/ObjC)
        if let fwdDecl = config.forwardDeclPattern {
            lines = lines.filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return fwdDecl.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) == nil
            }
        }

        // Replace booleans/null
        var text = lines.joined(separator: "\n")
        text = replaceOutsideStrings(text, config.trueValue, "~yep")
        text = replaceOutsideStrings(text, config.falseValue, "~nope")
        if config.nilValue != "0" {
            text = replaceOutsideStrings(text, config.nilValue, "~nil")
        }
        lines = text.components(separatedBy: "\n")

        var result: [String] = []
        var indentLevel = 0
        var inMain = false
        var skipReturn0 = false
        var inAutoreleasepool = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { result.append(""); continue }

            // Skip main wrapper
            if config.hasMainWrapper {
                if trimmed.contains(config.mainPattern) && trimmed.contains("{") {
                    inMain = true; skipReturn0 = true; continue
                }
                if config.autoreleasepoolWrapper && trimmed.contains("@autoreleasepool") && trimmed.contains("{") {
                    inAutoreleasepool = true; continue
                }
                if inMain && skipReturn0 && trimmed == "return 0;" { skipReturn0 = false; continue }
                if inMain && trimmed == "}" {
                    if inAutoreleasepool { inAutoreleasepool = false; continue }
                    inMain = false; continue
                }
            }

            let nsLine = trimmed as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            // Closing brace
            if trimmed == "}" {
                if indentLevel > 0 { indentLevel -= 1 }
                result.append("\(indent(indentLevel))<~>>")
                continue
            }

            // Comment
            if trimmed.hasPrefix(config.commentPrefix) {
                let comment = String(trimmed.dropFirst(config.commentPrefix.count)).trimmingCharacters(in: .whitespaces)
                result.append("\(indent(indentLevel))@@ \(comment)")
                continue
            }

            // Function definition
            if let m = config.funcPattern.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 1))
                let params = nsLine.substring(with: m.range(at: 2))
                // Strip type annotations from params
                let cleanParams = stripParamTypes(params, style: config.callStyle)
                result.append("\(indent(indentLevel))<~morph{\(name)(\(cleanParams))}>>")
                indentLevel += 1
                continue
            }

            // For loop
            if let m = config.forPattern.firstMatch(in: trimmed, range: range) {
                let v = nsLine.substring(with: m.range(at: 1))
                let start = nsLine.substring(with: m.range(at: 2))
                let end = nsLine.substring(with: m.range(at: 3))
                result.append("\(indent(indentLevel))<~loop{\(v):\(start)..\(end)}>>")
                indentLevel += 1
                continue
            }

            // If
            if let m = config.ifPattern.firstMatch(in: trimmed, range: range) {
                let cond = reverseExpr(nsLine.substring(with: m.range(at: 1)))
                result.append("\(indent(indentLevel))<~when{\(cond)}>>")
                indentLevel += 1
                continue
            }

            // Else
            if config.elsePattern.firstMatch(in: trimmed, range: range) != nil {
                result.append("\(indent(indentLevel))<~else>>")
                indentLevel += 1
                continue
            }

            // Return
            if let m = config.returnPattern.firstMatch(in: trimmed, range: range) {
                var val = nsLine.substring(with: m.range(at: 1))
                if val.hasSuffix(";") { val = String(val.dropLast()) }
                val = reverseExpr(val)
                result.append("\(indent(indentLevel))~>yeet{\(reverseFuncCalls(val, style: config.callStyle))}")
                continue
            }

            // Print
            if let m = config.printPattern.firstMatch(in: trimmed, range: range) {
                let expr = reverseExpr(nsLine.substring(with: m.range(at: 1)))
                result.append("\(indent(indentLevel))~>frob{7a3}::emit(\(reverseFuncCalls(expr, style: config.callStyle)))")
                continue
            }

            // Variable declaration
            if let m = config.varPattern.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 1))
                var val = nsLine.substring(with: m.range(at: 2))
                if val.hasSuffix(";") { val = String(val.dropLast()) }
                val = reverseExpr(val)
                result.append("\(indent(indentLevel))~>snag{\(name)}::val(\(reverseFuncCalls(val, style: config.callStyle)))")
                continue
            }

            // Unrecognized - pass through as comment
            var cleaned = trimmed
            if cleaned.hasSuffix(";") { cleaned = String(cleaned.dropLast()) }
            result.append("\(indent(indentLevel))\(reverseFuncCalls(reverseExpr(cleaned), style: config.callStyle))")
        }

        // Close remaining blocks
        while indentLevel > 0 {
            indentLevel -= 1
            result.append("\(indent(indentLevel))<~>>")
        }

        let output = result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output + "\n"
    }

    private func stripParamTypes(_ params: String, style: CallStyle) -> String {
        switch style {
        case .cFamily:
            // "int n" → "n", "int a, int b" → "a, b"
            return params.components(separatedBy: ",").map { p in
                let parts = p.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
                return parts.last ?? p.trimmingCharacters(in: .whitespaces)
            }.joined(separator: ", ")
        case .swift:
            // "_ n: Int" → "n", "_ a: Int, _ b: Int" → "a, b"
            return params.components(separatedBy: ",").map { p in
                var cleaned = p.trimmingCharacters(in: .whitespaces)
                if cleaned.hasPrefix("_ ") { cleaned = String(cleaned.dropFirst(2)) }
                if let colonIdx = cleaned.firstIndex(of: ":") {
                    cleaned = String(cleaned[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                }
                return cleaned
            }.joined(separator: ", ")
        case .go:
            // "a int, b int" → "a, b" or "n int" → "n"
            return params.components(separatedBy: ",").map { p in
                let parts = p.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
                return parts.first ?? p.trimmingCharacters(in: .whitespaces)
            }.joined(separator: ", ")
        default:
            return params
        }
    }
}

// MARK: - Language-Specific Factories

class CReverseTranspiler: BraceReverseTranspiler {
    init() {
        super.init(config: Config(
            headerPatterns: ["// Transpiled from JibJab", "#include"],
            hasMainWrapper: true,
            mainPattern: "int main()",
            printPattern: try! NSRegularExpression(pattern: "^printf\\(\"%[dslf]\\\\n\",\\s*(.+)\\);$"),
            varPattern: try! NSRegularExpression(pattern: "^(?:int|float|double|char|long|unsigned|short|auto)\\s+(\\w+)\\s*=\\s*(.+);$"),
            forPattern: try! NSRegularExpression(pattern: "^for\\s*\\(int\\s+(\\w+)\\s*=\\s*(\\d+);\\s*\\w+\\s*<\\s*(\\d+);"),
            ifPattern: try! NSRegularExpression(pattern: "^if\\s*\\((.+)\\)\\s*\\{$"),
            funcPattern: try! NSRegularExpression(pattern: "^(?:int|void|float|double)\\s+(\\w+)\\(([^)]*)\\)\\s*\\{$"),
            callStyle: .cFamily,
            forwardDeclPattern: try! NSRegularExpression(pattern: "^(?:int|void|float|double)\\s+\\w+\\([^)]*\\);$"),
            autoreleasepoolWrapper: false
        ))
    }
}

class CppReverseTranspiler: BraceReverseTranspiler {
    init() {
        super.init(config: Config(
            headerPatterns: ["// Transpiled from JibJab", "#include"],
            hasMainWrapper: true,
            mainPattern: "int main()",
            printPattern: try! NSRegularExpression(pattern: "^std::cout\\s*<<\\s*(.+?)\\s*<<\\s*std::endl;$"),
            varPattern: try! NSRegularExpression(pattern: "^(?:int|float|double|char|long|unsigned|auto|bool|string)\\s+(\\w+)\\s*=\\s*(.+);$"),
            forPattern: try! NSRegularExpression(pattern: "^for\\s*\\(int\\s+(\\w+)\\s*=\\s*(\\d+);\\s*\\w+\\s*<\\s*(\\d+);"),
            ifPattern: try! NSRegularExpression(pattern: "^if\\s*\\((.+)\\)\\s*\\{$"),
            funcPattern: try! NSRegularExpression(pattern: "^(?:int|void|float|double|auto)\\s+(\\w+)\\(([^)]*)\\)\\s*\\{$"),
            callStyle: .cFamily,
            forwardDeclPattern: try! NSRegularExpression(pattern: "^(?:int|void|float|double|auto)\\s+\\w+\\([^)]*\\);$")
        ))
    }
}

class JavaScriptReverseTranspiler: BraceReverseTranspiler {
    init() {
        super.init(config: Config(
            headerPatterns: ["// Transpiled from JibJab"],
            hasMainWrapper: false,
            printPattern: try! NSRegularExpression(pattern: "^console\\.log\\((.+)\\);$"),
            varPattern: try! NSRegularExpression(pattern: "^(?:let|const|var)\\s+(\\w+)\\s*=\\s*(.+);$"),
            forPattern: try! NSRegularExpression(pattern: "^for\\s*\\(let\\s+(\\w+)\\s*=\\s*(\\d+);\\s*\\w+\\s*<\\s*(\\d+);"),
            ifPattern: try! NSRegularExpression(pattern: "^if\\s*\\((.+)\\)\\s*\\{$"),
            funcPattern: try! NSRegularExpression(pattern: "^function\\s+(\\w+)\\(([^)]*)\\)\\s*\\{$"),
            trueValue: "true",
            falseValue: "false",
            nilValue: "null",
            callStyle: .javascript
        ))
    }
}

class SwiftReverseTranspiler: BraceReverseTranspiler {
    init() {
        super.init(config: Config(
            headerPatterns: ["// Transpiled from JibJab"],
            hasMainWrapper: false,
            printPattern: try! NSRegularExpression(pattern: "^print\\((.+)\\)$"),
            varPattern: try! NSRegularExpression(pattern: "^var\\s+(\\w+)(?:\\s*:\\s*\\w+)?\\s*=\\s*(.+)$"),
            forPattern: try! NSRegularExpression(pattern: "^for\\s+(\\w+)\\s+in\\s+(\\d+)\\.\\.<(\\d+)\\s*\\{$"),
            ifPattern: try! NSRegularExpression(pattern: "^if\\s+(.+?)\\s*\\{$"),
            funcPattern: try! NSRegularExpression(pattern: "^func\\s+(\\w+)\\(([^)]*)\\)(?:\\s*->\\s*\\w+)?\\s*\\{$"),
            trueValue: "true",
            falseValue: "false",
            nilValue: "nil",
            callStyle: .swift,
            stripSemicolons: false
        ))
    }
}

class GoReverseTranspiler: BraceReverseTranspiler {
    init() {
        super.init(config: Config(
            headerPatterns: ["// Transpiled from JibJab", "package main", "import"],
            hasMainWrapper: true,
            mainPattern: "func main()",
            printPattern: try! NSRegularExpression(pattern: "^fmt\\.Println\\((.+)\\)$"),
            varPattern: try! NSRegularExpression(pattern: "^(?:var\\s+)?(\\w+)\\s*:?=\\s*(.+)$"),
            forPattern: try! NSRegularExpression(pattern: "^for\\s+(\\w+)\\s*:=\\s*(\\d+);\\s*\\w+\\s*<\\s*(\\d+);"),
            ifPattern: try! NSRegularExpression(pattern: "^if\\s+(.+?)\\s*\\{$"),
            funcPattern: try! NSRegularExpression(pattern: "^func\\s+(\\w+)\\(([^)]*)\\)(?:\\s*\\w+)?\\s*\\{$"),
            trueValue: "true",
            falseValue: "false",
            nilValue: "nil",
            callStyle: .go,
            stripSemicolons: false
        ))
    }
}

class ObjCReverseTranspiler: BraceReverseTranspiler {
    init() {
        super.init(config: Config(
            headerPatterns: ["// Transpiled from JibJab", "#import", "#include"],
            hasMainWrapper: true,
            mainPattern: "int main(",
            printPattern: try! NSRegularExpression(pattern: "^printf\\(\"%[a-z]*\\\\n\",\\s*(?:\\(long\\))?(.+)\\);$"),
            varPattern: try! NSRegularExpression(pattern: "^(?:NSInteger|int|float|double|long|BOOL|NSUInteger)\\s+(\\w+)\\s*=\\s*(.+);$"),
            forPattern: try! NSRegularExpression(pattern: "^for\\s*\\(int\\s+(\\w+)\\s*=\\s*(\\d+);\\s*\\w+\\s*<\\s*(\\d+);"),
            ifPattern: try! NSRegularExpression(pattern: "^if\\s*\\((.+)\\)\\s*\\{$"),
            funcPattern: try! NSRegularExpression(pattern: "^(?:NSInteger|int|void|float|double)\\s+(\\w+)\\(([^)]*)\\)\\s*\\{$"),
            trueValue: "YES",
            falseValue: "NO",
            nilValue: "nil",
            callStyle: .cFamily,
            forwardDeclPattern: try! NSRegularExpression(pattern: "^(?:NSInteger|int|void|float|double)\\s+\\w+\\([^)]*\\);$"),
            autoreleasepoolWrapper: true
        ))
    }
}

class ObjCppReverseTranspiler: BraceReverseTranspiler {
    init() {
        super.init(config: Config(
            headerPatterns: ["// Transpiled from JibJab", "#import", "#include"],
            hasMainWrapper: true,
            mainPattern: "int main(",
            printPattern: try! NSRegularExpression(pattern: "^std::cout\\s*<<\\s*(.+?)\\s*<<\\s*std::endl;$"),
            varPattern: try! NSRegularExpression(pattern: "^(?:int|float|double|auto|bool|long)\\s+(\\w+)\\s*=\\s*(.+);$"),
            forPattern: try! NSRegularExpression(pattern: "^for\\s*\\(int\\s+(\\w+)\\s*=\\s*(\\d+);\\s*\\w+\\s*<\\s*(\\d+);"),
            ifPattern: try! NSRegularExpression(pattern: "^if\\s*\\((.+)\\)\\s*\\{$"),
            funcPattern: try! NSRegularExpression(pattern: "^(?:int|void|float|double|auto)\\s+(\\w+)\\(([^)]*)\\)\\s*\\{$"),
            trueValue: "true",
            falseValue: "false",
            nilValue: "nil",
            callStyle: .cFamily,
            forwardDeclPattern: try! NSRegularExpression(pattern: "^(?:int|void|float|double|auto)\\s+\\w+\\([^)]*\\);$"),
            autoreleasepoolWrapper: true
        ))
    }
}

class AppleScriptReverseTranspiler: ReverseTranspiling {
    private static let logRegex = try! NSRegularExpression(pattern: "^(\\s*)log\\s+(.+)$")
    private static let setRegex = try! NSRegularExpression(pattern: "^(\\s*)set\\s+(\\w+)\\s+to\\s+(.+)$")
    private static let repeatRegex = try! NSRegularExpression(pattern: "^(\\s*)repeat\\s+with\\s+(\\w+)\\s+from\\s+(\\d+)\\s+to\\s+\\((\\d+)\\s*-\\s*1\\)$")
    private static let ifRegex = try! NSRegularExpression(pattern: "^(\\s*)if\\s+(.+?)\\s+then$")
    private static let elseRegex = try! NSRegularExpression(pattern: "^(\\s*)else$")
    private static let onRegex = try! NSRegularExpression(pattern: "^(\\s*)on\\s+(\\w+)\\(([^)]*)\\)$")
    private static let returnRegex = try! NSRegularExpression(pattern: "^(\\s*)return\\s+(.+)$")
    private static let endRegex = try! NSRegularExpression(pattern: "^(\\s*)end\\s*(\\w*)$")
    private static let commentRegex = try! NSRegularExpression(pattern: "^(\\s*)--\\s*(.*)$")

    func reverseTranspile(_ code: String) -> String? {
        var lines = code.components(separatedBy: "\n")
        lines = lines.filter { !$0.hasPrefix("-- Transpiled from JibJab") }

        var text = lines.joined(separator: "\n")
        text = replaceOutsideStrings(text, " and ", " <&&> ")
        text = replaceOutsideStrings(text, " or ", " <||> ")
        text = replaceOutsideStrings(text, " mod ", " <%> ")
        lines = text.components(separatedBy: "\n")

        var result: [String] = []
        var indentLevel = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces.union(.init(charactersIn: "\t")))
            if trimmed.isEmpty { result.append(""); continue }

            let nsLine = trimmed as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            if let m = Self.commentRegex.firstMatch(in: trimmed, range: range) {
                let comment = nsLine.substring(with: m.range(at: 2))
                result.append("\(indent(indentLevel))@@ \(comment)")
            } else if Self.endRegex.firstMatch(in: trimmed, range: range) != nil {
                if indentLevel > 0 { indentLevel -= 1 }
                result.append("\(indent(indentLevel))<~>>")
            } else if let m = Self.onRegex.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 2))
                let params = nsLine.substring(with: m.range(at: 3))
                result.append("\(indent(indentLevel))<~morph{\(name)(\(params))}>>")
                indentLevel += 1
            } else if let m = Self.repeatRegex.firstMatch(in: trimmed, range: range) {
                let v = nsLine.substring(with: m.range(at: 2))
                let start = nsLine.substring(with: m.range(at: 3))
                let end = nsLine.substring(with: m.range(at: 4))
                result.append("\(indent(indentLevel))<~loop{\(v):\(start)..\(end)}>>")
                indentLevel += 1
            } else if let m = Self.ifRegex.firstMatch(in: trimmed, range: range) {
                let cond = reverseExpr(nsLine.substring(with: m.range(at: 2)))
                result.append("\(indent(indentLevel))<~when{\(cond)}>>")
                indentLevel += 1
            } else if Self.elseRegex.firstMatch(in: trimmed, range: range) != nil {
                result.append("\(indent(indentLevel))<~else>>")
                indentLevel += 1
            } else if let m = Self.returnRegex.firstMatch(in: trimmed, range: range) {
                let val = reverseExpr(nsLine.substring(with: m.range(at: 2)))
                result.append("\(indent(indentLevel))~>yeet{\(reverseFuncCalls(val, style: .applescript))}")
            } else if let m = Self.logRegex.firstMatch(in: trimmed, range: range) {
                let expr = reverseExpr(nsLine.substring(with: m.range(at: 2)))
                result.append("\(indent(indentLevel))~>frob{7a3}::emit(\(reverseFuncCalls(expr, style: .applescript)))")
            } else if let m = Self.setRegex.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 2))
                let val = reverseExpr(nsLine.substring(with: m.range(at: 3)))
                result.append("\(indent(indentLevel))~>snag{\(name)}::val(\(reverseFuncCalls(val, style: .applescript)))")
            } else {
                result.append("\(indent(indentLevel))\(reverseFuncCalls(reverseExpr(trimmed), style: .applescript))")
            }
        }

        while indentLevel > 0 {
            indentLevel -= 1
            result.append("\(indent(indentLevel))<~>>")
        }

        let output = result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output + "\n"
    }
}

// MARK: - Factory

struct ReverseTranspilerFactory {
    private static let transpilers: [String: ReverseTranspiling] = [
        "py": PythonReverseTranspiler(),
        "js": JavaScriptReverseTranspiler(),
        "c": CReverseTranspiler(),
        "cpp": CppReverseTranspiler(),
        "swift": SwiftReverseTranspiler(),
        "objc": ObjCReverseTranspiler(),
        "objcpp": ObjCppReverseTranspiler(),
        "go": GoReverseTranspiler(),
        "applescript": AppleScriptReverseTranspiler(),
    ]

    static func transpiler(for language: String) -> ReverseTranspiling? {
        transpilers[language]
    }
}
