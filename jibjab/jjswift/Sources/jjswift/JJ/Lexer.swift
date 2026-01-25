/// JibJab Lexer - Tokenizes JJ source code
import Foundation

class Lexer {
    private let source: String
    private var pos: String.Index
    private var line: Int = 1
    private var col: Int = 1
    private var tokens: [Token] = []

    init(source: String) {
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

    private func addToken(_ type: TokenType, value: Any? = nil) {
        tokens.append(Token(type: type, value: value, line: line, col: col))
    }

    func tokenize() -> [Token] {
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
        if match("@@") != nil {
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

        // Keywords and special tokens
        if match("~>frob{7a3}") != nil {
            addToken(.print)
            return
        }
        if match("~>slurp{9f2}") != nil {
            addToken(.input)
            return
        }
        if match("~>yeet") != nil {
            addToken(.yeet)
            return
        }
        if match("~>snag") != nil {
            addToken(.snag)
            return
        }
        if match("~>invoke") != nil {
            addToken(.invoke)
            return
        }
        if match("~nil") != nil {
            addToken(.nil)
            return
        }
        if match("~yep") != nil {
            addToken(.true)
            return
        }
        if match("~nope") != nil {
            addToken(.false)
            return
        }

        // Block structures
        if let m = matchRegex("<~loop\\{([^}]*)\\}>>") {
            // Extract content between { and }
            let start = m.index(m.startIndex, offsetBy: 7) // skip "<~loop{"
            let end = m.index(m.endIndex, offsetBy: -3)    // skip "}>>"
            let content = String(m[start..<end])
            addToken(.loop, value: content)
            return
        }
        if let m = matchRegex("<~when\\{([^}]*)\\}>>") {
            let start = m.index(m.startIndex, offsetBy: 7)
            let end = m.index(m.endIndex, offsetBy: -3)
            let content = String(m[start..<end])
            addToken(.when, value: content)
            return
        }
        if match("<~else>>") != nil {
            addToken(.else)
            return
        }
        if let m = matchRegex("<~morph\\{([^}]*)\\}>>") {
            let start = m.index(m.startIndex, offsetBy: 8)
            let end = m.index(m.endIndex, offsetBy: -3)
            let content = String(m[start..<end])
            addToken(.morph, value: content)
            return
        }
        if match("<~try>>") != nil {
            addToken(.try)
            return
        }
        if match("<~oops>>") != nil {
            addToken(.oops)
            return
        }
        if match("<~>>") != nil {
            addToken(.blockEnd)
            return
        }

        // Operators
        if match("<+>") != nil {
            addToken(.add)
            return
        }
        if match("<->") != nil {
            addToken(.sub)
            return
        }
        if match("<*>") != nil {
            addToken(.mul)
            return
        }
        if match("</>") != nil {
            addToken(.div)
            return
        }
        if match("<%>") != nil {
            addToken(.mod)
            return
        }
        if match("<!=>") != nil {
            addToken(.neq)
            return
        }
        if match("<=>") != nil {
            addToken(.eq)
            return
        }
        if match("<lt>") != nil {
            addToken(.lt)
            return
        }
        if match("<gt>") != nil {
            addToken(.gt)
            return
        }
        if match("<&&>") != nil {
            addToken(.and)
            return
        }
        if match("<||>") != nil {
            addToken(.or)
            return
        }
        if match("<!>") != nil {
            addToken(.not)
            return
        }

        // Structure
        if match("::") != nil {
            addToken(.action)
            return
        }
        if match("..") != nil {
            addToken(.range)
            return
        }
        if match(":") != nil {
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
        if peek() == "#" {
            _ = advance()
            if let num = matchRegex("-?\\d+\\.?\\d*") {
                if num.contains(".") {
                    addToken(.number, value: Double(num)!)
                } else {
                    addToken(.number, value: Int(num)!)
                }
                return
            }
        }

        // Plain numbers (for inline expressions)
        if let ch = peek(), ch.isNumber || (ch == "-" && (peek(offset: 1)?.isNumber ?? false)) {
            if let num = matchRegex("-?\\d+\\.?\\d*") {
                if num.contains(".") {
                    addToken(.number, value: Double(num)!)
                } else {
                    addToken(.number, value: Int(num)!)
                }
                return
            }
        }

        // Strings
        if peek() == "\"" {
            _ = advance()
            var value = ""
            while let ch = peek(), ch != "\"" {
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

        // Keywords
        if match("emit") != nil {
            addToken(.emit)
            return
        }
        if match("grab") != nil {
            addToken(.grab)
            return
        }
        if match("val") != nil {
            addToken(.val)
            return
        }
        if match("with") != nil {
            addToken(.with)
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
}
