/// JibJab Lexer - Tokenizes JJ source code
/// Uses shared language definition from common/jj.json via JJConfig
import Foundation

public class Lexer {
    private let source: String
    private var pos: String.Index
    private var line: Int = 1
    private var col: Int = 1
    private var tokens: [Token] = []

    public init(source: String) {
        self.source = source
        self.pos = source.startIndex
    }

    private func peek(offset: Int = 0) -> Character? {
        guard let idx = source.index(pos, offsetBy: offset, limitedBy: source.endIndex),
              idx < source.endIndex else { return nil }
        return source[idx]
    }

    private func advance(count: Int = 1) -> String {
        var result = ""
        for _ in 0..<count {
            guard pos < source.endIndex else { break }
            let ch = source[pos]
            result.append(ch)
            if ch == "\n" {
                line += 1
                col = 1
            } else {
                col += 1
            }
            pos = source.index(after: pos)
        }
        return result
    }

    private func remaining() -> Substring {
        return source[pos...]
    }

    private func match(_ pattern: String) -> String? {
        if remaining().hasPrefix(pattern) {
            return advance(count: pattern.count)
        }
        return nil
    }

    private func matchRegex(_ pattern: String) -> String? {
        let remaining = self.remaining()
        guard let regex = try? NSRegularExpression(pattern: "^" + pattern),
              let match = regex.firstMatch(in: String(remaining), range: NSRange(remaining.startIndex..., in: remaining)) else {
            return nil
        }
        let matchLength = match.range.length
        return advance(count: matchLength)
    }

    private func addToken(_ type: TokenType, value: Any? = nil, numericType: String? = nil) {
        tokens.append(Token(type: type, value: value, line: line, col: col, numericType: numericType))
    }

    public func tokenize() -> [Token] {
        while pos < source.endIndex {
            scanToken()
        }
        addToken(.eof)
        return tokens
    }

    private func scanToken() {
        // Skip whitespace (except newlines)
        while let ch = peek(), ch == " " || ch == "\t" || ch == "\r" {
            _ = advance()
        }

        guard pos < source.endIndex else { return }

        // Comments
        if match(JJ.literals.comment) != nil {
            // Skip leading whitespace after comment marker
            while let ch = peek(), ch == " " || ch == "\t" {
                _ = advance()
            }
            var text = ""
            while let ch = peek(), ch != "\n" {
                text.append(ch)
                _ = advance()
            }
            addToken(.comment, value: text)
            return
        }

        // Newlines
        if peek() == "\n" {
            _ = advance()
            addToken(.newline)
            return
        }

        // Keywords
        if match(JJ.keywords.print) != nil {
            addToken(.print)
            return
        }
        if match(JJ.keywords.log) != nil {
            addToken(.log)
            return
        }
        if match(JJ.keywords.input) != nil {
            addToken(.input)
            return
        }
        if match(JJ.keywords.yeet) != nil {
            addToken(.yeet)
            return
        }
        if match(JJ.keywords.kaboom) != nil {
            addToken(.kaboom)
            return
        }
        if match(JJ.keywords.snag) != nil {
            addToken(.snag)
            return
        }
        if match(JJ.keywords.invoke) != nil {
            addToken(.invoke)
            return
        }
        if match(JJ.keywords.enum) != nil {
            addToken(.enum)
            return
        }
        if match(JJ.keywords.nil) != nil {
            addToken(.nil)
            return
        }
        if match(JJ.keywords.true) != nil {
            addToken(.true)
            return
        }
        if match(JJ.keywords.false) != nil {
            addToken(.false)
            return
        }

        // Catch malformed JJ action keywords (e.g. ~>frob33333{7a3} or ~>fr999ob{7aww3})
        // Must come after valid keyword checks. Consume the rest of the line.
        if remaining().hasPrefix("~>") {
            if let m = matchRegex("~>[a-zA-Z0-9]+\\{[^}]*\\}[^\n]*") {
                // Extract keyword and hash, validate each against known values
                let afterArrow = m.dropFirst(2)
                let keyword = String(afterArrow.prefix(while: { $0 != "{" }))
                let afterBrace = afterArrow.drop(while: { $0 != "{" }).dropFirst()
                let hash = String(afterBrace.prefix(while: { $0 != "}" }))

                // Known valid keyword{hash} pairs from jj.json
                let validHashes = JJ.validHashes ?? [:]

                let msg: String
                if let expectedHash = validHashes[keyword] {
                    // Valid keyword but bad hash
                    msg = "Invalid hash '{\(hash)}' for keyword '~>\(keyword)' (expected '{\(expectedHash)}')"
                } else {
                    // Unknown keyword - suggest closest valid keyword
                    let allKeywordNames = Lexer.extractKeywordNames()
                    let suggestion = Lexer.closestMatch(to: keyword, from: allKeywordNames)
                    if let hint = suggestion {
                        msg = "Unknown keyword '~>\(keyword){\(hash)}', did you mean '~>\(hint)'?"
                    } else {
                        msg = "Unknown keyword '~>\(keyword){\(hash)}'"
                    }
                }
                addToken(.identifier, value: msg)
                return
            }
        }

        // Block structures
        let loopPrefix = NSRegularExpression.escapedPattern(for: JJ.blocks.loop)
        let whenPrefix = NSRegularExpression.escapedPattern(for: JJ.blocks.when)
        let morphPrefix = NSRegularExpression.escapedPattern(for: JJ.blocks.morph)
        let blockSuffix = NSRegularExpression.escapedPattern(for: JJ.blockSuffix)

        if let m = matchRegex("\(loopPrefix)([^}]*)\(blockSuffix)") {
            let start = m.index(m.startIndex, offsetBy: JJ.blocks.loop.count)
            let end = m.index(m.endIndex, offsetBy: -JJ.blockSuffix.count)
            let content = String(m[start..<end])
            addToken(.loop, value: content)
            return
        }
        if let m = matchRegex("\(whenPrefix)([^}]*)\(blockSuffix)") {
            let start = m.index(m.startIndex, offsetBy: JJ.blocks.when.count)
            let end = m.index(m.endIndex, offsetBy: -JJ.blockSuffix.count)
            let content = String(m[start..<end])
            addToken(.when, value: content)
            return
        }
        if match(JJ.blocks.else) != nil {
            addToken(.else)
            return
        }
        if let m = matchRegex("\(morphPrefix)([^}]*)\(blockSuffix)") {
            let start = m.index(m.startIndex, offsetBy: JJ.blocks.morph.count)
            let end = m.index(m.endIndex, offsetBy: -JJ.blockSuffix.count)
            let content = String(m[start..<end])
            addToken(.morph, value: content)
            return
        }
        if match(JJ.blocks.try) != nil {
            addToken(.try)
            return
        }
        if match(JJ.blocks.oops) != nil {
            addToken(.oops)
            return
        }
        if match(JJ.blocks.end) != nil {
            addToken(.blockEnd)
            return
        }

        // Catch malformed block keywords (e.g. <~morp3333h{...}>>, <~loo999p{...}>>)
        // Must come after valid block checks.
        if remaining().hasPrefix("<~") {
            if let m = matchRegex("<~[a-zA-Z0-9]+\\{[^}]*\\}>>") {
                // Extract block name between <~ and {
                let afterTilde = m.dropFirst(2) // remove "<~"
                let blockName = String(afterTilde.prefix(while: { $0 != "{" }))
                let validBlocks = Lexer.bracedBlockNames()
                let suggestion = Lexer.closestMatch(to: blockName, from: validBlocks)
                let msg: String
                if let hint = suggestion {
                    msg = "Unknown block '<~\(blockName)', did you mean '<~\(hint)'?"
                } else {
                    msg = "Unknown block '<~\(blockName)'"
                }
                addToken(.identifier, value: msg)
                return
            }
            // Also catch <~badword>> (no braces, like <~els999e>> or <~tr999y>>)
            if let m = matchRegex("<~[a-zA-Z0-9]+>>") {
                let blockName = String(m.dropFirst(2).dropLast(2))
                let validSimpleBlocks = Lexer.simpleBlockNames()
                let suggestion = Lexer.closestMatch(to: blockName, from: validSimpleBlocks)
                let msg: String
                if let hint = suggestion {
                    msg = "Unknown block '<~\(blockName)>>', did you mean '<~\(hint)>>'?"
                } else {
                    msg = "Unknown block '<~\(blockName)>>'"
                }
                addToken(.identifier, value: msg)
                return
            }
        }

        // Operators - match full <...> token first, then validate
        // Skip <~ patterns (block keywords handled above)
        if peek() == "<" && peek(offset: 1) != "~" {
            if let m = matchRegex("<[^>]+>") {
                // Check if it's a valid operator
                let opMap: [String: TokenType] = [
                    JJ.operators.add.symbol: .add,
                    JJ.operators.sub.symbol: .sub,
                    JJ.operators.mul.symbol: .mul,
                    JJ.operators.div.symbol: .div,
                    JJ.operators.mod.symbol: .mod,
                    JJ.operators.neq.symbol: .neq,
                    JJ.operators.eq.symbol: .eq,
                    JJ.operators.lte.symbol: .lte,
                    JJ.operators.lt.symbol: .lt,
                    JJ.operators.gte.symbol: .gte,
                    JJ.operators.gt.symbol: .gt,
                    JJ.operators.and.symbol: .and,
                    JJ.operators.or.symbol: .or,
                    JJ.operators.not.symbol: .not,
                ]
                if let tokenType = opMap[m] {
                    addToken(tokenType)
                    return
                }
                // Not a valid operator — malformed
                let validOps = Array(opMap.keys)
                let suggestion = Lexer.closestMatch(to: m, from: validOps)
                let msg: String
                if let hint = suggestion {
                    msg = "Unknown operator '\(m)', did you mean '\(hint)'?"
                } else {
                    msg = "Unknown operator '\(m)'"
                }
                addToken(.identifier, value: msg)
                return
            }
        }

        // Structure
        if match(JJ.structure.action) != nil {
            addToken(.action)
            return
        }
        if match(JJ.structure.range) != nil {
            addToken(.range)
            return
        }
        if match(JJ.structure.colon) != nil {
            addToken(.colon)
            return
        }

        // Single characters
        if let ch = peek() {
            switch ch {
            case "(":
                _ = advance()
                addToken(.lparen)
                return
            case ")":
                _ = advance()
                addToken(.rparen)
                return
            case "[":
                _ = advance()
                addToken(.lbracket)
                return
            case "]":
                _ = advance()
                addToken(.rbracket)
                return
            case "{":
                _ = advance()
                addToken(.lbrace)
                return
            case "}":
                _ = advance()
                addToken(.rbrace)
                return
            case ",":
                _ = advance()
                addToken(.comma)
                return
            default:
                break
            }
        }

        // Numbers (with # prefix for JJ syntax)
        if peek() == Character(JJ.literals.numberPrefix) {
            _ = advance()
            if let num = matchRegex("-?\\d+\\.?\\d*") {
                // Check for type suffix
                let suffix = matchRegex("(i8|i16|i32|i64|u8|u16|u32|u64|u|f|d)")
                let numericType = parseNumericType(suffix, hasDecimal: num.contains("."))
                if num.contains(".") {
                    addToken(.number, value: Double(num) ?? 0.0, numericType: numericType)
                } else {
                    addToken(.number, value: Int(num) ?? 0, numericType: numericType)
                }
                return
            }
        }

        // Plain numbers (for inline expressions)
        if let ch = peek(), ch.isNumber || (ch == "-" && (peek(offset: 1)?.isNumber ?? false)) {
            if let num = matchRegex("-?\\d+\\.?\\d*") {
                // Check for type suffix
                let suffix = matchRegex("(i8|i16|i32|i64|u8|u16|u32|u64|u|f|d)")
                let numericType = parseNumericType(suffix, hasDecimal: num.contains("."))
                if num.contains(".") {
                    addToken(.number, value: Double(num) ?? 0.0, numericType: numericType)
                } else {
                    addToken(.number, value: Int(num) ?? 0, numericType: numericType)
                }
                return
            }
        }

        // Strings (with interpolation detection)
        if peek() == Character(JJ.literals.stringDelim) {
            _ = advance()
            var currentLiteral = ""
            var parts: [(isVar: Bool, text: String)] = []
            var hasInterpolation = false

            while let ch = peek(), ch != Character(JJ.literals.stringDelim) {
                if ch == "\\" {
                    _ = advance()
                    if let esc = peek() {
                        if esc == "{" {
                            currentLiteral.append("{")
                            _ = advance()
                        } else {
                            let escapes: [Character: Character] = ["n": "\n", "t": "\t", "r": "\r", "\"": "\"", "\\": "\\"]
                            currentLiteral.append(escapes[esc] ?? esc)
                            _ = advance()
                        }
                    }
                } else if ch == "{" {
                    _ = advance()
                    var varName = ""
                    while let inner = peek(), inner != "}" && inner != Character(JJ.literals.stringDelim) {
                        varName.append(inner)
                        _ = advance()
                    }
                    if peek() == "}" { _ = advance() }
                    let isValidId = !varName.isEmpty && varName.range(of: "^[a-zA-Z_][a-zA-Z0-9_]*$", options: .regularExpression) != nil
                    if isValidId {
                        hasInterpolation = true
                        parts.append((isVar: false, text: currentLiteral))
                        currentLiteral = ""
                        parts.append((isVar: true, text: varName))
                    } else {
                        currentLiteral.append("{")
                        currentLiteral.append(varName)
                        currentLiteral.append("}")
                    }
                } else {
                    if let c = advance().first {
                        currentLiteral.append(c)
                    }
                }
            }
            _ = advance() // closing quote

            if hasInterpolation {
                parts.append((isVar: false, text: currentLiteral))
                addToken(.interpString, value: parts)
            } else {
                addToken(.string, value: currentLiteral)
            }
            return
        }

        // Syntax keywords
        if match(JJ.syntax.emit) != nil {
            addToken(.emit)
            return
        }
        if match(JJ.syntax.grab) != nil {
            addToken(.grab)
            return
        }
        if match(JJ.syntax.val) != nil {
            addToken(.val)
            return
        }
        if match(JJ.syntax.with) != nil {
            addToken(.with)
            return
        }
        if match(JJ.syntax.cases) != nil {
            addToken(.cases)
            return
        }

        // Identifiers
        if let m = matchRegex("[a-zA-Z_][a-zA-Z0-9_]*") {
            addToken(.identifier, value: m)
            return
        }

        // Unknown character - collect consecutive non-whitespace/non-alphanumeric symbols
        if let ch = peek(), !ch.isLetter && !ch.isNumber && ch != " " && ch != "\t" && ch != "\n" && ch != "\r" {
            var bad = ""
            while let c = peek(), !c.isLetter && !c.isNumber && c != " " && c != "\t" && c != "\n" && c != "\r"
                    && c != "(" && c != ")" && c != "[" && c != "]" && c != "{" && c != "}" && c != "," && c != "\"" {
                bad += advance()
            }
            addToken(.identifier, value: "Unexpected symbol '\(bad)' (operators must use <...> syntax)")
            return
        }
        _ = advance()
    }

    private func parseNumericType(_ suffix: String?, hasDecimal: Bool) -> String? {
        guard let suffix = suffix else {
            return hasDecimal ? "Double" : "Int"
        }
        switch suffix {
        case "i8": return "Int8"
        case "i16": return "Int16"
        case "i32": return "Int32"
        case "i64": return "Int64"
        case "u": return "UInt"
        case "u8": return "UInt8"
        case "u16": return "UInt16"
        case "u32": return "UInt32"
        case "u64": return "UInt64"
        case "f": return "Float"
        case "d": return "Double"
        default: return hasDecimal ? "Double" : "Int"
        }
    }

    /// All valid operator symbols from jj.json
    static func allOperatorSymbols() -> [String] {
        return [
            JJ.operators.add.symbol, JJ.operators.sub.symbol,
            JJ.operators.mul.symbol, JJ.operators.div.symbol,
            JJ.operators.mod.symbol, JJ.operators.eq.symbol,
            JJ.operators.neq.symbol, JJ.operators.lt.symbol,
            JJ.operators.lte.symbol, JJ.operators.gt.symbol,
            JJ.operators.gte.symbol, JJ.operators.and.symbol,
            JJ.operators.or.symbol, JJ.operators.not.symbol
        ]
    }

    /// Extract keyword names from jj.json keywords (e.g. "frob" from "~>frob{7a3}", "snag" from "~>snag")
    static func extractKeywordNames() -> [String] {
        let keywords = [
            JJ.keywords.print, JJ.keywords.input,
            JJ.keywords.yeet, JJ.keywords.kaboom,
            JJ.keywords.snag, JJ.keywords.invoke, JJ.keywords.enum
        ]
        return keywords.compactMap { kw -> String? in
            guard kw.hasPrefix("~>") else { return nil }
            let name = kw.dropFirst(2)
            if let braceIdx = name.firstIndex(of: "{") {
                return String(name[name.startIndex..<braceIdx])
            }
            return String(name)
        }
    }

    /// Find the closest valid keyword name using longest common subsequence
    static func closestMatch(to input: String, from candidates: [String]) -> String? {
        let inputLower = input.lowercased()
        var best: String?
        var bestScore = 0
        for candidate in candidates {
            let score = lcsLength(inputLower, candidate.lowercased())
            if score > bestScore && score >= 2 {
                bestScore = score
                best = candidate
            }
        }
        return best
    }

    /// Extract block name from config string (e.g. "loop" from "<~loop{", "else" from "<~else>>")
    private static func blockName(_ block: String) -> String? {
        guard block.hasPrefix("<~") else { return nil }
        let rest = block.dropFirst(2)
        let name = rest.prefix(while: { $0.isLetter })
        return name.isEmpty ? nil : String(name)
    }

    /// Block names with brace content (e.g. ["loop", "when", "morph"])
    static func bracedBlockNames() -> [String] {
        return [JJ.blocks.loop, JJ.blocks.when, JJ.blocks.morph].compactMap { blockName($0) }
    }

    /// Simple block names without brace content (e.g. ["else", "try", "oops"])
    static func simpleBlockNames() -> [String] {
        return [JJ.blocks.else, JJ.blocks.try, JJ.blocks.oops].compactMap { blockName($0) }
    }

    /// Longest common subsequence length
    private static func lcsLength(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i-1] == b[j-1] {
                    dp[i][j] = dp[i-1][j-1] + 1
                } else {
                    dp[i][j] = max(dp[i-1][j], dp[i][j-1])
                }
            }
        }
        return dp[a.count][b.count]
    }
}
