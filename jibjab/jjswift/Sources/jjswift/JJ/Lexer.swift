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
            while let ch = peek(), ch != "\n" {
                _ = advance()
            }
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
        if match(JJ.keywords.input) != nil {
            addToken(.input)
            return
        }
        if match(JJ.keywords.yeet) != nil {
            addToken(.yeet)
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

        // Operators (use .symbol for matching)
        if match(JJ.operators.add.symbol) != nil {
            addToken(.add)
            return
        }
        if match(JJ.operators.sub.symbol) != nil {
            addToken(.sub)
            return
        }
        if match(JJ.operators.mul.symbol) != nil {
            addToken(.mul)
            return
        }
        if match(JJ.operators.div.symbol) != nil {
            addToken(.div)
            return
        }
        if match(JJ.operators.mod.symbol) != nil {
            addToken(.mod)
            return
        }
        if match(JJ.operators.neq.symbol) != nil {
            addToken(.neq)
            return
        }
        if match(JJ.operators.eq.symbol) != nil {
            addToken(.eq)
            return
        }
        if match(JJ.operators.lte.symbol) != nil {
            addToken(.lte)
            return
        }
        if match(JJ.operators.lt.symbol) != nil {
            addToken(.lt)
            return
        }
        if match(JJ.operators.gte.symbol) != nil {
            addToken(.gte)
            return
        }
        if match(JJ.operators.gt.symbol) != nil {
            addToken(.gt)
            return
        }
        if match(JJ.operators.and.symbol) != nil {
            addToken(.and)
            return
        }
        if match(JJ.operators.or.symbol) != nil {
            addToken(.or)
            return
        }
        if match(JJ.operators.not.symbol) != nil {
            addToken(.not)
            return
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
                    addToken(.number, value: Double(num)!, numericType: numericType)
                } else {
                    addToken(.number, value: Int(num)!, numericType: numericType)
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
                    addToken(.number, value: Double(num)!, numericType: numericType)
                } else {
                    addToken(.number, value: Int(num)!, numericType: numericType)
                }
                return
            }
        }

        // Strings
        if peek() == Character(JJ.literals.stringDelim) {
            _ = advance()
            var value = ""
            while let ch = peek(), ch != Character(JJ.literals.stringDelim) {
                if ch == "\\" {
                    _ = advance()
                    if let esc = peek() {
                        let escapes: [Character: Character] = ["n": "\n", "t": "\t", "r": "\r", "\"": "\"", "\\": "\\"]
                        value.append(escapes[esc] ?? esc)
                        _ = advance()
                    }
                } else {
                    value.append(advance().first!)
                }
            }
            _ = advance() // closing quote
            addToken(.string, value: value)
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

        // Unknown - skip
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
}
