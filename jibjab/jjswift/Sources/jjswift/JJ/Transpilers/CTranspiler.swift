/// JibJab C Transpiler - Converts JJ to C

class CTranspiler {
    private var indentLevel = 0

    func transpile(_ program: Program) -> String {
        var lines = [
            "// Transpiled from JibJab",
            "#include <stdio.h>",
            "#include <stdlib.h>",
            ""
        ]

        // Forward declarations
        let funcs = program.statements.compactMap { $0 as? FuncDef }
        for f in funcs {
            let params = f.params.map { "int \($0)" }.joined(separator: ", ")
            lines.append("int \(f.name)(\(params));")
        }
        if !funcs.isEmpty {
            lines.append("")
        }

        // Function definitions
        for f in funcs {
            lines.append(stmtToString(f))
            lines.append("")
        }

        // Main
        let mainStmts = program.statements.filter { !($0 is FuncDef) }
        if !mainStmts.isEmpty {
            lines.append("int main() {")
            indentLevel = 1
            for s in mainStmts {
                lines.append(stmtToString(s))
            }
            lines.append("    return 0;")
            lines.append("}")
        }

        return lines.joined(separator: "\n")
    }

    private func ind() -> String {
        return String(repeating: "    ", count: indentLevel)
    }

    private func stmtToString(_ node: ASTNode) -> String {
        if let printStmt = node as? PrintStmt {
            let e = printStmt.expr
            if let lit = e as? Literal, lit.value is String {
                return "\(ind())printf(\"%s\\n\", \(expr(e)));"
            }
            return "\(ind())printf(\"%d\\n\", \(expr(e)));"
        } else if let varDecl = node as? VarDecl {
            return "\(ind())int \(varDecl.name) = \(expr(varDecl.value));"
        } else if let loopStmt = node as? LoopStmt {
            var header: String
            if loopStmt.start != nil {
                header = "\(ind())for (int \(loopStmt.var) = \(expr(loopStmt.start!)); \(loopStmt.var) < \(expr(loopStmt.end!)); \(loopStmt.var)++) {"
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
            let params = funcDef.params.map { "int \($0)" }.joined(separator: ", ")
            let header = "int \(funcDef.name)(\(params)) {"
            indentLevel = 1
            let body = funcDef.body.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel = 0
            return "\(header)\n\(body)\n}"
        } else if let returnStmt = node as? ReturnStmt {
            return "\(ind())return \(expr(returnStmt.value));"
        }
        return ""
    }

    private func expr(_ node: ASTNode) -> String {
        if let literal = node as? Literal {
            if let str = literal.value as? String {
                return "\"\(str)\""
            } else if literal.value == nil {
                return "0"
            } else if let bool = literal.value as? Bool {
                return bool ? "1" : "0"
            } else if let int = literal.value as? Int {
                return String(int)
            } else if let double = literal.value as? Double {
                return String(Int(double))
            }
            return "0"
        } else if let varRef = node as? VarRef {
            return varRef.name
        } else if let binaryOp = node as? BinaryOp {
            return "(\(expr(binaryOp.left)) \(binaryOp.op) \(expr(binaryOp.right)))"
        } else if let unaryOp = node as? UnaryOp {
            return "(\(unaryOp.op)\(expr(unaryOp.operand)))"
        } else if let funcCall = node as? FuncCall {
            let args = funcCall.args.map { expr($0) }.joined(separator: ", ")
            return "\(funcCall.name)(\(args))"
        }
        return ""
    }
}
