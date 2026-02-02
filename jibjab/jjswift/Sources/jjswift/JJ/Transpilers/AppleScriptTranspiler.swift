/// JibJab AppleScript Transpiler - Converts JJ to AppleScript
/// Uses shared config from common/targets/applescript.json

public class AppleScriptTranspiler: Transpiling {
    public init() {}
    private var indentLevel = 0
    private let T = loadTarget("applescript")
    private let OP = JJ.operators
    private var enums: [String: [String]] = [:]
    private var dictVars = Set<String>()

    private lazy var reserved: Set<String> = Set(T.reservedWords.map { $0.lowercased() })

    private func safeName(_ name: String) -> String {
        reserved.contains(name.lowercased()) ? "\(T.reservedPrefix)\(name)" : name
    }

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
            if let varRef = printStmt.expr as? VarRef, dictVars.contains(varRef.name) {
                let name = safeName(varRef.name)
                let blockEndIf = T.blockEndIf ?? T.blockEnd
                var lines: [String] = []
                lines.append(ind() + T.if.replacingOccurrences(of: "{condition}", with: "\(name) is {}"))
                lines.append(ind() + T.indent + T.print.replacingOccurrences(of: "{expr}", with: "\"{}\""))
                lines.append(ind() + T.else)
                lines.append(ind() + T.indent + T.print.replacingOccurrences(of: "{expr}", with: name))
                lines.append(ind() + blockEndIf)
                return lines.joined(separator: "\n")
            }
            return ind() + T.print.replacingOccurrences(of: "{expr}", with: expr(printStmt.expr))
        } else if let varDecl = node as? VarDecl {
            if varDecl.value is DictLiteral {
                dictVars.insert(varDecl.name)
            }
            return ind() + T.var
                .replacingOccurrences(of: "{name}", with: safeName(varDecl.name))
                .replacingOccurrences(of: "{value}", with: expr(varDecl.value))
        } else if let loopStmt = node as? LoopStmt {
            var header: String
            if let start = loopStmt.start, let end = loopStmt.end {
                header = ind() + T.forRange
                    .replacingOccurrences(of: "{var}", with: safeName(loopStmt.var))
                    .replacingOccurrences(of: "{start}", with: expr(start))
                    .replacingOccurrences(of: "{end}", with: expr(end))
            } else if let collection = loopStmt.collection {
                header = ind() + T.forIn
                    .replacingOccurrences(of: "{var}", with: safeName(loopStmt.var))
                    .replacingOccurrences(of: "{collection}", with: expr(collection))
            } else if let condition = loopStmt.condition {
                header = ind() + T.while.replacingOccurrences(of: "{condition}", with: expr(condition))
            } else {
                header = ind() + "\(T.comment) unsupported loop"
            }
            indentLevel += 1
            let body = loopStmt.body.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            let blockEndRepeat = T.blockEndRepeat ?? T.blockEnd
            return "\(header)\n\(body)\n\(ind())\(blockEndRepeat)"
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
            let blockEndIf = T.blockEndIf ?? T.blockEnd
            result += "\n\(ind())\(blockEndIf)"
            return result
        } else if let tryStmt = node as? TryStmt {
            let header = ind() + T.tryBlock
            indentLevel += 1
            let tryBody = tryStmt.tryBody.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            var result = "\(header)\n\(tryBody)"
            if let oopsBody = tryStmt.oopsBody {
                var catchTemplate = T.catchBlock
                if let varName = tryStmt.oopsVar, let cv = T.catchVar {
                    catchTemplate = cv.replacingOccurrences(of: "{var}", with: safeName(varName))
                }
                result += "\n\(ind())\(catchTemplate)"
                indentLevel += 1
                if let varName = tryStmt.oopsVar, let bind = T.catchVarBind {
                    result += "\n" + ind() + bind.replacingOccurrences(of: "{var}", with: safeName(varName))
                }
                result += "\n" + oopsBody.map { stmtToString($0) }.joined(separator: "\n")
                indentLevel -= 1
            }
            let blockEndTry = T.blockEndTry ?? T.blockEnd
            result += "\n\(ind())\(blockEndTry)"
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
            let blockEndFunc = T.blockEndFunc?.replacingOccurrences(of: "{name}", with: safeFuncName) ?? T.blockEnd
            return "\(header)\n\(body)\n\(ind())\(blockEndFunc)"
        } else if let returnStmt = node as? ReturnStmt {
            return ind() + T.return.replacingOccurrences(of: "{value}", with: expr(returnStmt.value))
        } else if let throwStmt = node as? ThrowStmt {
            if let tmpl = T.throwStmt {
                return ind() + tmpl.replacingOccurrences(of: "{value}", with: expr(throwStmt.value))
            }
            return ind() + T.comment + " throw " + expr(throwStmt.value)
        } else if let enumDef = node as? EnumDef {
            let safeEnumName = safeName(enumDef.name)
            enums[enumDef.name] = enumDef.cases
            let pairs = enumDef.cases.map { "\($0):\"\($0)\"" }.joined(separator: ", ")
            return ind() + T.var
                .replacingOccurrences(of: "{name}", with: safeEnumName)
                .replacingOccurrences(of: "{value}", with: "{\(pairs)}")
        } else if let comment = node as? CommentNode {
            return ind() + T.comment + " " + comment.text
        }
        return ""
    }

    private func expr(_ node: ASTNode) -> String {
        if let interp = node as? StringInterpolation {
            let concat = T.interpConcat ?? " & "
            var parts: [String] = []
            for part in interp.parts {
                switch part {
                case .literal(let text):
                    if !text.isEmpty { parts.append("\"\(escapeString(text))\"") }
                case .variable(let name):
                    if let castTmpl = T.interpCast {
                        parts.append(castTmpl.replacingOccurrences(of: "{name}", with: safeName(name)))
                    } else {
                        parts.append(safeName(name))
                    }
                }
            }
            if parts.isEmpty { return "\"\"" }
            return parts.joined(separator: concat)
        }
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
            let pairs = dict.pairs.map { pair -> String in
                var key = expr(pair.0)
                if key.hasPrefix("\"") && key.hasSuffix("\"") {
                    key = String(key.dropFirst().dropLast())
                }
                return "\(safeName(key)):\(expr(pair.1))"
            }.joined(separator: ", ")
            return "{\(pairs)}"
        } else if let tuple = node as? TupleLiteral {
            let elements = tuple.elements.map { expr($0) }.joined(separator: ", ")
            return "{\(elements)}"
        } else if let idx = node as? IndexAccess {
            // Enum access
            if let varRef = idx.array as? VarRef, enums[varRef.name] != nil {
                if let lit = idx.index as? Literal, let strVal = lit.value as? String {
                    return T.enumAccess
                        .replacingOccurrences(of: "{key}", with: strVal)
                        .replacingOccurrences(of: "{name}", with: safeName(varRef.name))
                }
            }
            // Dict access
            if let varRef = idx.array as? VarRef, dictVars.contains(varRef.name) {
                if let lit = idx.index as? Literal, let strVal = lit.value as? String {
                    return T.propertyAccess
                        .replacingOccurrences(of: "{key}", with: safeName(strVal))
                        .replacingOccurrences(of: "{object}", with: safeName(varRef.name))
                }
            }
            // Array/nested access
            return T.indexAccess
                .replacingOccurrences(of: "{index}", with: expr(idx.index))
                .replacingOccurrences(of: "{array}", with: expr(idx.array))
        } else if let binaryOp = node as? BinaryOp {
            var op = binaryOp.op
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
            return T.call
                .replacingOccurrences(of: "{name}", with: safeName(funcCall.name))
                .replacingOccurrences(of: "{args}", with: args)
        }
        return ""
    }
}
