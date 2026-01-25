/// JibJab Python Transpiler - Converts JJ to Python

class PythonTranspiler {
    private var indentLevel = 0

    func transpile(_ program: Program) -> String {
        var lines = ["#!/usr/bin/env python3", "# Transpiled from JibJab", ""]
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
            return "\(ind())print(\(expr(printStmt.expr)))"
        } else if let varDecl = node as? VarDecl {
            return "\(ind())\(varDecl.name) = \(expr(varDecl.value))"
        } else if let loopStmt = node as? LoopStmt {
            var header: String
            if loopStmt.start != nil {
                header = "\(ind())for \(loopStmt.var) in range(\(expr(loopStmt.start!)), \(expr(loopStmt.end!))):"
            } else if let collection = loopStmt.collection {
                header = "\(ind())for \(loopStmt.var) in \(expr(collection)):"
            } else {
                header = "\(ind())while \(expr(loopStmt.condition!)):"
            }
            indentLevel += 1
            let body = loopStmt.body.map { stmtToString($0) }.joined(separator: "\n")
            let bodyStr = body.isEmpty ? "\(ind())pass" : body
            indentLevel -= 1
            return "\(header)\n\(bodyStr)"
        } else if let ifStmt = node as? IfStmt {
            let header = "\(ind())if \(expr(ifStmt.condition)):"
            indentLevel += 1
            let thenStr = ifStmt.thenBody.map { stmtToString($0) }.joined(separator: "\n")
            let thenBody = thenStr.isEmpty ? "\(ind())pass" : thenStr
            indentLevel -= 1
            var result = "\(header)\n\(thenBody)"
            if let elseBody = ifStmt.elseBody {
                result += "\n\(ind())else:"
                indentLevel += 1
                result += "\n" + elseBody.map { stmtToString($0) }.joined(separator: "\n")
                indentLevel -= 1
            }
            return result
        } else if let funcDef = node as? FuncDef {
            let header = "\(ind())def \(funcDef.name)(\(funcDef.params.joined(separator: ", "))):"
            indentLevel += 1
            let body = funcDef.body.map { stmtToString($0) }.joined(separator: "\n")
            let bodyStr = body.isEmpty ? "\(ind())pass" : body
            indentLevel -= 1
            return "\(header)\n\(bodyStr)"
        } else if let returnStmt = node as? ReturnStmt {
            return "\(ind())return \(expr(returnStmt.value))"
        }
        return ""
    }

    private func expr(_ node: ASTNode) -> String {
        if let literal = node as? Literal {
            if let str = literal.value as? String {
                return "\"\(str.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
            } else if literal.value == nil {
                return "None"
            } else if let bool = literal.value as? Bool {
                return bool ? "True" : "False"
            } else if let int = literal.value as? Int {
                return String(int)
            } else if let double = literal.value as? Double {
                return String(double)
            }
            return String(describing: literal.value ?? "None")
        } else if let varRef = node as? VarRef {
            return varRef.name
        } else if let binaryOp = node as? BinaryOp {
            var op = binaryOp.op
            if op == "&&" { op = "and" }
            if op == "||" { op = "or" }
            return "(\(expr(binaryOp.left)) \(op) \(expr(binaryOp.right)))"
        } else if let unaryOp = node as? UnaryOp {
            let op = unaryOp.op == "!" ? "not " : unaryOp.op
            return "(\(op)\(expr(unaryOp.operand)))"
        } else if let inputExpr = node as? InputExpr {
            return "input(\(expr(inputExpr.prompt)))"
        } else if let funcCall = node as? FuncCall {
            let args = funcCall.args.map { expr($0) }.joined(separator: ", ")
            return "\(funcCall.name)(\(args))"
        }
        return ""
    }
}
