/// JibJab Parser - Parses tokens into AST
/// Uses emit values from common/jj.json via JJConfig
import Foundation

public class Parser {
    private var tokens: [Token]
    private var pos: Int = 0

    public init(tokens: [Token]) {
        // Filter out newlines
        self.tokens = tokens.filter { $0.type != .newline }
    }

    private func peek(offset: Int = 0) -> Token {
        let idx = pos + offset
        if idx < tokens.count {
            return tokens[idx]
        }
        return Token(type: .eof, value: nil, line: 0, col: 0)
    }

    private func advance() -> Token {
        let token = peek()
        pos += 1
        return token
    }

    private func match(_ types: TokenType...) -> Token? {
        if types.contains(peek().type) {
            return advance()
        }
        return nil
    }

    private func expect(_ type: TokenType) throws -> Token {
        if peek().type == type {
            return advance()
        }
        let token = peek()
        let tokenText = token.value.map { "\($0)" } ?? Self.tokenSymbol(token.type)
        throw ParserError.unexpectedToken(expected: type, got: token.type, gotValue: tokenText, line: token.line)
    }

    static func tokenSymbol(_ type: TokenType) -> String {
        let key = "\(type)"
        // Check shared config first
        if let symbols = JJ.tokenSymbols, let symbol = symbols[key] {
            return symbol
        }
        // Operator symbols from config
        switch type {
        case .add: return JJ.operators.add.symbol
        case .sub: return JJ.operators.sub.symbol
        case .mul: return JJ.operators.mul.symbol
        case .div: return JJ.operators.div.symbol
        case .mod: return JJ.operators.mod.symbol
        case .eq: return JJ.operators.eq.symbol
        case .neq: return JJ.operators.neq.symbol
        case .lt: return JJ.operators.lt.symbol
        case .lte: return JJ.operators.lte.symbol
        case .gt: return JJ.operators.gt.symbol
        case .gte: return JJ.operators.gte.symbol
        case .and: return JJ.operators.and.symbol
        case .or: return JJ.operators.or.symbol
        case .not: return JJ.operators.not.symbol
        case .comma: return ","
        case .eof: return "end of file"
        case .newline: return "newline"
        case .blockEnd: return JJ.blocks.end
        default: return key
        }
    }

    public func parse() throws -> Program {
        var statements: [ASTNode] = []
        while peek().type != .eof {
            if let stmt = try parseStatement() {
                statements.append(stmt)
            } else {
                let bad = advance()
                let tokenText = bad.value.map { "\($0)" } ?? "\(bad.type)"
                throw ParserError.unrecognizedStatement(token: tokenText, line: bad.line)
            }
        }
        return Program(statements: statements)
    }

    private func parseStatement() throws -> ASTNode? {
        switch peek().type {
        case .print:
            return try parsePrint()
        case .log:
            return try parseLog()
        case .snag:
            return try parseVarDecl()
        case .loop:
            return try parseLoop()
        case .when:
            return try parseIf()
        case .morph:
            return try parseFuncDef()
        case .yeet:
            return try parseReturn()
        case .kaboom:
            return try parseThrow()
        case .enum:
            return try parseEnumDef()
        case .`try`:
            return try parseTry()
        case .comment:
            let token = advance()
            return CommentNode(text: (token.value as? String) ?? "")
        default:
            return nil
        }
    }

    private func parsePrint() throws -> PrintStmt {
        _ = advance() // PRINT
        _ = try expect(.action)
        _ = try expect(.emit)
        _ = try expect(.lparen)
        let expr = try parseExpression()
        _ = try expect(.rparen)
        return PrintStmt(expr: expr)
    }

    private func parseLog() throws -> LogStmt {
        _ = advance() // LOG
        _ = try expect(.action)
        _ = try expect(.emit)
        _ = try expect(.lparen)
        let expr = try parseExpression()
        _ = try expect(.rparen)
        return LogStmt(expr: expr)
    }

    private func parseVarDecl() throws -> VarDecl {
        _ = advance() // SNAG
        _ = try expect(.lbrace)
        let nameToken = try expect(.identifier)
        let name = (nameToken.value as? String) ?? ""
        _ = try expect(.rbrace)
        _ = try expect(.action)
        _ = try expect(.val)
        _ = try expect(.lparen)
        let value = try parseExpression()
        _ = try expect(.rparen)
        return VarDecl(name: name, value: value)
    }

    private func parseLoop() throws -> LoopStmt {
        let token = advance() // LOOP with value
        let loopSpec = (token.value as? String) ?? ""
        let body = try parseBlock()

        // Parse loop specification
        if loopSpec.contains("..") {
            let parts = loopSpec.split(separator: ":", maxSplits: 1).map { String($0) }
            let varName = parts[0]
            let rangeParts = parts[1].split(separator: "..", maxSplits: 1).map { String($0) }
            let start = try parseInlineExpr(rangeParts[0])
            let end = try parseInlineExpr(rangeParts[1])
            return LoopStmt(var: varName, start: start, end: end, collection: nil, condition: nil, body: body)
        } else if loopSpec.contains(":") {
            let parts = loopSpec.split(separator: ":", maxSplits: 1).map { String($0) }
            let varName = parts[0]
            let collection = VarRef(name: parts[1])
            return LoopStmt(var: varName, start: nil, end: nil, collection: collection, condition: nil, body: body)
        } else {
            let condition = try parseInlineExpr(loopSpec)
            return LoopStmt(var: "_", start: nil, end: nil, collection: nil, condition: condition, body: body)
        }
    }

    private func parseIf() throws -> IfStmt {
        let token = advance() // WHEN with condition
        let condition = try parseInlineExpr((token.value as? String) ?? "")
        let thenBody = try parseBlock()
        var elseBody: [ASTNode]? = nil

        if peek().type == .else {
            _ = advance()
            elseBody = try parseBlock()
        }

        return IfStmt(condition: condition, thenBody: thenBody, elseBody: elseBody)
    }

    private func parseTry() throws -> TryStmt {
        _ = advance() // consume .try
        let tryBody = try parseBlock()
        var oopsBody: [ASTNode]? = nil
        var oopsVar: String? = nil
        if peek().type == .oops {
            _ = advance()
            if peek().type == .identifier {
                oopsVar = advance().value as? String
            }
            oopsBody = try parseBlock()
        }
        return TryStmt(tryBody: tryBody, oopsBody: oopsBody, oopsVar: oopsVar)
    }

    private func parseFuncDef() throws -> FuncDef {
        let token = advance() // MORPH with signature
        let sig = (token.value as? String) ?? ""

        // Parse signature like "funcName(param1, param2)"
        guard let regex = try? NSRegularExpression(pattern: "(\\w+)\\(([^)]*)\\)") else {
            throw ParserError.invalidFunctionSignature(sig)
        }
        let range = NSRange(sig.startIndex..., in: sig)
        guard let match = regex.firstMatch(in: sig, range: range) else {
            throw ParserError.invalidFunctionSignature(sig)
        }

        guard let nameRange = Range(match.range(at: 1), in: sig),
              let paramsRange = Range(match.range(at: 2), in: sig) else {
            throw ParserError.invalidFunctionSignature(sig)
        }
        let name = String(sig[nameRange])
        let paramsStr = String(sig[paramsRange])
        let params = paramsStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let body = try parseBlock()
        return FuncDef(name: name, params: params, body: body)
    }

    private func parseReturn() throws -> ReturnStmt {
        _ = advance() // YEET
        _ = try expect(.lbrace)
        let value = try parseExpression()
        _ = try expect(.rbrace)
        return ReturnStmt(value: value)
    }

    private func parseThrow() throws -> ThrowStmt {
        _ = advance() // KABOOM
        _ = try expect(.lbrace)
        let value = try parseExpression()
        _ = try expect(.rbrace)
        return ThrowStmt(value: value)
    }

    private func parseEnumDef() throws -> EnumDef {
        _ = advance() // ENUM
        _ = try expect(.lbrace)
        let nameToken = try expect(.identifier)
        let name = (nameToken.value as? String) ?? ""
        _ = try expect(.rbrace)
        _ = try expect(.action)
        _ = try expect(.cases)
        _ = try expect(.lparen)
        var cases: [String] = []
        if peek().type != .rparen {
            let caseToken = try expect(.identifier)
            cases.append((caseToken.value as? String) ?? "")
            while match(.comma) != nil {
                let caseToken = try expect(.identifier)
                cases.append((caseToken.value as? String) ?? "")
            }
        }
        _ = try expect(.rparen)
        return EnumDef(name: name, cases: cases)
    }

    private func parseBlock() throws -> [ASTNode] {
        var statements: [ASTNode] = []
        while peek().type != .blockEnd && peek().type != .else && peek().type != .oops && peek().type != .eof {
            if let stmt = try parseStatement() {
                statements.append(stmt)
            } else {
                let bad = advance()
                let tokenText = bad.value.map { "\($0)" } ?? "\(bad.type)"
                throw ParserError.unrecognizedStatement(token: tokenText, line: bad.line)
            }
        }
        if peek().type == .blockEnd {
            _ = advance()
        }
        return statements
    }

    private func parseExpression() throws -> ASTNode {
        return try parseOr()
    }

    private func parseOr() throws -> ASTNode {
        var left = try parseAnd()
        while match(.or) != nil {
            let right = try parseAnd()
            left = BinaryOp(left: left, op: JJ.operators.or.emit, right: right)
        }
        return left
    }

    private func parseAnd() throws -> ASTNode {
        var left = try parseEquality()
        while match(.and) != nil {
            let right = try parseEquality()
            left = BinaryOp(left: left, op: JJ.operators.and.emit, right: right)
        }
        return left
    }

    private func parseEquality() throws -> ASTNode {
        var left = try parseComparison()
        while true {
            if match(.eq) != nil {
                left = BinaryOp(left: left, op: JJ.operators.eq.emit, right: try parseComparison())
            } else if match(.neq) != nil {
                left = BinaryOp(left: left, op: JJ.operators.neq.emit, right: try parseComparison())
            } else {
                break
            }
        }
        return left
    }

    private func parseComparison() throws -> ASTNode {
        var left = try parseAdditive()
        while true {
            if match(.lte) != nil {
                left = BinaryOp(left: left, op: JJ.operators.lte.emit, right: try parseAdditive())
            } else if match(.lt) != nil {
                left = BinaryOp(left: left, op: JJ.operators.lt.emit, right: try parseAdditive())
            } else if match(.gte) != nil {
                left = BinaryOp(left: left, op: JJ.operators.gte.emit, right: try parseAdditive())
            } else if match(.gt) != nil {
                left = BinaryOp(left: left, op: JJ.operators.gt.emit, right: try parseAdditive())
            } else {
                break
            }
        }
        return left
    }

    private func parseAdditive() throws -> ASTNode {
        var left = try parseMultiplicative()
        while true {
            if match(.add) != nil {
                left = BinaryOp(left: left, op: JJ.operators.add.emit, right: try parseMultiplicative())
            } else if match(.sub) != nil {
                left = BinaryOp(left: left, op: JJ.operators.sub.emit, right: try parseMultiplicative())
            } else {
                break
            }
        }
        return left
    }

    private func parseMultiplicative() throws -> ASTNode {
        var left = try parseUnary()
        while true {
            if match(.mul) != nil {
                left = BinaryOp(left: left, op: JJ.operators.mul.emit, right: try parseUnary())
            } else if match(.div) != nil {
                left = BinaryOp(left: left, op: JJ.operators.div.emit, right: try parseUnary())
            } else if match(.mod) != nil {
                left = BinaryOp(left: left, op: JJ.operators.mod.emit, right: try parseUnary())
            } else {
                break
            }
        }
        return left
    }

    private func parseUnary() throws -> ASTNode {
        if match(.not) != nil {
            return UnaryOp(op: JJ.operators.not.emit, operand: try parseUnary())
        }
        return try parsePrimary()
    }

    private func parsePrimary() throws -> ASTNode {
        // Parentheses: either grouped expression or tuple
        if match(.lparen) != nil {
            // Empty tuple ()
            if peek().type == .rparen {
                _ = advance()
                return try parsePostfix(TupleLiteral(elements: []))
            }
            let firstExpr = try parseExpression()
            // Check if this is a tuple (has comma) or just grouped expression
            if match(.comma) != nil {
                var elements: [ASTNode] = [firstExpr]
                if peek().type != .rparen {
                    elements.append(try parseExpression())
                    while match(.comma) != nil {
                        elements.append(try parseExpression())
                    }
                }
                _ = try expect(.rparen)
                return try parsePostfix(TupleLiteral(elements: elements))
            }
            _ = try expect(.rparen)
            return try parsePostfix(firstExpr)
        }

        // Array literal
        if match(.lbracket) != nil {
            var elements: [ASTNode] = []
            if peek().type != .rbracket {
                elements.append(try parseExpression())
                while match(.comma) != nil {
                    elements.append(try parseExpression())
                }
            }
            _ = try expect(.rbracket)
            return try parsePostfix(ArrayLiteral(elements: elements))
        }

        // Dictionary literal: {key: value, ...}
        if peek().type == .lbrace {
            // Look ahead to see if this is a dict literal (has colon after first expr)
            let startPos = pos
            _ = advance() // consume {
            if peek().type == .rbrace {
                _ = advance() // empty dict {}
                return try parsePostfix(DictLiteral(pairs: []))
            }
            // Parse first key
            let firstKey = try parseExpression()
            if peek().type == .colon {
                // This is a dictionary literal
                _ = advance() // consume :
                let firstValue = try parseExpression()
                var pairs: [(key: ASTNode, value: ASTNode)] = [(firstKey, firstValue)]
                while match(.comma) != nil {
                    let key = try parseExpression()
                    _ = try expect(.colon)
                    let value = try parseExpression()
                    pairs.append((key, value))
                }
                _ = try expect(.rbrace)
                return try parsePostfix(DictLiteral(pairs: pairs))
            } else {
                // Not a dict literal, restore position (shouldn't happen in well-formed code)
                pos = startPos
            }
        }

        if let token = match(.number) {
            let numType = token.numericType.flatMap { NumericType(rawValue: $0) }
            return Literal(value: token.value, numericType: numType)
        }
        if let token = match(.interpString) {
            if let rawParts = token.value as? [(isVar: Bool, text: String)] {
                let parts = rawParts.map { part -> StringInterpPart in
                    part.isVar ? .variable(part.text) : .literal(part.text)
                }
                return StringInterpolation(parts: parts)
            }
        }
        if let token = match(.string) {
            return Literal(value: token.value)
        }
        if match(.true) != nil {
            return Literal(value: true)
        }
        if match(.false) != nil {
            return Literal(value: false)
        }
        if match(.nil) != nil {
            return Literal(value: nil)
        }

        if match(.input) != nil {
            _ = try expect(.action)
            _ = try expect(.grab)
            _ = try expect(.lparen)
            let prompt = try parseExpression()
            _ = try expect(.rparen)
            return InputExpr(prompt: prompt)
        }

        if match(.invoke) != nil {
            _ = try expect(.lbrace)
            let nameToken = try expect(.identifier)
            let name = (nameToken.value as? String) ?? ""
            _ = try expect(.rbrace)
            _ = try expect(.action)
            _ = try expect(.with)
            _ = try expect(.lparen)
            var args: [ASTNode] = []
            if peek().type != .rparen {
                args.append(try parseExpression())
                while match(.comma) != nil {
                    args.append(try parseExpression())
                }
            }
            _ = try expect(.rparen)
            return FuncCall(name: name, args: args)
        }

        if let token = match(.identifier) {
            let name = (token.value as? String) ?? ""
            // Check for error tokens from the lexer
            if name.hasPrefix("Unknown ") || name.hasPrefix("Invalid ") || name.hasPrefix("Unexpected ") {
                throw ParserError.unrecognizedStatement(token: name, line: token.line)
            }
            return try parsePostfix(VarRef(name: name))
        }

        let token = peek()
        let tokenText = token.value.map { "\($0)" } ?? "\(token.type)"
        throw ParserError.unexpectedToken(expected: .identifier, got: token.type, gotValue: tokenText, line: token.line)
    }

    private func parsePostfix(_ expr: ASTNode) throws -> ASTNode {
        var result = expr
        // Handle array indexing: arr[index]
        while match(.lbracket) != nil {
            let index = try parseExpression()
            _ = try expect(.rbracket)
            result = IndexAccess(array: result, index: index)
        }
        return result
    }

    private func parseInlineExpr(_ text: String) throws -> ASTNode {
        let lexer = Lexer(source: text)
        let tokens = lexer.tokenize()
        let parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        // Ensure all tokens were consumed
        if parser.peek().type != .eof {
            let leftover = parser.peek()
            let tokenText = leftover.value.map { "\($0)" } ?? "\(leftover.type)"
            if tokenText.hasPrefix("Unknown ") || tokenText.hasPrefix("Invalid ") {
                throw ParserError.unrecognizedStatement(token: tokenText, line: leftover.line)
            }
            throw ParserError.unexpectedToken(expected: .eof, got: leftover.type, gotValue: tokenText, line: leftover.line)
        }
        return expr
    }
}

public enum ParserError: Error, CustomStringConvertible {
    case unexpectedToken(expected: TokenType, got: TokenType, gotValue: String, line: Int)
    case invalidFunctionSignature(String)
    case unrecognizedStatement(token: String, line: Int)

    public var description: String {
        switch self {
        case .unexpectedToken(let expected, _, let gotValue, let line):
            if gotValue.hasPrefix("Unknown ") || gotValue.hasPrefix("Unexpected ") {
                return "\(gotValue) at line \(line)"
            }
            return "Expected \(expected), got '\(gotValue)' at line \(line)"
        case .invalidFunctionSignature(let sig):
            return "Invalid function signature: \(sig)"
        case .unrecognizedStatement(let token, let line):
            if token.hasPrefix("Unknown ") || token.hasPrefix("Invalid ") || token.hasPrefix("Unexpected ") {
                return "\(token) at line \(line)"
            }
            return "Unrecognized statement '\(token)' at line \(line)"
        }
    }
}
