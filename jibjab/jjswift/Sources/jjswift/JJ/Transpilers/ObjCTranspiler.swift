/// JibJab Objective-C Transpiler - Converts JJ to Objective-C
/// Uses shared config from common/jj.json

class ObjCTranspiler {
    private var indentLevel = 0
    private let T = JJ.targets.objc

    func transpile(_ program: Program) -> String {
        var lines = [T.header.trimmingCharacters(in: .newlines), ""]

        // Forward declarations
        let funcs = program.statements.compactMap { $0 as? FuncDef }
        for f in funcs {
            let params = f.params.map { "int \($0)" }.joined(separator: ", ")
            lines.append(T.funcDecl
                .replacingOccurrences(of: "{name}", with: f.name)
                .replacingOccurrences(of: "{params}", with: params))
        }
        if !funcs.isEmpty {
            lines.append("")
        }

        // Function definitions
        for f in funcs {
            lines.append(stmtToString(f))
            lines.append("")
        }

        // Main with @autoreleasepool
        let mainStmts = program.statements.filter { !($0 is FuncDef) }
        if !mainStmts.isEmpty {
            lines.append("int main(int argc, const char * argv[]) {")
            lines.append("    @autoreleasepool {")
            indentLevel = 2
            for s in mainStmts {
                lines.append(stmtToString(s))
            }
            lines.append("    }")
            lines.append("    return 0;")
            lines.append("}")
        }

        return lines.joined(separator: "\n")
    }

    private func ind() -> String {
        return String(repeating: T.indent, count: indentLevel)
    }

    private func stmtToString(_ node: ASTNode) -> String {
        if let printStmt = node as? PrintStmt {
            let e = printStmt.expr
            if let lit = e as? Literal, lit.value is String {
                // String literal - use @"string" format
                return ind() + "NSLog(@\"%@\", @\(expr(e)));"
            }
            return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
        } else if let varDecl = node as? VarDecl {
            return ind() + T.var
                .replacingOccurrences(of: "{name}", with: varDecl.name)
                .replacingOccurrences(of: "{value}", with: expr(varDecl.value))
        } else if let loopStmt = node as? LoopStmt {
            var header: String
            if loopStmt.start != nil {
                header = ind() + T.forRange
                    .replacingOccurrences(of: "{var}", with: loopStmt.var)
                    .replacingOccurrences(of: "{start}", with: expr(loopStmt.start!))
                    .replacingOccurrences(of: "{end}", with: expr(loopStmt.end!))
            } else {
                header = ind() + T.while.replacingOccurrences(of: "{condition}", with: expr(loopStmt.condition!))
            }
            indentLevel += 1
            let body = loopStmt.body.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            return "\(header)\n\(body)\n\(ind())\(T.blockEnd)"
        } else if let ifStmt = node as? IfStmt {
            let header = ind() + T.if.replacingOccurrences(of: "{condition}", with: expr(ifStmt.condition))
            indentLevel += 1
            let thenBody = ifStmt.thenBody.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            var result = "\(header)\n\(thenBody)\n\(ind())\(T.blockEnd)"
            if let elseBody = ifStmt.elseBody {
                result = String(result.dropLast(T.blockEnd.count)) + T.else
                indentLevel += 1
                result += "\n" + elseBody.map { stmtToString($0) }.joined(separator: "\n")
                indentLevel -= 1
                result += "\n\(ind())\(T.blockEnd)"
            }
            return result
        } else if let funcDef = node as? FuncDef {
            let params = funcDef.params.map { "int \($0)" }.joined(separator: ", ")
            let header = T.func
                .replacingOccurrences(of: "{name}", with: funcDef.name)
                .replacingOccurrences(of: "{params}", with: params)
            indentLevel = 1
            let body = funcDef.body.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel = 0
            return "\(header)\n\(body)\n\(T.blockEnd)"
        } else if let returnStmt = node as? ReturnStmt {
            return ind() + T.return.replacingOccurrences(of: "{value}", with: expr(returnStmt.value))
        }
        return ""
    }

    private func expr(_ node: ASTNode) -> String {
        if let literal = node as? Literal {
            if let str = literal.value as? String {
                return "\"\(str)\""
            } else if literal.value == nil {
                return T.nil
            } else if let bool = literal.value as? Bool {
                return bool ? T.true : T.false
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
            return T.call
                .replacingOccurrences(of: "{name}", with: funcCall.name)
                .replacingOccurrences(of: "{args}", with: args)
        }
        return ""
    }
}
