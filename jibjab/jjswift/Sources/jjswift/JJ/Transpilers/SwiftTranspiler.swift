/// JibJab Swift Transpiler - Converts JJ to Swift
/// Uses shared config from common/jj.json

class SwiftTranspiler {
    private var indentLevel = 0
    private let T = loadTarget("swift")
    private var doubleVars = Set<String>()
    private var enums = Set<String>()

    private func isFloatExpr(_ node: ASTNode) -> Bool {
        if let lit = node as? Literal { return lit.value is Double }
        if let v = node as? VarRef { return doubleVars.contains(v.name) }
        if let b = node as? BinaryOp { return isFloatExpr(b.left) || isFloatExpr(b.right) }
        if let u = node as? UnaryOp { return isFloatExpr(u.operand) }
        return false
    }

    private func inferType(_ node: ASTNode) -> String {
        if let literal = node as? Literal {
            if literal.value is Double { return "Double" }
        }
        return "Int"
    }

    func transpile(_ program: Program) -> String {
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
            if inferType(varDecl.value) == "Double" {
                doubleVars.insert(varDecl.name)
            }
            let template = T.varInfer ?? T.var
            return ind() + template
                .replacingOccurrences(of: "{name}", with: varDecl.name)
                .replacingOccurrences(of: "{value}", with: expr(varDecl.value))
        } else if let loopStmt = node as? LoopStmt {
            var header: String
            if loopStmt.start != nil {
                header = ind() + T.forRange
                    .replacingOccurrences(of: "{var}", with: loopStmt.var)
                    .replacingOccurrences(of: "{start}", with: expr(loopStmt.start!))
                    .replacingOccurrences(of: "{end}", with: expr(loopStmt.end!))
            } else if let collection = loopStmt.collection {
                header = ind() + T.forIn
                    .replacingOccurrences(of: "{var}", with: loopStmt.var)
                    .replacingOccurrences(of: "{collection}", with: expr(collection))
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
            // Swift requires typed parameters with _ to suppress argument labels
            let typedParams = funcDef.params.map { "_ \($0): Int" }.joined(separator: ", ")
            let header = ind() + T.func
                .replacingOccurrences(of: "{name}", with: funcDef.name)
                .replacingOccurrences(of: "{params}", with: typedParams)
            indentLevel += 1
            let body = funcDef.body.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            return "\(header)\n\(body)\n\(ind())\(T.blockEnd)"
        } else if let returnStmt = node as? ReturnStmt {
            return ind() + T.return.replacingOccurrences(of: "{value}", with: expr(returnStmt.value))
        } else if let enumDef = node as? EnumDef {
            enums.insert(enumDef.name)
            let cases = enumDef.cases.joined(separator: ", ")
            return ind() + "enum \(enumDef.name) { case \(cases) }"
        }
        return ""
    }

    private func expr(_ node: ASTNode) -> String {
        if let literal = node as? Literal {
            if let str = literal.value as? String {
                return "\"\(str.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
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
            // If referencing an enum type directly, use .self
            if enums.contains(varRef.name) {
                return "\(varRef.name).self"
            }
            return varRef.name
        } else if let binaryOp = node as? BinaryOp {
            // Use truncatingRemainder for float modulo in Swift
            if binaryOp.op == "%" && (isFloatExpr(binaryOp.left) || isFloatExpr(binaryOp.right)) {
                return "\(expr(binaryOp.left)).truncatingRemainder(dividingBy: \(expr(binaryOp.right)))"
            }
            return "(\(expr(binaryOp.left)) \(binaryOp.op) \(expr(binaryOp.right)))"
        } else if let unaryOp = node as? UnaryOp {
            return "(\(unaryOp.op)\(expr(unaryOp.operand)))"
        } else if let funcCall = node as? FuncCall {
            let args = funcCall.args.map { expr($0) }.joined(separator: ", ")
            return T.call
                .replacingOccurrences(of: "{name}", with: funcCall.name)
                .replacingOccurrences(of: "{args}", with: args)
        } else if let idx = node as? IndexAccess {
            // Check if this is enum access (e.g., Color["Red"] -> Color.Red)
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                if let lit = idx.index as? Literal, let strVal = lit.value as? String {
                    return "\(varRef.name).\(strVal)"
                }
            }
            return "\(expr(idx.array))[\(expr(idx.index))]"
        } else if let arr = node as? ArrayLiteral {
            let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
            return "[\(elements)]"
        } else if let dict = node as? DictLiteral {
            let pairs = dict.pairs.map { "\(expr($0.key)): \(expr($0.value))" }.joined(separator: ", ")
            return "[\(pairs)]"
        } else if let tuple = node as? TupleLiteral {
            let elements = tuple.elements.map { expr($0) }.joined(separator: ", ")
            return "(\(elements))"
        }
        return ""
    }
}
