import Foundation
import JJLib

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
    // Reverse operators using jj.json config (order matters - longer patterns first)
    // JavaScript-specific triple operators (not in jj.json, map to same JJ symbols)
    s = replaceOutsideStrings(s, " === ", " \(JJ.operators.eq.symbol) ")
    s = replaceOutsideStrings(s, " !== ", " \(JJ.operators.neq.symbol) ")
    // Multi-char emit operators first to avoid partial matches
    let OP = JJ.operators
    let orderedOps: [(String, String)] = [
        (OP.lte.emit, OP.lte.symbol), (OP.gte.emit, OP.gte.symbol),
        (OP.neq.emit, OP.neq.symbol), (OP.eq.emit, OP.eq.symbol),
        (OP.and.emit, OP.and.symbol), (OP.or.emit, OP.or.symbol),
        (OP.lt.emit, OP.lt.symbol), (OP.gt.emit, OP.gt.symbol),
        (OP.add.emit, OP.add.symbol), (OP.sub.emit, OP.sub.symbol),
        (OP.mul.emit, OP.mul.symbol), (OP.div.emit, OP.div.symbol),
        (OP.mod.emit, OP.mod.symbol),
    ]
    for (emit, symbol) in orderedOps {
        s = replaceOutsideStrings(s, " \(emit) ", " \(symbol) ")
    }

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
            let prevChar: Character
            if let prevIdx = (i > s.startIndex ? s.index(before: i) : nil) {
                prevChar = s[prevIdx]
            } else {
                prevChar = Character(" ")
            }
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
    return JJEmit.invoke(funcName, reversedArgs)
}

private func indent(_ level: Int) -> String {
    String(repeating: "  ", count: level)
}

// MARK: - Python Reverse Transpiler

class PythonReverseTranspiler: ReverseTranspiling {
    private let pyTarget = loadTarget("py")

    private static let printRegex = try? NSRegularExpression(pattern: "^(\\s*)print\\((.+)\\)$")
    private static let varRegex = try? NSRegularExpression(pattern: "^(\\s*)([a-zA-Z_][a-zA-Z0-9_]*)\\s*=\\s*(.+)$")
    private static let forRegex = try? NSRegularExpression(pattern: "^(\\s*)for\\s+(\\w+)\\s+in\\s+range\\((\\d+),\\s*(\\d+)\\):$")
    private static let ifRegex = try? NSRegularExpression(pattern: "^(\\s*)if\\s+(.+):$")
    private static let elseRegex = try? NSRegularExpression(pattern: "^(\\s*)else:$")
    private static let defRegex = try? NSRegularExpression(pattern: "^(\\s*)def\\s+(\\w+)\\(([^)]*)\\):$")
    private static let returnRegex = try? NSRegularExpression(pattern: "^(\\s*)return\\s+(.+)$")
    private static let commentRegex = try? NSRegularExpression(pattern: "^(\\s*)#\\s*(.*)$")

    private static let printBoolRegex = try? NSRegularExpression(
        pattern: #"^(\s*)print\(str\((\w+)\)\.lower\(\)\)$"#
    )
    private static let fstringBoolRegex = try? NSRegularExpression(
        pattern: #"\{str\((\w+)\)\.lower\(\)\}"#
    )

    func reverseTranspile(_ code: String) -> String? {
        var lines = code.components(separatedBy: "\n")

        // Strip header
        lines = lines.filter { line in
            !line.hasPrefix("#!/usr/bin/env python3") &&
            !line.hasPrefix("# Transpiled from JibJab")
        }

        // Pre-process: simplify bool patterns
        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            let leading = String(lines[i].prefix(while: { $0 == " " }))
            let ns = trimmed as NSString
            let range = NSRange(location: 0, length: ns.length)
            // print(str(t).lower()) → print(t)
            if let m = Self.printBoolRegex?.firstMatch(in: trimmed, range: range) {
                let varName = ns.substring(with: m.range(at: 2))
                lines[i] = "\(leading)print(\(varName))"
                continue
            }
            // f-string: {str(t).lower()} → {t}
            if let regex = Self.fstringBoolRegex {
                lines[i] = leading + regex.stringByReplacingMatches(
                    in: trimmed, range: range, withTemplate: "{$1}")
            }
        }

        // Replace Python-specific booleans/operators using target config
        var text = lines.joined(separator: "\n")
        text = replaceOutsideStrings(text, pyTarget.true, JJ.keywords.true)
        text = replaceOutsideStrings(text, pyTarget.false, JJ.keywords.false)
        text = replaceOutsideStrings(text, pyTarget.nil, JJ.keywords.nil)
        text = replaceOutsideStrings(text, " \(pyTarget.and) ", " \(JJ.operators.and.symbol) ")
        text = replaceOutsideStrings(text, " \(pyTarget.or) ", " \(JJ.operators.or.symbol) ")
        text = replaceOutsideStrings(text, pyTarget.not, JJ.operators.not.symbol + " ")
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
                result.append("\(indent(indentLevel))\(JJEmit.end)")
            }

            let nsLine = trimmed as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            if let m = Self.commentRegex?.firstMatch(in: trimmed, range: range) {
                let comment = nsLine.substring(with: m.range(at: 2))
                result.append("\(indent(indentLevel))\(JJEmit.comment) \(comment)")
            } else if let m = Self.defRegex?.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 2))
                let params = nsLine.substring(with: m.range(at: 3))
                result.append("\(indent(indentLevel))\(JJEmit.morph(name, params))")
                indentLevel += 1
            } else if let m = Self.forRegex?.firstMatch(in: trimmed, range: range) {
                let v = nsLine.substring(with: m.range(at: 2))
                let start = nsLine.substring(with: m.range(at: 3))
                let end = nsLine.substring(with: m.range(at: 4))
                result.append("\(indent(indentLevel))\(JJEmit.loop(v, start, end))")
                indentLevel += 1
            } else if let m = Self.ifRegex?.firstMatch(in: trimmed, range: range) {
                let cond = reverseExpr(nsLine.substring(with: m.range(at: 2)))
                result.append("\(indent(indentLevel))\(JJEmit.when(cond))")
                indentLevel += 1
            } else if Self.elseRegex?.firstMatch(in: trimmed, range: range) != nil {
                result.append("\(indent(indentLevel))\(JJEmit.else)")
                indentLevel += 1
            } else if let m = Self.returnRegex?.firstMatch(in: trimmed, range: range) {
                let val = reverseExpr(nsLine.substring(with: m.range(at: 2)))
                result.append("\(indent(indentLevel))\(JJEmit.yeet(reverseFuncCalls(val, style: .python)))")
            } else if let m = Self.printRegex?.firstMatch(in: trimmed, range: range) {
                let expr = reverseExpr(nsLine.substring(with: m.range(at: 2)))
                result.append("\(indent(indentLevel))\(JJEmit.print(reverseFuncCalls(expr, style: .python)))")
            } else if let m = Self.varRegex?.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 2))
                // Skip if the name is a known keyword
                if ["for", "if", "else", "def", "return", "print", "while"].contains(name) { continue }
                let val = reverseExpr(nsLine.substring(with: m.range(at: 3)))
                result.append("\(indent(indentLevel))\(JJEmit.snag(name, reverseFuncCalls(val, style: .python)))")
            } else {
                // Try to reverse standalone function calls
                let reversed = reverseFuncCalls(trimmed, style: .python)
                result.append("\(indent(indentLevel))\(reversed)")
            }
        }

        // Close remaining blocks
        while indentLevel > 0 {
            indentLevel -= 1
            result.append("\(indent(indentLevel))\(JJEmit.end)")
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

    guard let pattern = try? NSRegularExpression(pattern: "\\b([a-zA-Z_][a-zA-Z0-9_]*)\\(([^)]*)\\)") else { return expr }
    let nsExpr = expr as NSString
    var result = expr
    let matches = pattern.matches(in: expr, range: NSRange(location: 0, length: nsExpr.length))

    // Process in reverse to preserve ranges
    for match in matches.reversed() {
        let name = nsExpr.substring(with: match.range(at: 1))
        let args = nsExpr.substring(with: match.range(at: 2))
        if !knownFuncs.contains(name) && !name.isEmpty {
            let replacement = JJEmit.invoke(name, args)
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
        var printPattern: NSRegularExpression?
        var varPattern: NSRegularExpression?
        var forPattern: NSRegularExpression?
        var ifPattern: NSRegularExpression?
        var elsePattern = try? NSRegularExpression(pattern: "^\\}?\\s*else\\s*\\{?$")
        var funcPattern: NSRegularExpression?
        var returnPattern = try? NSRegularExpression(pattern: "^return\\s+(.+?)\\s*;?$")
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

        // Replace booleans/null using JJ keywords from config
        var text = lines.joined(separator: "\n")
        text = replaceOutsideStrings(text, config.trueValue, JJ.keywords.true)
        text = replaceOutsideStrings(text, config.falseValue, JJ.keywords.false)
        if config.nilValue != "0" {
            text = replaceOutsideStrings(text, config.nilValue, JJ.keywords.nil)
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
                result.append("\(indent(indentLevel))\(JJEmit.end)")
                continue
            }

            // Comment
            if trimmed.hasPrefix(config.commentPrefix) {
                let comment = String(trimmed.dropFirst(config.commentPrefix.count)).trimmingCharacters(in: .whitespaces)
                result.append("\(indent(indentLevel))\(JJEmit.comment) \(comment)")
                continue
            }

            // Function definition
            if let m = config.funcPattern?.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 1))
                let params = nsLine.substring(with: m.range(at: 2))
                // Strip type annotations from params
                let cleanParams = stripParamTypes(params, style: config.callStyle)
                result.append("\(indent(indentLevel))\(JJEmit.morph(name, cleanParams))")
                indentLevel += 1
                continue
            }

            // For loop
            if let m = config.forPattern?.firstMatch(in: trimmed, range: range) {
                let v = nsLine.substring(with: m.range(at: 1))
                let start = nsLine.substring(with: m.range(at: 2))
                let end = nsLine.substring(with: m.range(at: 3))
                result.append("\(indent(indentLevel))\(JJEmit.loop(v, start, end))")
                indentLevel += 1
                continue
            }

            // If
            if let m = config.ifPattern?.firstMatch(in: trimmed, range: range) {
                let cond = reverseExpr(nsLine.substring(with: m.range(at: 1)))
                result.append("\(indent(indentLevel))\(JJEmit.when(cond))")
                indentLevel += 1
                continue
            }

            // Else
            if config.elsePattern?.firstMatch(in: trimmed, range: range) != nil {
                result.append("\(indent(indentLevel))\(JJEmit.else)")
                indentLevel += 1
                continue
            }

            // Return
            if let m = config.returnPattern?.firstMatch(in: trimmed, range: range) {
                var val = nsLine.substring(with: m.range(at: 1))
                if val.hasSuffix(";") { val = String(val.dropLast()) }
                val = reverseExpr(val)
                result.append("\(indent(indentLevel))\(JJEmit.yeet(reverseFuncCalls(val, style: config.callStyle)))")
                continue
            }

            // Print
            if let m = config.printPattern?.firstMatch(in: trimmed, range: range) {
                // Support alternation patterns: try group 1 first, fall back to group 2
                let captureRange1 = m.range(at: 1)
                let captureRange2 = m.numberOfRanges > 2 ? m.range(at: 2) : NSRange(location: NSNotFound, length: 0)
                let captured: String
                if captureRange1.location != NSNotFound {
                    captured = nsLine.substring(with: captureRange1)
                } else if captureRange2.location != NSNotFound {
                    captured = nsLine.substring(with: captureRange2)
                } else {
                    continue
                }
                let expr = reverseExpr(captured)
                result.append("\(indent(indentLevel))\(JJEmit.print(reverseFuncCalls(expr, style: config.callStyle)))")
                continue
            }

            // Variable declaration
            if let m = config.varPattern?.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 1))
                var val = nsLine.substring(with: m.range(at: 2))
                if val.hasSuffix(";") { val = String(val.dropLast()) }
                val = reverseExpr(val)
                result.append("\(indent(indentLevel))\(JJEmit.snag(name, reverseFuncCalls(val, style: config.callStyle)))")
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
            result.append("\(indent(indentLevel))\(JJEmit.end)")
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

// MARK: - C-Family Printf Handler

/// Handles printf("format\n", args) with multiple format specifiers by
/// reconstructing them as interpolated strings before the base class processes them.
class CFamilyPrintfReverseTranspiler: BraceReverseTranspiler {
    private static let printfMultiRegex = try? NSRegularExpression(
        pattern: #"^(\s*)printf\("(.+)\\n"(?:,\s*(.+))?\);$"#
    )

    private static let boolTernaryPrintf = try? NSRegularExpression(
        pattern: #"^(\s*)printf\("%s\\n",\s*(\w+)\s*\?\s*"true"\s*:\s*"false"\);$"#
    )

    override func reverseTranspile(_ code: String) -> String? {
        var lines = code.components(separatedBy: "\n")
        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            let leading = String(lines[i].prefix(while: { $0 == " " || $0 == "\t" }))
            let ns = trimmed as NSString
            let range = NSRange(location: 0, length: ns.length)

            // Bool ternary: printf("%s\n", x ? "true" : "false"); → printf("%d\n", x);
            if let m = Self.boolTernaryPrintf?.firstMatch(in: trimmed, range: range) {
                let varName = ns.substring(with: m.range(at: 2))
                lines[i] = "\(leading)printf(\"%d\\n\", \(varName));"
                continue
            }

            // Multi-specifier printf (interpolation)
            if let m = Self.printfMultiRegex?.firstMatch(in: trimmed, range: range) {
                let fmt = ns.substring(with: m.range(at: 2))
                let specifierCount = fmt.components(separatedBy: "%").count - 1
                if specifierCount > 1, m.range(at: 3).location != NSNotFound {
                    let argsStr = ns.substring(with: m.range(at: 3))
                    let args = splitArgs(argsStr)
                    var result = fmt
                    for arg in args {
                        if let r = result.range(of: "%[dsgflv]+", options: .regularExpression) {
                            result = result.replacingCharacters(in: r, with: "{\(arg)}")
                        }
                    }
                    // Strip ternary bool expressions: {x ? "true" : "false"} → {x}
                    let boolTernary = try? NSRegularExpression(pattern: #"\{(\w+) \? "true" : "false"\}"#)
                    if let bt = boolTernary {
                        result = bt.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "{$1}")
                    }
                    lines[i] = "\(leading)printf(\"%s\\n\", \"\(result)\");"
                }
            }
        }
        return super.reverseTranspile(lines.joined(separator: "\n"))
    }

    /// Split args respecting nested parens/ternary expressions
    private func splitArgs(_ s: String) -> [String] {
        var args: [String] = []
        var current = ""
        var depth = 0
        for c in s {
            if c == "(" { depth += 1 }
            if c == ")" { depth -= 1 }
            if c == "," && depth == 0 {
                args.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(c)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(current.trimmingCharacters(in: .whitespaces))
        }
        return args
    }
}

// MARK: - Language-Specific Factories

class CReverseTranspiler: CFamilyPrintfReverseTranspiler {
    init() {
        super.init(config: Config(
            headerPatterns: ["// Transpiled from JibJab", "#include"],
            hasMainWrapper: true,
            mainPattern: "int main()",
            printPattern: try? NSRegularExpression(pattern: "^printf\\(\"%[dslf]\\\\n\",\\s*(.+)\\);$"),
            varPattern: try? NSRegularExpression(pattern: "^(?:int|float|double|char|long|unsigned|short|auto)\\s+(\\w+)\\s*=\\s*(.+);$"),
            forPattern: try? NSRegularExpression(pattern: "^for\\s*\\(int\\s+(\\w+)\\s*=\\s*(\\d+);\\s*\\w+\\s*<\\s*(\\d+);"),
            ifPattern: try? NSRegularExpression(pattern: "^if\\s*\\((.+)\\)\\s*\\{$"),
            funcPattern: try? NSRegularExpression(pattern: "^(?:int|void|float|double)\\s+(\\w+)\\(([^)]*)\\)\\s*\\{$"),
            callStyle: .cFamily,
            forwardDeclPattern: try? NSRegularExpression(pattern: "^(?:int|void|float|double)\\s+\\w+\\([^)]*\\);$"),
            autoreleasepoolWrapper: false
        ))
    }
}

class CppReverseTranspiler: CFamilyPrintfReverseTranspiler {
    private static let coutBoolRegex = try? NSRegularExpression(
        pattern: #"^(\s*)std::cout\s*<<\s*\((\w+)\s*\?\s*"true"\s*:\s*"false"\)\s*<<\s*std::endl;$"#
    )

    init() {
        super.init(config: Config(
            headerPatterns: ["// Transpiled from JibJab", "#include"],
            hasMainWrapper: true,
            mainPattern: "int main()",
            printPattern: try? NSRegularExpression(pattern: "^std::cout\\s*<<\\s*(.+?)\\s*<<\\s*std::endl;$"),
            varPattern: try? NSRegularExpression(pattern: "^(?:int|float|double|char|long|unsigned|auto|bool|string)\\s+(\\w+)\\s*=\\s*(.+);$"),
            forPattern: try? NSRegularExpression(pattern: "^for\\s*\\(int\\s+(\\w+)\\s*=\\s*(\\d+);\\s*\\w+\\s*<\\s*(\\d+);"),
            ifPattern: try? NSRegularExpression(pattern: "^if\\s*\\((.+)\\)\\s*\\{$"),
            funcPattern: try? NSRegularExpression(pattern: "^(?:int|void|float|double|auto)\\s+(\\w+)\\(([^)]*)\\)\\s*\\{$"),
            callStyle: .cFamily,
            forwardDeclPattern: try? NSRegularExpression(pattern: "^(?:int|void|float|double|auto)\\s+\\w+\\([^)]*\\);$")
        ))
    }

    override func reverseTranspile(_ code: String) -> String? {
        // Pre-process: strip cout bool ternary to plain cout
        var lines = code.components(separatedBy: "\n")
        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            let leading = String(lines[i].prefix(while: { $0 == " " || $0 == "\t" }))
            let ns = trimmed as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = Self.coutBoolRegex?.firstMatch(in: trimmed, range: range) {
                let varName = ns.substring(with: m.range(at: 2))
                lines[i] = "\(leading)std::cout << \(varName) << std::endl;"
            }
        }
        return super.reverseTranspile(lines.joined(separator: "\n"))
    }
}

class JavaScriptReverseTranspiler: BraceReverseTranspiler {
    init() {
        let target = loadTarget("js")
        super.init(config: Config(
            headerPatterns: ["// Transpiled from JibJab"],
            hasMainWrapper: false,
            printPattern: try? NSRegularExpression(pattern: "^console\\.log\\((.+)\\);$"),
            varPattern: try? NSRegularExpression(pattern: "^(?:let|const|var)\\s+(\\w+)\\s*=\\s*(.+);$"),
            forPattern: try? NSRegularExpression(pattern: "^for\\s*\\(let\\s+(\\w+)\\s*=\\s*(\\d+);\\s*\\w+\\s*<\\s*(\\d+);"),
            ifPattern: try? NSRegularExpression(pattern: "^if\\s*\\((.+)\\)\\s*\\{$"),
            funcPattern: try? NSRegularExpression(pattern: "^function\\s+(\\w+)\\(([^)]*)\\)\\s*\\{$"),
            trueValue: target.true,
            falseValue: target.false,
            nilValue: target.nil,
            callStyle: .javascript
        ))
    }
}

class SwiftReverseTranspiler: BraceReverseTranspiler {
    init() {
        super.init(config: Config(
            headerPatterns: ["// Transpiled from JibJab"],
            hasMainWrapper: false,
            printPattern: try? NSRegularExpression(pattern: "^print\\((.+)\\)$"),
            varPattern: try? NSRegularExpression(pattern: "^var\\s+(\\w+)(?:\\s*:\\s*\\w+)?\\s*=\\s*(.+)$"),
            forPattern: try? NSRegularExpression(pattern: "^for\\s+(\\w+)\\s+in\\s+(\\d+)\\.\\.<(\\d+)\\s*\\{$"),
            ifPattern: try? NSRegularExpression(pattern: "^if\\s+(.+?)\\s*\\{$"),
            funcPattern: try? NSRegularExpression(pattern: "^func\\s+(\\w+)\\(([^)]*)\\)(?:\\s*->\\s*\\w+)?\\s*\\{$"),
            callStyle: .swift,
            stripSemicolons: false
        ))
    }
}

class GoReverseTranspiler: BraceReverseTranspiler {
    private static let printfRegex = try? NSRegularExpression(
        pattern: #"^(\s*)fmt\.Printf\("(.+)\\n"(?:,\s*(.+))?\)$"#
    )

    init() {
        super.init(config: Config(
            headerPatterns: ["// Transpiled from JibJab", "package main", "import"],
            hasMainWrapper: true,
            mainPattern: "func main()",
            printPattern: try? NSRegularExpression(pattern: "^fmt\\.Println\\((.+)\\)$"),
            varPattern: try? NSRegularExpression(pattern: "^(?:var\\s+)?(\\w+)\\s*:?=\\s*(.+)$"),
            forPattern: try? NSRegularExpression(pattern: "^for\\s+(\\w+)\\s*:=\\s*(\\d+);\\s*\\w+\\s*<\\s*(\\d+);"),
            ifPattern: try? NSRegularExpression(pattern: "^if\\s+(.+?)\\s*\\{$"),
            funcPattern: try? NSRegularExpression(pattern: "^func\\s+(\\w+)\\(([^)]*)\\)(?:\\s*\\w+)?\\s*\\{$"),
            callStyle: .go,
            stripSemicolons: false
        ))
    }

    override func reverseTranspile(_ code: String) -> String? {
        // Pre-process: convert fmt.Printf with %v placeholders to fmt.Println with interpolation braces
        var lines = code.components(separatedBy: "\n")
        // Also strip multi-line import block: "fmt", "math", bare )
        var inImportBlock = false
        lines = lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Track multi-line import block
            if trimmed == "import (" { inImportBlock = true; return nil }
            if inImportBlock {
                if trimmed == ")" { inImportBlock = false; return nil }
                return nil  // skip "fmt", "math" etc.
            }
            return line
        }
        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            let leading = String(lines[i].prefix(while: { $0 == " " || $0 == "\t" }))
            let ns = trimmed as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = Self.printfRegex?.firstMatch(in: trimmed, range: range) {
                let fmt = ns.substring(with: m.range(at: 2))
                let argsRange = m.range(at: 3)
                if argsRange.location != NSNotFound {
                    let argsStr = ns.substring(with: argsRange)
                    let args = argsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    // Replace %v with {argName}
                    var result = fmt
                    for arg in args {
                        if let r = result.range(of: "%v") {
                            result = result.replacingCharacters(in: r, with: "{\(arg)}")
                        }
                    }
                    lines[i] = "\(leading)fmt.Println(\"\(result)\")"
                } else {
                    lines[i] = "\(leading)fmt.Println(\"\(fmt)\")"
                }
            }
        }
        return super.reverseTranspile(lines.joined(separator: "\n"))
    }
}

class ObjCReverseTranspiler: CFamilyPrintfReverseTranspiler {
    init() {
        let target = loadTarget("objc")
        super.init(config: Config(
            headerPatterns: ["// Transpiled from JibJab", "#import", "#include"],
            hasMainWrapper: true,
            mainPattern: "int main(",
            printPattern: try? NSRegularExpression(pattern: "^printf\\(\"%[a-z]*\\\\n\",\\s*(?:\\(long\\))?(.+)\\);$"),
            varPattern: try? NSRegularExpression(pattern: "^(?:NSInteger|int|float|double|long|BOOL|NSUInteger)\\s+(\\w+)\\s*=\\s*(.+);$"),
            forPattern: try? NSRegularExpression(pattern: "^for\\s*\\(int\\s+(\\w+)\\s*=\\s*(\\d+);\\s*\\w+\\s*<\\s*(\\d+);"),
            ifPattern: try? NSRegularExpression(pattern: "^if\\s*\\((.+)\\)\\s*\\{$"),
            funcPattern: try? NSRegularExpression(pattern: "^(?:NSInteger|int|void|float|double)\\s+(\\w+)\\(([^)]*)\\)\\s*\\{$"),
            trueValue: target.true,
            falseValue: target.false,
            nilValue: target.nil,
            callStyle: .cFamily,
            forwardDeclPattern: try? NSRegularExpression(pattern: "^(?:NSInteger|int|void|float|double)\\s+\\w+\\([^)]*\\);$"),
            autoreleasepoolWrapper: true
        ))
    }
}

class ObjCppReverseTranspiler: CFamilyPrintfReverseTranspiler {
    private static let coutBoolRegex = try? NSRegularExpression(
        pattern: #"^(\s*)std::cout\s*<<\s*\((\w+)\s*\?\s*"true"\s*:\s*"false"\)\s*<<\s*std::endl;$"#
    )

    init() {
        super.init(config: Config(
            headerPatterns: ["// Transpiled from JibJab", "#import", "#include"],
            hasMainWrapper: true,
            mainPattern: "int main(",
            printPattern: try? NSRegularExpression(pattern: "^(?:printf\\(\"%[a-z]*\\\\n\",\\s*(?:\\(long\\))?(.+)\\)|std::cout\\s*<<\\s*(.+?)\\s*<<\\s*std::endl);$"),
            varPattern: try? NSRegularExpression(pattern: "^(?:int|float|double|auto|bool|long)\\s+(\\w+)\\s*=\\s*(.+);$"),
            forPattern: try? NSRegularExpression(pattern: "^for\\s*\\(int\\s+(\\w+)\\s*=\\s*(\\d+);\\s*\\w+\\s*<\\s*(\\d+);"),
            ifPattern: try? NSRegularExpression(pattern: "^if\\s*\\((.+)\\)\\s*\\{$"),
            funcPattern: try? NSRegularExpression(pattern: "^(?:int|void|float|double|auto)\\s+(\\w+)\\(([^)]*)\\)\\s*\\{$"),
            callStyle: .cFamily,
            forwardDeclPattern: try? NSRegularExpression(pattern: "^(?:int|void|float|double|auto)\\s+\\w+\\([^)]*\\);$"),
            autoreleasepoolWrapper: true
        ))
    }

    override func reverseTranspile(_ code: String) -> String? {
        var lines = code.components(separatedBy: "\n")
        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            let leading = String(lines[i].prefix(while: { $0 == " " || $0 == "\t" }))
            let ns = trimmed as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = Self.coutBoolRegex?.firstMatch(in: trimmed, range: range) {
                let varName = ns.substring(with: m.range(at: 2))
                lines[i] = "\(leading)std::cout << \(varName) << std::endl;"
            }
        }
        return super.reverseTranspile(lines.joined(separator: "\n"))
    }
}

class AppleScriptReverseTranspiler: ReverseTranspiling {
    private let asTarget = loadTarget("applescript")

    private static let logRegex = try? NSRegularExpression(pattern: "^(\\s*)log\\s+(.+)$")
    private static let setRegex = try? NSRegularExpression(pattern: "^(\\s*)set\\s+(\\w+)\\s+to\\s+(.+)$")
    private static let repeatRegex = try? NSRegularExpression(pattern: "^(\\s*)repeat\\s+with\\s+(\\w+)\\s+from\\s+(\\d+)\\s+to\\s+\\((\\d+)\\s*-\\s*1\\)$")
    private static let ifRegex = try? NSRegularExpression(pattern: "^(\\s*)if\\s+(.+?)\\s+then$")
    private static let elseRegex = try? NSRegularExpression(pattern: "^(\\s*)else$")
    private static let onRegex = try? NSRegularExpression(pattern: "^(\\s*)on\\s+(\\w+)\\(([^)]*)\\)$")
    private static let returnRegex = try? NSRegularExpression(pattern: "^(\\s*)return\\s+(.+)$")
    private static let endRegex = try? NSRegularExpression(pattern: "^(\\s*)end\\s*(\\w*)$")
    private static let commentRegex = try? NSRegularExpression(pattern: "^(\\s*)--\\s*(.*)$")

    func reverseTranspile(_ code: String) -> String? {
        var lines = code.components(separatedBy: "\n")
        lines = lines.filter { !$0.hasPrefix("-- Transpiled from JibJab") }

        // Replace AppleScript-specific operators using target config
        var text = lines.joined(separator: "\n")
        text = replaceOutsideStrings(text, " \(asTarget.and) ", " \(JJ.operators.and.symbol) ")
        text = replaceOutsideStrings(text, " \(asTarget.or) ", " \(JJ.operators.or.symbol) ")
        text = replaceOutsideStrings(text, " \(asTarget.mod) ", " \(JJ.operators.mod.symbol) ")
        lines = text.components(separatedBy: "\n")

        var result: [String] = []
        var indentLevel = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces.union(.init(charactersIn: "\t")))
            if trimmed.isEmpty { result.append(""); continue }

            let nsLine = trimmed as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            if let m = Self.commentRegex?.firstMatch(in: trimmed, range: range) {
                let comment = nsLine.substring(with: m.range(at: 2))
                result.append("\(indent(indentLevel))\(JJEmit.comment) \(comment)")
            } else if Self.endRegex?.firstMatch(in: trimmed, range: range) != nil {
                if indentLevel > 0 { indentLevel -= 1 }
                result.append("\(indent(indentLevel))\(JJEmit.end)")
            } else if let m = Self.onRegex?.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 2))
                let params = nsLine.substring(with: m.range(at: 3))
                result.append("\(indent(indentLevel))\(JJEmit.morph(name, params))")
                indentLevel += 1
            } else if let m = Self.repeatRegex?.firstMatch(in: trimmed, range: range) {
                let v = nsLine.substring(with: m.range(at: 2))
                let start = nsLine.substring(with: m.range(at: 3))
                let end = nsLine.substring(with: m.range(at: 4))
                result.append("\(indent(indentLevel))\(JJEmit.loop(v, start, end))")
                indentLevel += 1
            } else if let m = Self.ifRegex?.firstMatch(in: trimmed, range: range) {
                let cond = reverseExpr(nsLine.substring(with: m.range(at: 2)))
                result.append("\(indent(indentLevel))\(JJEmit.when(cond))")
                indentLevel += 1
            } else if Self.elseRegex?.firstMatch(in: trimmed, range: range) != nil {
                result.append("\(indent(indentLevel))\(JJEmit.else)")
                indentLevel += 1
            } else if let m = Self.returnRegex?.firstMatch(in: trimmed, range: range) {
                let val = reverseExpr(nsLine.substring(with: m.range(at: 2)))
                result.append("\(indent(indentLevel))\(JJEmit.yeet(reverseFuncCalls(val, style: .applescript)))")
            } else if let m = Self.logRegex?.firstMatch(in: trimmed, range: range) {
                let expr = reverseExpr(nsLine.substring(with: m.range(at: 2)))
                result.append("\(indent(indentLevel))\(JJEmit.print(reverseFuncCalls(expr, style: .applescript)))")
            } else if let m = Self.setRegex?.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 2))
                let val = reverseExpr(nsLine.substring(with: m.range(at: 3)))
                result.append("\(indent(indentLevel))\(JJEmit.snag(name, reverseFuncCalls(val, style: .applescript)))")
            } else {
                result.append("\(indent(indentLevel))\(reverseFuncCalls(reverseExpr(trimmed), style: .applescript))")
            }
        }

        while indentLevel > 0 {
            indentLevel -= 1
            result.append("\(indent(indentLevel))\(JJEmit.end)")
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
