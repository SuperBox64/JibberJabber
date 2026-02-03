/// JibJab Swift Transpiler - Converts JJ to Swift
/// Uses shared config from common/jj.json

public class SwiftTranspiler: Transpiling {
    public init() {}
    private var indentLevel = 0
    private let T = loadTarget("swift")
    private var doubleVars = Set<String>()
    private var enums = Set<String>()
    private var enumCases: [String: [String]] = [:]
    private var dictVars = Set<String>()
    private var tupleVars = Set<String>()

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

    public func transpile(_ program: Program) -> String {
        var lines = [T.header.trimmingCharacters(in: .newlines)]
        if needsErrorStruct(program.statements), let errStruct = T.errorStruct {
            lines.append("")
            lines.append(errStruct)
        }
        for s in program.statements {
            lines.append(stmtToString(s))
        }
        return lines.joined(separator: "\n")
    }

    private func needsErrorStruct(_ stmts: [ASTNode]) -> Bool {
        for s in stmts {
            if s is ThrowStmt || s is TryStmt { return true }
            if let ifStmt = s as? IfStmt {
                if needsErrorStruct(ifStmt.thenBody) { return true }
                if let elseBody = ifStmt.elseBody, needsErrorStruct(elseBody) { return true }
            }
            if let loop = s as? LoopStmt, needsErrorStruct(loop.body) { return true }
            if let fn = s as? FuncDef, needsErrorStruct(fn.body) { return true }
            if let tryStmt = s as? TryStmt {
                if needsErrorStruct(tryStmt.tryBody) { return true }
                if let oops = tryStmt.oopsBody, needsErrorStruct(oops) { return true }
            }
        }
        return false
    }

    private func ind() -> String {
        return String(repeating: T.indent, count: indentLevel)
    }

    private func stmtToString(_ node: ASTNode) -> String {
        if let printStmt = node as? PrintStmt {
            return ind() + T.print.replacingOccurrences(of: "{expr}", with: expr(printStmt.expr))
        } else if let logStmt = node as? LogStmt {
            return ind() + T.log.replacingOccurrences(of: "{expr}", with: expr(logStmt.expr))
        } else if let varDecl = node as? VarDecl {
            if inferType(varDecl.value) == "Double" {
                doubleVars.insert(varDecl.name)
            }
            // Dict declaration
            if let dictLit = varDecl.value as? DictLiteral {
                dictVars.insert(varDecl.name)
                let value = dictLit.pairs.isEmpty ? T.dictEmpty : expr(varDecl.value)
                let tmpl = T.varDict ?? T.var
                return ind() + tmpl
                    .replacingOccurrences(of: "{name}", with: varDecl.name)
                    .replacingOccurrences(of: "{value}", with: value)
                    .replacingOccurrences(of: "{type}", with: "")
            }
            // Tuple declaration
            if varDecl.value is TupleLiteral {
                tupleVars.insert(varDecl.name)
                let template = T.varInfer ?? T.var
                return ind() + template
                    .replacingOccurrences(of: "{name}", with: varDecl.name)
                    .replacingOccurrences(of: "{value}", with: expr(varDecl.value))
            }
            let template = T.varInfer ?? T.var
            return ind() + template
                .replacingOccurrences(of: "{name}", with: varDecl.name)
                .replacingOccurrences(of: "{value}", with: expr(varDecl.value))
        } else if let loopStmt = node as? LoopStmt {
            var header: String
            if let start = loopStmt.start, let end = loopStmt.end {
                header = ind() + T.forRange
                    .replacingOccurrences(of: "{var}", with: loopStmt.var)
                    .replacingOccurrences(of: "{start}", with: expr(start))
                    .replacingOccurrences(of: "{end}", with: expr(end))
            } else if let collection = loopStmt.collection {
                header = ind() + T.forIn
                    .replacingOccurrences(of: "{var}", with: loopStmt.var)
                    .replacingOccurrences(of: "{collection}", with: expr(collection))
            } else if let condition = loopStmt.condition {
                header = ind() + T.while.replacingOccurrences(of: "{condition}", with: expr(condition))
            } else {
                header = ind() + "\(T.comment) unsupported loop"
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
        } else if let tryStmt = node as? TryStmt {
            let header = ind() + T.tryBlock
            indentLevel += 1
            let tryBody = tryStmt.tryBody.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            var result = "\(header)\n\(tryBody)\n\(ind())\(T.blockEnd)"
            if let oopsBody = tryStmt.oopsBody {
                var catchTemplate = T.catchBlock
                if let varName = tryStmt.oopsVar, let cv = T.catchVar {
                    catchTemplate = cv.replacingOccurrences(of: "{var}", with: varName)
                }
                result = String(result.dropLast(T.blockEnd.count)) + catchTemplate
                indentLevel += 1
                if let varName = tryStmt.oopsVar, let bind = T.catchVarBind {
                    result += "\n" + ind() + bind.replacingOccurrences(of: "{var}", with: varName)
                }
                result += "\n" + oopsBody.map { stmtToString($0) }.joined(separator: "\n")
                indentLevel -= 1
                result += "\n\(ind())\(T.blockEnd)"
            }
            return result
        } else if let funcDef = node as? FuncDef {
            let paramFmt = T.paramFormat ?? "{name}: {type}"
            let paramType = T.types?["Int"] ?? "Int"
            let typedParams = funcDef.params.map {
                paramFmt.replacingOccurrences(of: "{name}", with: $0)
                        .replacingOccurrences(of: "{type}", with: paramType)
            }.joined(separator: ", ")
            let header = ind() + T.func
                .replacingOccurrences(of: "{name}", with: funcDef.name)
                .replacingOccurrences(of: "{params}", with: typedParams)
            indentLevel += 1
            let body = funcDef.body.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            return "\(header)\n\(body)\n\(ind())\(T.blockEnd)"
        } else if let returnStmt = node as? ReturnStmt {
            return ind() + T.return.replacingOccurrences(of: "{value}", with: expr(returnStmt.value))
        } else if let throwStmt = node as? ThrowStmt {
            if let tmpl = T.throwStmt {
                return ind() + tmpl.replacingOccurrences(of: "{value}", with: expr(throwStmt.value))
            }
            return ind() + T.comment + " throw " + expr(throwStmt.value)
        } else if let enumDef = node as? EnumDef {
            enums.insert(enumDef.name)
            enumCases[enumDef.name] = enumDef.cases
            let cases = enumDef.cases.joined(separator: ", ")
            let tmpl = T.enumTemplate ?? "enum {name} { case {cases} }"
            return ind() + tmpl.replacingOccurrences(of: "{name}", with: enumDef.name)
                               .replacingOccurrences(of: "{cases}", with: cases)
        } else if let comment = node as? CommentNode {
            return ind() + T.comment + " " + comment.text
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
        } else if let interp = node as? StringInterpolation {
            let open = T.interpOpen ?? "\""
            let close = T.interpClose ?? "\""
            let varOpen = T.interpVarOpen ?? "\\("
            let varClose = T.interpVarClose ?? ")"
            var result = open
            for part in interp.parts {
                switch part {
                case .literal(let text): result += escapeString(text)
                case .variable(let name): result += "\(varOpen)\(name)\(varClose)"
                }
            }
            return result + close
        } else if let varRef = node as? VarRef {
            // If referencing an enum type directly, generate dict representation
            if enums.contains(varRef.name) {
                if let cases = enumCases[varRef.name] {
                    let pairs = cases.map { "\\\"\($0)\\\": \($0)" }.joined(separator: ", ")
                    return "\"{\(pairs)}\""
                }
                return T.enumSelf.replacingOccurrences(of: "{name}", with: varRef.name)
            }
            return varRef.name
        } else if let binaryOp = node as? BinaryOp {
            if binaryOp.op == "%" && (isFloatExpr(binaryOp.left) || isFloatExpr(binaryOp.right)),
               let fm = T.floatMod {
                return fm.replacingOccurrences(of: "{left}", with: expr(binaryOp.left))
                         .replacingOccurrences(of: "{right}", with: expr(binaryOp.right))
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
                    return T.enumAccess
                        .replacingOccurrences(of: "{name}", with: varRef.name)
                        .replacingOccurrences(of: "{key}", with: strVal)
                }
            }
            // Tuple access: use .N dot syntax instead of [N]
            if let varRef = idx.array as? VarRef, tupleVars.contains(varRef.name) {
                if let lit = idx.index as? Literal, let intVal = lit.value as? Int {
                    return "\(varRef.name).\(intVal)"
                }
            }
            // Nested dict access (e.g., data["items"][0]) - must come before simple dict access
            if let innerIdx = idx.array as? IndexAccess {
                if let innerVarRef = innerIdx.array as? VarRef, dictVars.contains(innerVarRef.name) {
                    // Access raw dict value and safely cast to array
                    let key = expr(innerIdx.index)
                    let idxExpr = expr(idx.index)
                    return "(\(innerVarRef.name)[\(key)] as? [Any] ?? [])[\(idxExpr)]"
                }
                let inner = expr(innerIdx)
                let idxExpr = expr(idx.index)
                return "\(inner)[\(idxExpr)]"
            }
            // Dict access: use nil coalescing instead of force unwrap
            if let varRef = idx.array as? VarRef, dictVars.contains(varRef.name) {
                return "\(expr(varRef))[\(expr(idx.index))] as Any? ?? \"\""
            }
            return "\(expr(idx.array))[\(expr(idx.index))]"
        } else if let arr = node as? ArrayLiteral {
            let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
            return "[\(elements)]"
        } else if let dict = node as? DictLiteral {
            if dict.pairs.isEmpty { return T.dictEmpty }
            let pairs = dict.pairs.map { "\(expr($0.key)): \(expr($0.value))" }.joined(separator: ", ")
            return "[\(pairs)]"
        } else if let tuple = node as? TupleLiteral {
            if tuple.elements.isEmpty { return "()" }
            if tuple.elements.count == 1 {
                return "(\(expr(tuple.elements[0])),)"
            }
            let elements = tuple.elements.map { expr($0) }.joined(separator: ", ")
            return "(\(elements))"
        }
        return ""
    }
}
