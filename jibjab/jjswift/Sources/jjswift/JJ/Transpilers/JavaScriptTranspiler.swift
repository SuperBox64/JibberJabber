/// JibJab JavaScript Transpiler - Converts JJ to JavaScript

class JavaScriptTranspiler {
    private var indentLevel = 0

    func transpile(_ program: Program) -> String {
        var lines = ["// Transpiled from JibJab", ""]
        for s in program.statements {
            lines.append(stmtToString(s))
        }
        return lines.joined(separator: "\n")
    }

    private func ind() -> String {
        return String(repeating: "    ", count: indentLevel)
    }

    private func stmtToString(_ node: ASTNode) -> String {
        if let printStmt = node as? PrintStmt {
            return "\(ind())console.log(\(expr(printStmt.expr)));"
        } else if let varDecl = node as? VarDecl {
            return "\(ind())let \(varDecl.name) = \(expr(varDecl.value));"
        } else if let loopStmt = node as? LoopStmt {
            var header: String
            if loopStmt.start != nil {
                header = "\(ind())for (let \(loopStmt.var) = \(expr(loopStmt.start!)); \(loopStmt.var) < \(expr(loopStmt.end!)); \(loopStmt.var)++) {"
            } else if let collection = loopStmt.collection {
                header = "\(ind())for (const \(loopStmt.var) of \(expr(collection))) {"
            } else {
                header = "\(ind())while (\(expr(loopStmt.condition!))) {"
            }
            indentLevel += 1
            let body = loopStmt.body.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            return "\(header)\n\(body)\n\(ind())}"
        } else if let ifStmt = node as? IfStmt {
            let header = "\(ind())if (\(expr(ifStmt.condition))) {"
            indentLevel += 1
            let thenBody = ifStmt.thenBody.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            var result = "\(header)\n\(thenBody)\n\(ind())}"
            if let elseBody = ifStmt.elseBody {
                result += " else {"
                indentLevel += 1
                result += "\n" + elseBody.map { stmtToString($0) }.joined(separator: "\n")
                indentLevel -= 1
                result += "\n\(ind())}"
            }
            return result
        } else if let funcDef = node as? FuncDef {
            let header = "\(ind())function \(funcDef.name)(\(funcDef.params.joined(separator: ", "))) {"
            indentLevel += 1
            let body = funcDef.body.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            return "\(header)\n\(body)\n\(ind())}"
        } else if let returnStmt = node as? ReturnStmt {
            return "\(ind())return \(expr(returnStmt.value));"
        }
        return ""
    }

    private func expr(_ node: ASTNode) -> String {
        if let literal = node as? Literal {
            if let str = literal.value as? String {
                return "\"\(str.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
            } else if literal.value == nil {
                return "null"
            } else if let bool = literal.value as? Bool {
                return bool ? "true" : "false"
            } else if let int = literal.value as? Int {
                return String(int)
            } else if let double = literal.value as? Double {
                return String(double)
            }
            return String(describing: literal.value ?? "null")
        } else if let varRef = node as? VarRef {
            return varRef.name
        } else if let binaryOp = node as? BinaryOp {
            var op = binaryOp.op
            if op == "==" { op = "===" }
            if op == "!=" { op = "!==" }
            return "(\(expr(binaryOp.left)) \(op) \(expr(binaryOp.right)))"
        } else if let unaryOp = node as? UnaryOp {
            return "(\(unaryOp.op)\(expr(unaryOp.operand)))"
        } else if let funcCall = node as? FuncCall {
            let args = funcCall.args.map { expr($0) }.joined(separator: ", ")
            return "\(funcCall.name)(\(args))"
        }
        return ""
    }
}
