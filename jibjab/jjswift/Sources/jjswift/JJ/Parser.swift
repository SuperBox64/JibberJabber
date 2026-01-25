/// JibJab Parser - Parses tokens into AST
import Foundation

class Parser {
    private var tokens: [Token]
    private var pos: Int = 0

    init(tokens: [Token]) {
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
        throw ParserError.unexpectedToken(expected: type, got: peek().type, line: peek().line)
    }

    func parse() throws -> Program {
        var statements: [ASTNode] = []
        while peek().type != .eof {
            if let stmt = try parseStatement() {
                statements.append(stmt)
            }
        }
        return Program(statements: statements)
    }

    private func parseStatement() throws -> ASTNode? {
        switch peek().type {
        case .print:
            return try parsePrint()
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

    private func parseVarDecl() throws -> VarDecl {
        _ = advance() // SNAG
        _ = try expect(.lbrace)
        let nameToken = try expect(.identifier)
        let name = nameToken.value as! String
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
        let loopSpec = token.value as! String
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
        let condition = try parseInlineExpr(token.value as! String)
        let thenBody = try parseBlock()
        var elseBody: [ASTNode]? = nil

        if peek().type == .else {
            _ = advance()
            elseBody = try parseBlock()
        }

        return IfStmt(condition: condition, thenBody: thenBody, elseBody: elseBody)
    }

    private func parseFuncDef() throws -> FuncDef {
        let token = advance() // MORPH with signature
        let sig = token.value as! String

        // Parse signature like "funcName(param1, param2)"
        let regex = try! NSRegularExpression(pattern: "(\\w+)\\(([^)]*)\\)")
        let range = NSRange(sig.startIndex..., in: sig)
        guard let match = regex.firstMatch(in: sig, range: range) else {
            throw ParserError.invalidFunctionSignature(sig)
        }

        let nameRange = Range(match.range(at: 1), in: sig)!
        let paramsRange = Range(match.range(at: 2), in: sig)!
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

    private func parseBlock() throws -> [ASTNode] {
        var statements: [ASTNode] = []
        while peek().type != .blockEnd && peek().type != .else && peek().type != .eof {
            if let stmt = try parseStatement() {
                statements.append(stmt)
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
            left = BinaryOp(left: left, op: "||", right: right)
        }
        return left
    }

    private func parseAnd() throws -> ASTNode {
        var left = try parseEquality()
        while match(.and) != nil {
            let right = try parseEquality()
            left = BinaryOp(left: left, op: "&&", right: right)
        }
        return left
    }

    private func parseEquality() throws -> ASTNode {
        var left = try parseComparison()
        while true {
            if match(.eq) != nil {
                left = BinaryOp(left: left, op: "==", right: try parseComparison())
            } else if match(.neq) != nil {
                left = BinaryOp(left: left, op: "!=", right: try parseComparison())
            } else {
                break
            }
        }
        return left
    }

    private func parseComparison() throws -> ASTNode {
        var left = try parseAdditive()
        while true {
            if match(.lt) != nil {
                left = BinaryOp(left: left, op: "<", right: try parseAdditive())
            } else if match(.gt) != nil {
                left = BinaryOp(left: left, op: ">", right: try parseAdditive())
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
                left = BinaryOp(left: left, op: "+", right: try parseMultiplicative())
            } else if match(.sub) != nil {
                left = BinaryOp(left: left, op: "-", right: try parseMultiplicative())
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
                left = BinaryOp(left: left, op: "*", right: try parseUnary())
            } else if match(.div) != nil {
                left = BinaryOp(left: left, op: "/", right: try parseUnary())
            } else if match(.mod) != nil {
                left = BinaryOp(left: left, op: "%", right: try parseUnary())
            } else {
                break
            }
        }
        return left
    }

    private func parseUnary() throws -> ASTNode {
        if match(.not) != nil {
            return UnaryOp(op: "!", operand: try parseUnary())
        }
        return try parsePrimary()
    }

    private func parsePrimary() throws -> ASTNode {
        if match(.lparen) != nil {
            let expr = try parseExpression()
            _ = try expect(.rparen)
            return expr
        }

        if let token = match(.number) {
            return Literal(value: token.value)
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
            let name = nameToken.value as! String
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
            return VarRef(name: token.value as! String)
        }

        throw ParserError.unexpectedToken(expected: .identifier, got: peek().type, line: peek().line)
    }

    private func parseInlineExpr(_ text: String) throws -> ASTNode {
        let lexer = Lexer(source: text)
        let tokens = lexer.tokenize()
        let parser = Parser(tokens: tokens)
        return try parser.parseExpression()
    }
}

enum ParserError: Error, CustomStringConvertible {
    case unexpectedToken(expected: TokenType, got: TokenType, line: Int)
    case invalidFunctionSignature(String)

    var description: String {
        switch self {
        case .unexpectedToken(let expected, let got, let line):
            return "Expected \(expected), got \(got) at line \(line)"
        case .invalidFunctionSignature(let sig):
            return "Invalid function signature: \(sig)"
        }
    }
}
