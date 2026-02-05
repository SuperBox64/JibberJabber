/// JibJab Python Transpiler - Converts JJ to Python
/// Uses shared config from common/jj.json

public class PythonTranspiler: Transpiling {
    public init() {}
    private var indentLevel = 0
    private let T = loadTarget("py")
    private var enums = Set<String>()
    private var boolVars = Set<String>()
    private var needsRandomImport = false

    public func transpile(_ program: Program) -> String {
        // Check if random is used
        needsRandomImport = containsRandom(program.statements)

        var lines = [T.header.trimmingCharacters(in: .newlines)]
        if needsRandomImport, let randomImport = T.randomImport {
            lines.append(randomImport)
        }
        if needsInput(program.statements), let inputHelper = T.inputHelper {
            lines.append(inputHelper)
        }
        for s in program.statements {
            lines.append(stmtToString(s))
        }
        return lines.joined(separator: "\n")
    }

    private func needsInput(_ stmts: [ASTNode]) -> Bool {
        for s in stmts {
            if let varDecl = s as? VarDecl, varDecl.value is InputExpr { return true }
            if let ifStmt = s as? IfStmt {
                if needsInput(ifStmt.thenBody) { return true }
                if let elseBody = ifStmt.elseBody, needsInput(elseBody) { return true }
            }
            if let loop = s as? LoopStmt, needsInput(loop.body) { return true }
            if let fn = s as? FuncDef, needsInput(fn.body) { return true }
            if let tryStmt = s as? TryStmt {
                if needsInput(tryStmt.tryBody) { return true }
                if let oops = tryStmt.oopsBody, needsInput(oops) { return true }
            }
        }
        return false
    }

    private func containsRandom(_ nodes: [ASTNode]) -> Bool {
        for node in nodes {
            if node is RandomExpr { return true }
            if let printStmt = node as? PrintStmt, containsRandomExpr(printStmt.expr) { return true }
            if let logStmt = node as? LogStmt, containsRandomExpr(logStmt.expr) { return true }
            if let varDecl = node as? VarDecl, containsRandomExpr(varDecl.value) { return true }
            if let constDecl = node as? ConstDecl, containsRandomExpr(constDecl.value) { return true }
            if let loopStmt = node as? LoopStmt, containsRandom(loopStmt.body) { return true }
            if let ifStmt = node as? IfStmt {
                if containsRandom(ifStmt.thenBody) { return true }
                if let elseBody = ifStmt.elseBody, containsRandom(elseBody) { return true }
            }
            if let funcDef = node as? FuncDef, containsRandom(funcDef.body) { return true }
            if let tryStmt = node as? TryStmt {
                if containsRandom(tryStmt.tryBody) { return true }
                if let oopsBody = tryStmt.oopsBody, containsRandom(oopsBody) { return true }
            }
        }
        return false
    }

    private func containsRandomExpr(_ node: ASTNode) -> Bool {
        if node is RandomExpr { return true }
        if let binary = node as? BinaryOp {
            return containsRandomExpr(binary.left) || containsRandomExpr(binary.right)
        }
        if let unary = node as? UnaryOp {
            return containsRandomExpr(unary.operand)
        }
        return false
    }

    private func ind() -> String {
        return String(repeating: T.indent, count: indentLevel)
    }

    private func stmtToString(_ node: ASTNode) -> String {
        if let printStmt = node as? PrintStmt {
            if let varRef = printStmt.expr as? VarRef, boolVars.contains(varRef.name) {
                return ind() + T.printBool.replacingOccurrences(of: "{expr}", with: expr(printStmt.expr))
            }
            return ind() + T.print.replacingOccurrences(of: "{expr}", with: expr(printStmt.expr))
        } else if let logStmt = node as? LogStmt {
            if let varRef = logStmt.expr as? VarRef, boolVars.contains(varRef.name) {
                return ind() + T.logBool.replacingOccurrences(of: "{expr}", with: expr(logStmt.expr))
            }
            return ind() + T.log.replacingOccurrences(of: "{expr}", with: expr(logStmt.expr))
        } else if let varDecl = node as? VarDecl {
            if let lit = varDecl.value as? Literal, lit.value is Bool {
                boolVars.insert(varDecl.name)
            }
            return ind() + T.var
                .replacingOccurrences(of: "{name}", with: varDecl.name)
                .replacingOccurrences(of: "{value}", with: expr(varDecl.value))
        } else if let constDecl = node as? ConstDecl {
            if let lit = constDecl.value as? Literal, lit.value is Bool {
                boolVars.insert(constDecl.name)
            }
            return ind() + T.const
                .replacingOccurrences(of: "{name}", with: constDecl.name)
                .replacingOccurrences(of: "{value}", with: expr(constDecl.value))
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
            let bodyStr = body.isEmpty ? "\(ind())\(T.emptyBody ?? "")" : body
            indentLevel -= 1
            return "\(header)\n\(bodyStr)"
        } else if let ifStmt = node as? IfStmt {
            let header = ind() + T.if.replacingOccurrences(of: "{condition}", with: expr(ifStmt.condition))
            indentLevel += 1
            let thenStr = ifStmt.thenBody.map { stmtToString($0) }.joined(separator: "\n")
            let thenBody = thenStr.isEmpty ? "\(ind())pass" : thenStr
            indentLevel -= 1
            var result = "\(header)\n\(thenBody)"
            if let elseBody = ifStmt.elseBody {
                result += "\n\(ind())\(T.else)"
                indentLevel += 1
                result += "\n" + elseBody.map { stmtToString($0) }.joined(separator: "\n")
                indentLevel -= 1
            }
            return result
        } else if let tryStmt = node as? TryStmt {
            let header = ind() + T.tryBlock
            indentLevel += 1
            let tryStr = tryStmt.tryBody.map { stmtToString($0) }.joined(separator: "\n")
            let tryBody = tryStr.isEmpty ? "\(ind())\(T.emptyBody ?? "pass")" : tryStr
            indentLevel -= 1
            var result = "\(header)\n\(tryBody)"
            if let oopsBody = tryStmt.oopsBody {
                var catchTemplate = T.catchBlock
                if let varName = tryStmt.oopsVar, let cv = T.catchVar {
                    catchTemplate = cv.replacingOccurrences(of: "{var}", with: varName)
                }
                result += "\n\(ind())\(catchTemplate)"
                indentLevel += 1
                if let varName = tryStmt.oopsVar, let bind = T.catchVarBind {
                    result += "\n" + ind() + bind.replacingOccurrences(of: "{var}", with: varName)
                }
                let oopsStr = oopsBody.map { stmtToString($0) }.joined(separator: "\n")
                result += "\n" + (oopsStr.isEmpty ? "\(ind())\(T.emptyBody ?? "pass")" : oopsStr)
                indentLevel -= 1
            }
            return result
        } else if let funcDef = node as? FuncDef {
            let header = ind() + T.func
                .replacingOccurrences(of: "{name}", with: funcDef.name)
                .replacingOccurrences(of: "{params}", with: funcDef.params.joined(separator: ", "))
            indentLevel += 1
            let body = funcDef.body.map { stmtToString($0) }.joined(separator: "\n")
            let bodyStr = body.isEmpty ? "\(ind())\(T.emptyBody ?? "")" : body
            indentLevel -= 1
            return "\(header)\n\(bodyStr)"
        } else if let returnStmt = node as? ReturnStmt {
            return ind() + T.return.replacingOccurrences(of: "{value}", with: expr(returnStmt.value))
        } else if let throwStmt = node as? ThrowStmt {
            if let tmpl = T.throwStmt {
                return ind() + tmpl.replacingOccurrences(of: "{value}", with: expr(throwStmt.value))
            }
            return ind() + T.comment + " throw " + expr(throwStmt.value)
        } else if let enumDef = node as? EnumDef {
            enums.insert(enumDef.name)
            let cases = enumDef.cases.map { "\"\($0)\": \"\($0)\"" }.joined(separator: ", ")
            if let tmpl = T.enumTemplate {
                return ind() + tmpl.replacingOccurrences(of: "{name}", with: enumDef.name)
                                   .replacingOccurrences(of: "{cases}", with: cases)
            }
            return ind() + "\(enumDef.name) = {\(cases)}"
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
            let open = T.interpOpen ?? "f\""
            let close = T.interpClose ?? "\""
            let varOpen = T.interpVarOpen ?? "{"
            let varClose = T.interpVarClose ?? "}"
            var fstr = open
            for part in interp.parts {
                switch part {
                case .literal(let text): fstr += escapeString(text)
                case .variable(let name): fstr += "\(varOpen)\(name)\(varClose)"
                }
            }
            return fstr + close
        } else if let varRef = node as? VarRef {
            return varRef.name
        } else if let arrayLit = node as? ArrayLiteral {
            let elements = arrayLit.elements.map { expr($0) }.joined(separator: ", ")
            return "[\(elements)]"
        } else if let dictLit = node as? DictLiteral {
            let pairs = dictLit.pairs.map { "\(expr($0.key)): \(expr($0.value))" }.joined(separator: ", ")
            return "{\(pairs)}"
        } else if let tupleLit = node as? TupleLiteral {
            let elements = tupleLit.elements.map { expr($0) }.joined(separator: ", ")
            // Single element tuple needs trailing comma in Python
            if tupleLit.elements.count == 1 {
                return "(\(elements),)"
            }
            return "(\(elements))"
        } else if let indexAccess = node as? IndexAccess {
            return "\(expr(indexAccess.array))[\(expr(indexAccess.index))]"
        } else if let binaryOp = node as? BinaryOp {
            var op = binaryOp.op
            if op == "&&" { op = T.and }
            if op == "||" { op = T.or }
            return "(\(expr(binaryOp.left)) \(op) \(expr(binaryOp.right)))"
        } else if let unaryOp = node as? UnaryOp {
            let op = unaryOp.op == "!" ? T.not : unaryOp.op
            return "(\(op)\(expr(unaryOp.operand)))"
        } else if let inputExpr = node as? InputExpr {
            if let tmpl = T.input {
                return tmpl.replacingOccurrences(of: "{prompt}", with: expr(inputExpr.prompt))
            }
            return "input(\(expr(inputExpr.prompt)))"
        } else if let funcCall = node as? FuncCall {
            let args = funcCall.args.map { expr($0) }.joined(separator: ", ")
            return T.call
                .replacingOccurrences(of: "{name}", with: funcCall.name)
                .replacingOccurrences(of: "{args}", with: args)
        } else if let randomExpr = node as? RandomExpr {
            if let tmpl = T.random {
                return tmpl
                    .replacingOccurrences(of: "{min}", with: expr(randomExpr.min))
                    .replacingOccurrences(of: "{max}", with: expr(randomExpr.max))
            }
            return "0"
        }
        return ""
    }
}
