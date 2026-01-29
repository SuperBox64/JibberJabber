/// JibJab AppleScript Transpiler - Converts JJ to AppleScript
/// Uses shared config from common/jj.json

// AppleScript reserved words and class names that can't be used as variable names
private let appleScriptReserved: Set<String> = [
    "numbers", "strings", "characters", "words", "paragraphs", "items",
    "text", "list", "record", "number", "integer", "real", "string",
    "boolean", "date", "file", "alias", "class", "script", "property",
    "application", "window", "document", "folder", "disk", "reference",
    "it", "me", "my", "result", "true", "false", "missing", "value",
    "error", "pi", "tab", "return", "linefeed", "quote", "space", "color"
]

private func safeName(_ name: String) -> String {
    if appleScriptReserved.contains(name.lowercased()) {
        return "my_\(name)"
    }
    return name
}

public class AppleScriptTranspiler {
    public init() {}
    private var indentLevel = 0
    private let T = loadTarget("applescript")
    private let OP = JJ.operators
    private var enums: [String: [String]] = [:]  // Track enum name -> cases

    public func transpile(_ program: Program) -> String {
        var lines = [T.header.trimmingCharacters(in: .newlines)]
        for s in program.statements {
            lines.append(stmtToString(s))
        }
        return lines.joined(separator: "\n")
    }

    private func ind() -> String {
        return String(repeating: T.indent, count: indentLevel)
    }

    private func stmtToString(_ node: ASTNode) -> String {
        if let printStmt = node as? PrintStmt {
            return ind() + T.print.replacingOccurrences(of: "{expr}", with: expr(printStmt.expr))
        } else if let varDecl = node as? VarDecl {
            return ind() + T.var
                .replacingOccurrences(of: "{name}", with: safeName(varDecl.name))
                .replacingOccurrences(of: "{value}", with: expr(varDecl.value))
        } else if let loopStmt = node as? LoopStmt {
            var header: String
            if loopStmt.start != nil {
                header = ind() + T.forRange
                    .replacingOccurrences(of: "{var}", with: safeName(loopStmt.var))
                    .replacingOccurrences(of: "{start}", with: expr(loopStmt.start!))
                    .replacingOccurrences(of: "{end}", with: expr(loopStmt.end!))
            } else if let collection = loopStmt.collection {
                header = ind() + T.forIn
                    .replacingOccurrences(of: "{var}", with: safeName(loopStmt.var))
                    .replacingOccurrences(of: "{collection}", with: expr(collection))
            } else {
                header = ind() + T.while.replacingOccurrences(of: "{condition}", with: expr(loopStmt.condition!))
            }
            indentLevel += 1
            let body = loopStmt.body.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            return "\(header)\n\(body)\n\(ind())end repeat"
        } else if let ifStmt = node as? IfStmt {
            let header = ind() + T.if.replacingOccurrences(of: "{condition}", with: expr(ifStmt.condition))
            indentLevel += 1
            let thenBody = ifStmt.thenBody.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            var result = "\(header)\n\(thenBody)"
            if let elseBody = ifStmt.elseBody {
                result += "\n\(ind())\(T.else)"
                indentLevel += 1
                result += "\n" + elseBody.map { stmtToString($0) }.joined(separator: "\n")
                indentLevel -= 1
            }
            result += "\n\(ind())end if"
            return result
        } else if let funcDef = node as? FuncDef {
            let safeParams = funcDef.params.map { safeName($0) }.joined(separator: ", ")
            let safeFuncName = safeName(funcDef.name)
            let header = ind() + T.func
                .replacingOccurrences(of: "{name}", with: safeFuncName)
                .replacingOccurrences(of: "{params}", with: safeParams)
            indentLevel += 1
            let body = funcDef.body.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            return "\(header)\n\(body)\n\(ind())end \(safeFuncName)"
        } else if let returnStmt = node as? ReturnStmt {
            return ind() + T.return.replacingOccurrences(of: "{value}", with: expr(returnStmt.value))
        } else if let enumDef = node as? EnumDef {
            let safeEnumName = safeName(enumDef.name)
            enums[enumDef.name] = enumDef.cases
            // In AppleScript, represent enum as a record with case name -> index
            let pairs = enumDef.cases.enumerated().map { "\($0.element):\($0.offset)" }.joined(separator: ", ")
            return ind() + "set \(safeEnumName) to {\(pairs)}"
        }
        return ""
    }

    private func expr(_ node: ASTNode) -> String {
        if let literal = node as? Literal {
            if let str = literal.value as? String {
                return "\"\(escapeString(str))\""
            } else if literal.value == nil {
                return T.nil
            } else if let bool = literal.value as? Bool {
                return bool ? T.true : T.false
            } else if let int = literal.value as? Int {
                return String(int)
            } else if let double = literal.value as? Double {
                return String(double)
            }
            return String(describing: literal.value ?? T.nil)
        } else if let varRef = node as? VarRef {
            return safeName(varRef.name)
        } else if let arr = node as? ArrayLiteral {
            let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
            return "{\(elements)}"
        } else if let dict = node as? DictLiteral {
            let pairs = dict.pairs.map { "\(expr($0.0)):\(expr($0.1))" }.joined(separator: ", ")
            return "{\(pairs)}"
        } else if let tuple = node as? TupleLiteral {
            let elements = tuple.elements.map { expr($0) }.joined(separator: ", ")
            return "{\(elements)}"
        } else if let idx = node as? IndexAccess {
            // Check if this is enum access (e.g., Color["Red"] -> Red of my_Color)
            if let varRef = idx.array as? VarRef, enums[varRef.name] != nil {
                if let lit = idx.index as? Literal, let strVal = lit.value as? String {
                    return "\(strVal) of \(safeName(varRef.name))"
                }
            }
            return "item (\(expr(idx.index)) + 1) of \(expr(idx.array))"
        } else if let binaryOp = node as? BinaryOp {
            var op = binaryOp.op
            // Map operators to AppleScript equivalents
            if op == OP.and.emit || op == "&&" {
                op = T.and
            } else if op == OP.or.emit || op == "||" {
                op = T.or
            } else if op == "==" || op == OP.eq.emit {
                op = T.eq
            } else if op == "!=" || op == OP.neq.emit {
                op = T.neq
            } else if op == "<=" || op == OP.lte.emit {
                op = T.lte
            } else if op == ">=" || op == OP.gte.emit {
                op = T.gte
            } else if op == "%" || op == OP.mod.emit {
                op = T.mod
            }
            return "(\(expr(binaryOp.left)) \(op) \(expr(binaryOp.right)))"
        } else if let unaryOp = node as? UnaryOp {
            let op = (unaryOp.op == OP.not.emit || unaryOp.op == "!") ? T.not : unaryOp.op
            return "(\(op)\(expr(unaryOp.operand)))"
        } else if let funcCall = node as? FuncCall {
            let args = funcCall.args.map { expr($0) }.joined(separator: ", ")
            return "\(safeName(funcCall.name))(\(args))"
        }
        return ""
    }
}
