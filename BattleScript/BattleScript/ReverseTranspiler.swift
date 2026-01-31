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
    // JavaScript-specific operators from JS target config
    let jsTarget = loadTarget("js")
    if jsTarget.eq != "==" {
        s = replaceOutsideStrings(s, " \(jsTarget.eq) ", " \(JJ.operators.eq.symbol) ")
    }
    if jsTarget.neq != "!=" {
        s = replaceOutsideStrings(s, " \(jsTarget.neq) ", " \(JJ.operators.neq.symbol) ")
    }
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

private let numPrefix = JJ.literals.numberPrefix
private let numPrefixChar = JJ.literals.numberPrefix.first ?? Character("#")

private func reverseNumbers(_ s: String) -> String {
    let delim = Character(JJ.literals.stringDelim)
    var result = ""
    var inString = false
    var i = s.startIndex
    while i < s.endIndex {
        let c = s[i]
        if c == delim { inString.toggle(); result.append(c); i = s.index(after: i); continue }
        if inString { result.append(c); i = s.index(after: i); continue }

        if c.isNumber || (c == "-" && i < s.index(before: s.endIndex) && s[s.index(after: i)].isNumber) {
            let prevChar: Character
            if let prevIdx = (i > s.startIndex ? s.index(before: i) : nil) {
                prevChar = s[prevIdx]
            } else {
                prevChar = Character(" ")
            }
            if prevChar == numPrefixChar || prevChar.isLetter || prevChar == "_" {
                result.append(c); i = s.index(after: i); continue
            }
            var numStr = String(c)
            var j = s.index(after: i)
            while j < s.endIndex && (s[j].isNumber || s[j] == ".") {
                numStr.append(s[j])
                j = s.index(after: j)
            }
            let nextChar = j < s.endIndex ? s[j] : Character(" ")
            if !nextChar.isLetter && nextChar != "_" {
                result += numPrefix
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
    private let target = loadTarget("py")

    private static let pyTarget = loadTarget("py")
    private static let printRegex = ReversePatterns.printPattern(pyTarget)
    private static let varRegex = ReversePatterns.varPattern(pyTarget)
    private static let forRegex = ReversePatterns.forPattern(pyTarget)
    private static let ifRegex = ReversePatterns.ifPattern(pyTarget)
    private static let elseRegex = ReversePatterns.elsePattern(pyTarget)
    private static let defRegex = ReversePatterns.funcPattern(pyTarget)
    private static let returnRegex = ReversePatterns.returnPattern(pyTarget)
    private static let commentRegex = ReversePatterns.commentPattern(pyTarget)

    private static let printBoolRegex = ReversePatterns.pythonPrintBoolPattern(pyTarget)
    private static let fstringBoolRegex = ReversePatterns.pythonFStringBoolPattern(pyTarget)

    func reverseTranspile(_ code: String) -> String? {
        var lines = code.components(separatedBy: "\n")

        // Strip header using config
        let headerPats = ReversePatterns.headerPatterns(target)
        lines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for pattern in headerPats {
                if trimmed.hasPrefix(pattern) || trimmed == pattern { return false }
            }
            return true
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
        text = replaceOutsideStrings(text, target.true, JJ.keywords.true)
        text = replaceOutsideStrings(text, target.false, JJ.keywords.false)
        text = replaceOutsideStrings(text, target.nil, JJ.keywords.nil)
        // Replace operators from config
        for (find, replace) in ReversePatterns.operatorReplacements(target) {
            text = replaceOutsideStrings(text, find, replace)
        }
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
                let comment = nsLine.substring(with: m.range(at: 1))
                result.append("\(indent(indentLevel))\(JJEmit.comment) \(comment)")
            } else if let m = Self.defRegex?.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 1))
                let params = nsLine.substring(with: m.range(at: 2))
                result.append("\(indent(indentLevel))\(JJEmit.morph(name, params))")
                indentLevel += 1
            } else if let m = Self.forRegex?.firstMatch(in: trimmed, range: range) {
                let v = nsLine.substring(with: m.range(at: 1))
                let start = nsLine.substring(with: m.range(at: 2))
                let end = nsLine.substring(with: m.range(at: 3))
                result.append("\(indent(indentLevel))\(JJEmit.loop(v, start, end))")
                indentLevel += 1
            } else if let m = Self.ifRegex?.firstMatch(in: trimmed, range: range) {
                let cond = reverseExpr(nsLine.substring(with: m.range(at: 1)))
                result.append("\(indent(indentLevel))\(JJEmit.when(cond))")
                indentLevel += 1
            } else if Self.elseRegex?.firstMatch(in: trimmed, range: range) != nil {
                result.append("\(indent(indentLevel))\(JJEmit.else)")
                indentLevel += 1
            } else if let m = Self.returnRegex?.firstMatch(in: trimmed, range: range) {
                let val = reverseExpr(nsLine.substring(with: m.range(at: 1)))
                result.append("\(indent(indentLevel))\(JJEmit.yeet(reverseFuncCalls(val, target: target)))")
            } else if let m = Self.printRegex?.firstMatch(in: trimmed, range: range) {
                let expr = reverseExpr(nsLine.substring(with: m.range(at: 1)))
                result.append("\(indent(indentLevel))\(JJEmit.print(reverseFuncCalls(expr, target: target)))")
            } else if let m = Self.varRegex?.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 1))
                // Skip if the name is a known keyword (derived from target config templates)
                if ReversePatterns.knownFunctions(target).contains(name) { continue }
                let val = reverseExpr(nsLine.substring(with: m.range(at: 2)))
                result.append("\(indent(indentLevel))\(JJEmit.snag(name, reverseFuncCalls(val, target: target)))")
            } else {
                // Try to reverse standalone function calls
                let reversed = reverseFuncCalls(trimmed, target: target)
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

    init(from target: TargetConfig) {
        switch target.name {
        case "Python": self = .python
        case "Swift": self = .swift
        case "Go": self = .go
        case "JavaScript": self = .javascript
        case "AppleScript": self = .applescript
        default: self = .cFamily
        }
    }
}

private func reverseFuncCalls(_ expr: String, target: TargetConfig) -> String {
    let knownFuncs = ReversePatterns.knownFunctions(target)

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
        var target: TargetConfig
        var headerPatterns: [String]
        var hasMainWrapper: Bool
        var mainPattern: String
        var printPattern: NSRegularExpression?
        var varPattern: NSRegularExpression?
        var forPattern: NSRegularExpression?
        var ifPattern: NSRegularExpression?
        var elsePattern: NSRegularExpression?
        var funcPattern: NSRegularExpression?
        var returnPattern: NSRegularExpression?
        var commentPrefix: String
        var trueValue: String
        var falseValue: String
        var nilValue: String
        var callStyle: CallStyle
        var forwardDeclPattern: NSRegularExpression?
        var stripSemicolons: Bool
        var autoreleasepoolWrapper: Bool

        /// Build a Config entirely from a TargetConfig — no hard-coded defaults
        init(from target: TargetConfig) {
            self.target = target
            self.headerPatterns = ReversePatterns.headerPatterns(target)
            self.hasMainWrapper = target.main != nil
            self.mainPattern = ReversePatterns.mainSignature(target) ?? ""
            self.printPattern = ReversePatterns.printPattern(target)
            self.varPattern = ReversePatterns.varPattern(target)
            self.forPattern = ReversePatterns.forPattern(target)
            self.ifPattern = ReversePatterns.ifPattern(target)
            self.elsePattern = ReversePatterns.elsePattern(target)
            self.funcPattern = ReversePatterns.funcPattern(target)
            self.returnPattern = ReversePatterns.returnPattern(target)
            self.commentPrefix = ReversePatterns.commentPrefix(target)
            self.trueValue = target.true
            self.falseValue = target.false
            self.nilValue = target.nil
            self.callStyle = CallStyle(from: target)
            self.forwardDeclPattern = ReversePatterns.funcDeclPattern(target)
            self.stripSemicolons = target.return.hasSuffix(";")
            self.autoreleasepoolWrapper = ReversePatterns.hasAutoreleasepool(target)
        }
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
        // Replace target-specific operators
        for (find, replace) in ReversePatterns.operatorReplacements(config.target) {
            text = replaceOutsideStrings(text, find, replace)
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

            // Skip main wrapper (patterns derived from target config)
            let blockEnd = ReversePatterns.blockEndString(config.target)
            let mainReturn = ReversePatterns.mainReturnStatement(config.target)
            if config.hasMainWrapper {
                if trimmed.contains(config.mainPattern) && trimmed.contains("{") {
                    inMain = true; skipReturn0 = true; continue
                }
                if config.autoreleasepoolWrapper && config.target.main?.contains("@autoreleasepool") == true && trimmed.contains("@autoreleasepool") && trimmed.contains("{") {
                    inAutoreleasepool = true; continue
                }
                if inMain && skipReturn0 && trimmed == mainReturn { skipReturn0 = false; continue }
                if inMain && trimmed == blockEnd {
                    if inAutoreleasepool { inAutoreleasepool = false; continue }
                    inMain = false; continue
                }
            }

            let nsLine = trimmed as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            // Closing block (e.g. "}" for C-family)
            if trimmed == blockEnd {
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
                result.append("\(indent(indentLevel))\(JJEmit.yeet(reverseFuncCalls(val, target: config.target)))")
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
                result.append("\(indent(indentLevel))\(JJEmit.print(reverseFuncCalls(expr, target: config.target)))")
                continue
            }

            // Variable declaration
            if let m = config.varPattern?.firstMatch(in: trimmed, range: range) {
                // Find the first valid capture groups for name and value
                var name: String?
                var val: String?
                for g in stride(from: 1, to: m.numberOfRanges, by: 2) {
                    if m.range(at: g).location != NSNotFound && m.numberOfRanges > g + 1 && m.range(at: g + 1).location != NSNotFound {
                        name = nsLine.substring(with: m.range(at: g))
                        val = nsLine.substring(with: m.range(at: g + 1))
                        break
                    }
                }
                // Fallback to groups 1 and 2
                if name == nil && m.range(at: 1).location != NSNotFound {
                    name = nsLine.substring(with: m.range(at: 1))
                    if m.numberOfRanges > 2 && m.range(at: 2).location != NSNotFound {
                        val = nsLine.substring(with: m.range(at: 2))
                    }
                }
                if let name = name, let val = val {
                    var cleanVal = val
                    if cleanVal.hasSuffix(";") { cleanVal = String(cleanVal.dropLast()) }
                    cleanVal = reverseExpr(cleanVal)
                    result.append("\(indent(indentLevel))\(JJEmit.snag(name, reverseFuncCalls(cleanVal, target: config.target)))")
                    continue
                }
            }

            // Unrecognized - pass through as comment
            var cleaned = trimmed
            if cleaned.hasSuffix(";") { cleaned = String(cleaned.dropLast()) }
            result.append("\(indent(indentLevel))\(reverseFuncCalls(reverseExpr(cleaned), target: config.target))")
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
    let printfTarget: TargetConfig

    init(config: Config, printfTarget: TargetConfig) {
        self.printfTarget = printfTarget
        super.init(config: config)
    }

    private lazy var printfMultiRegex: NSRegularExpression? = {
        ReversePatterns.printfMultiPattern(printfTarget)
    }()

    private lazy var boolTernaryPrintf: NSRegularExpression? = {
        ReversePatterns.printfBoolTernaryPattern(printfTarget)
    }()

    private lazy var inlineBoolTernary: NSRegularExpression? = {
        ReversePatterns.inlineBoolTernaryPattern()
    }()

    override func reverseTranspile(_ code: String) -> String? {
        var lines = code.components(separatedBy: "\n")
        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            let leading = String(lines[i].prefix(while: { $0 == " " || $0 == "\t" }))
            let ns = trimmed as NSString
            let range = NSRange(location: 0, length: ns.length)

            // Bool ternary: printf("%s\n", x ? "true" : "false"); → printf("%d\n", x);
            if let m = boolTernaryPrintf?.firstMatch(in: trimmed, range: range) {
                let varName = ns.substring(with: m.range(at: 2))
                let replacement = ReversePatterns.printfIntReplacement(printfTarget, varName: varName)
                lines[i] = "\(leading)\(replacement)"
                continue
            }

            // Multi-specifier printf (interpolation)
            if let m = printfMultiRegex?.firstMatch(in: trimmed, range: range) {
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
                    // Strip ternary bool expressions using config-derived pattern
                    if let bt = inlineBoolTernary {
                        result = bt.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "{$1}")
                    }
                    // Build the string-print replacement from config
                    let strPrint = printfTarget.printStr.replacingOccurrences(of: "{expr}", with: "\"\(result)\"")
                    lines[i] = "\(leading)\(strPrint)"
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
        let target = loadTarget("c")
        super.init(config: Config(from: target), printfTarget: target)
    }
}

class CppReverseTranspiler: CFamilyPrintfReverseTranspiler {
    private static let cppTarget = loadTarget("cpp")
    private static let coutBoolRegex = ReversePatterns.coutBoolTernaryPattern(cppTarget)

    init() {
        let target = Self.cppTarget
        super.init(config: Config(from: target), printfTarget: target)
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
                if let replacement = ReversePatterns.coutReplacement(Self.cppTarget, varName: varName) {
                    lines[i] = "\(leading)\(replacement)"
                }
            }
        }
        return super.reverseTranspile(lines.joined(separator: "\n"))
    }
}

class JavaScriptReverseTranspiler: BraceReverseTranspiler {
    init() {
        let target = loadTarget("js")
        super.init(config: Config(from: target))
    }
}

class SwiftReverseTranspiler: BraceReverseTranspiler {
    init() {
        let target = loadTarget("swift")
        super.init(config: Config(from: target))
    }
}

class GoReverseTranspiler: BraceReverseTranspiler {
    private static let goTarget = loadTarget("go")
    private static let printfRegex = ReversePatterns.fmtPrintfPattern(goTarget)

    init() {
        let target = Self.goTarget
        super.init(config: Config(from: target))
    }

    override func reverseTranspile(_ code: String) -> String? {
        // Pre-process: convert fmt.Printf with %v placeholders to fmt.Println with interpolation braces
        var lines = code.components(separatedBy: "\n")
        // Strip multi-line import block (Go-specific header content)
        var inImportBlock = false
        lines = lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "import (" { inImportBlock = true; return nil }
            if inImportBlock {
                if trimmed == ")" { inImportBlock = false; return nil }
                return nil
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
                // Build the replacement using the target's printStr template
                let printlnTemplate = Self.goTarget.printStr
                if argsRange.location != NSNotFound {
                    let argsStr = ns.substring(with: argsRange)
                    let args = argsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    var result = fmt
                    for arg in args {
                        if let r = result.range(of: "%v") {
                            result = result.replacingCharacters(in: r, with: "{\(arg)}")
                        }
                    }
                    lines[i] = "\(leading)\(printlnTemplate.replacingOccurrences(of: "{expr}", with: "\"\(result)\""))"
                } else {
                    lines[i] = "\(leading)\(printlnTemplate.replacingOccurrences(of: "{expr}", with: "\"\(fmt)\""))"
                }
            }
        }
        return super.reverseTranspile(lines.joined(separator: "\n"))
    }
}

class ObjCReverseTranspiler: CFamilyPrintfReverseTranspiler {
    init() {
        let target = loadTarget("objc")
        super.init(config: Config(from: target), printfTarget: target)
    }
}

class ObjCppReverseTranspiler: CFamilyPrintfReverseTranspiler {
    private static let objcppTarget = loadTarget("objcpp")
    private static let coutBoolRegex = ReversePatterns.coutBoolTernaryPattern(objcppTarget)

    init() {
        let target = Self.objcppTarget
        // ObjC++ uses dual print (printf + cout) so override print pattern
        var config = Config(from: target)
        config.printPattern = ReversePatterns.dualPrintPattern(printf: target, cout: target)
        super.init(config: config, printfTarget: target)
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
                if let replacement = ReversePatterns.coutReplacement(Self.objcppTarget, varName: varName) {
                    lines[i] = "\(leading)\(replacement)"
                }
            }
        }
        return super.reverseTranspile(lines.joined(separator: "\n"))
    }
}

class AppleScriptReverseTranspiler: ReverseTranspiling {
    private let target = loadTarget("applescript")

    private static let asTarget = loadTarget("applescript")
    private static let logRegex = ReversePatterns.printPattern(asTarget)
    private static let setRegex = ReversePatterns.varPattern(asTarget)
    private static let repeatRegex = ReversePatterns.forPattern(asTarget)
    private static let ifRegex = ReversePatterns.ifPattern(asTarget)
    private static let elseRegex = ReversePatterns.elsePattern(asTarget)
    private static let onRegex = ReversePatterns.funcPattern(asTarget)
    private static let returnRegex = ReversePatterns.returnPattern(asTarget)
    private static let endRegex = try? NSRegularExpression(pattern: "^end\\s*(\\w*)$")
    private static let commentRegex = ReversePatterns.commentPattern(asTarget)

    func reverseTranspile(_ code: String) -> String? {
        var lines = code.components(separatedBy: "\n")

        // Strip header using config
        let headerPats = ReversePatterns.headerPatterns(target)
        lines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for pattern in headerPats {
                if trimmed.hasPrefix(pattern) || trimmed == pattern { return false }
            }
            return true
        }

        // Replace AppleScript-specific operators using config
        var text = lines.joined(separator: "\n")
        for (find, replace) in ReversePatterns.operatorReplacements(target) {
            text = replaceOutsideStrings(text, find, replace)
        }
        lines = text.components(separatedBy: "\n")

        var result: [String] = []
        var indentLevel = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces.union(.init(charactersIn: "\t")))
            if trimmed.isEmpty { result.append(""); continue }

            let nsLine = trimmed as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            if let m = Self.commentRegex?.firstMatch(in: trimmed, range: range) {
                let comment = nsLine.substring(with: m.range(at: 1))
                result.append("\(indent(indentLevel))\(JJEmit.comment) \(comment)")
            } else if Self.endRegex?.firstMatch(in: trimmed, range: range) != nil {
                if indentLevel > 0 { indentLevel -= 1 }
                result.append("\(indent(indentLevel))\(JJEmit.end)")
            } else if let m = Self.onRegex?.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 1))
                let params = nsLine.substring(with: m.range(at: 2))
                result.append("\(indent(indentLevel))\(JJEmit.morph(name, params))")
                indentLevel += 1
            } else if let m = Self.repeatRegex?.firstMatch(in: trimmed, range: range) {
                let v = nsLine.substring(with: m.range(at: 1))
                let start = nsLine.substring(with: m.range(at: 2))
                let end = nsLine.substring(with: m.range(at: 3))
                result.append("\(indent(indentLevel))\(JJEmit.loop(v, start, end))")
                indentLevel += 1
            } else if let m = Self.ifRegex?.firstMatch(in: trimmed, range: range) {
                let cond = reverseExpr(nsLine.substring(with: m.range(at: 1)))
                result.append("\(indent(indentLevel))\(JJEmit.when(cond))")
                indentLevel += 1
            } else if Self.elseRegex?.firstMatch(in: trimmed, range: range) != nil {
                result.append("\(indent(indentLevel))\(JJEmit.else)")
                indentLevel += 1
            } else if let m = Self.returnRegex?.firstMatch(in: trimmed, range: range) {
                let val = reverseExpr(nsLine.substring(with: m.range(at: 1)))
                result.append("\(indent(indentLevel))\(JJEmit.yeet(reverseFuncCalls(val, target: target)))")
            } else if let m = Self.logRegex?.firstMatch(in: trimmed, range: range) {
                let expr = reverseExpr(nsLine.substring(with: m.range(at: 1)))
                result.append("\(indent(indentLevel))\(JJEmit.print(reverseFuncCalls(expr, target: target)))")
            } else if let m = Self.setRegex?.firstMatch(in: trimmed, range: range) {
                let name = nsLine.substring(with: m.range(at: 1))
                let val = reverseExpr(nsLine.substring(with: m.range(at: 2)))
                result.append("\(indent(indentLevel))\(JJEmit.snag(name, reverseFuncCalls(val, target: target)))")
            } else {
                result.append("\(indent(indentLevel))\(reverseFuncCalls(reverseExpr(trimmed), target: target))")
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
