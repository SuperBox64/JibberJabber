/// JibJab JavaScript Transpiler - Converts JJ to JavaScript
/// Uses shared config from common/jj.json

public class JavaScriptTranspiler: Transpiling {
    public init() {}
    private var indentLevel = 0
    private let T = loadTarget("js")
    private var enums = Set<String>()

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
                result = String(result.dropLast(T.blockEnd.count)) + T.catchBlock
                indentLevel += 1
                result += "\n" + oopsBody.map { stmtToString($0) }.joined(separator: "\n")
                indentLevel -= 1
                result += "\n\(ind())\(T.blockEnd)"
            }
            return result
        } else if let funcDef = node as? FuncDef {
            let header = ind() + T.func
                .replacingOccurrences(of: "{name}", with: funcDef.name)
                .replacingOccurrences(of: "{params}", with: funcDef.params.joined(separator: ", "))
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
            let cases = enumDef.cases.map { "\($0): \"\($0)\"" }.joined(separator: ", ")
            let tmpl = T.enumTemplate ?? "const {name} = { {cases} };"
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
            let open = T.interpOpen ?? "`"
            let close = T.interpClose ?? "`"
            let varOpen = T.interpVarOpen ?? "${"
            let varClose = T.interpVarClose ?? "}"
            var tmpl = open
            for part in interp.parts {
                switch part {
                case .literal(let text): tmpl += escapeString(text)
                case .variable(let name): tmpl += "\(varOpen)\(name)\(varClose)"
                }
            }
            return tmpl + close
        } else if let varRef = node as? VarRef {
            return varRef.name
        } else if let binaryOp = node as? BinaryOp {
            var op = binaryOp.op
            if op == "==" { op = T.eq }
            if op == "!=" { op = T.neq }
            return "(\(expr(binaryOp.left)) \(op) \(expr(binaryOp.right)))"
        } else if let unaryOp = node as? UnaryOp {
            return "(\(unaryOp.op)\(expr(unaryOp.operand)))"
        } else if let funcCall = node as? FuncCall {
            let args = funcCall.args.map { expr($0) }.joined(separator: ", ")
            return T.call
                .replacingOccurrences(of: "{name}", with: funcCall.name)
                .replacingOccurrences(of: "{args}", with: args)
        } else if let idx = node as? IndexAccess {
            // Check if this is enum access (e.g., Color["Red"])
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                return "\(varRef.name)[\(expr(idx.index))]"
            }
            return "\(expr(idx.array))[\(expr(idx.index))]"
        } else if let arr = node as? ArrayLiteral {
            let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
            return "[\(elements)]"
        } else if let dict = node as? DictLiteral {
            let pairs = dict.pairs.map { "\(expr($0.key)): \(expr($0.value))" }.joined(separator: ", ")
            return "{ \(pairs) }"
        } else if let tuple = node as? TupleLiteral {
            let elements = tuple.elements.map { expr($0) }.joined(separator: ", ")
            return "[\(elements)]"
        }
        return ""
    }
}
