/// JibJab AppleScript Transpiler - Converts JJ to AppleScript
/// Uses shared config from common/targets/applescript.json

public class AppleScriptTranspiler: Transpiling {
    public init() {}
    private var indentLevel = 0
    private let T = loadTarget("applescript")
    private let OP = JJ.operators
    private var enums: [String: [String]] = [:]
    private var dictVars = Set<String>()
    private var intVars = Set<String>()
    private var inputStringVars = Set<String>()
    private var inNumericConversionContext = false
    private var needsStringHelpers = false

    private lazy var reserved: Set<String> = Set(T.reservedWords.map { $0.lowercased() })

    private func safeName(_ name: String) -> String {
        reserved.contains(name.lowercased()) ? "\(T.reservedPrefix)\(name)" : name
    }

    public func transpile(_ program: Program) -> String {
        needsStringHelpers = containsStringMethod(program.statements)
        var lines = [T.header.trimmingCharacters(in: .newlines)]
        if needsInput(program.statements), let inputHelper = T.inputHelper {
            lines.append("")
            lines.append(inputHelper)
        }
        if needsStringHelpers {
            lines.append("")
            lines.append(stringHelpers())
        }
        lines.append("")  // Blank line after header/imports
        var hadCode = false
        for s in program.statements {
            if s is CommentNode && hadCode {
                lines.append("")  // Blank line before comment after code
            }
            if !(s is CommentNode) {
                hadCode = true
            }
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
        } else if let logStmt = node as? LogStmt {
            return ind() + T.log.replacingOccurrences(of: "{expr}", with: expr(logStmt.expr))
        } else if let varDecl = node as? VarDecl {
            if varDecl.value is DictLiteral {
                dictVars.insert(varDecl.name)
            }
            if varDecl.value is InputExpr {
                inputStringVars.insert(varDecl.name)
                intVars.remove(varDecl.name)  // Input returns string, not int
            } else if let lit = varDecl.value as? Literal, lit.value is Int {
                intVars.insert(varDecl.name)
                inputStringVars.remove(varDecl.name)
            } else if varDecl.value is RandomExpr {
                intVars.insert(varDecl.name)
                inputStringVars.remove(varDecl.name)
            }
            return ind() + T.var
                .replacingOccurrences(of: "{name}", with: safeName(varDecl.name))
                .replacingOccurrences(of: "{value}", with: expr(varDecl.value))
        } else if let constDecl = node as? ConstDecl {
            return ind() + T.const
                .replacingOccurrences(of: "{name}", with: safeName(constDecl.name))
                .replacingOccurrences(of: "{value}", with: expr(constDecl.value))
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

    private func isNumericExpr(_ node: ASTNode) -> Bool {
        if let lit = node as? Literal { return lit.value is Int || lit.value is Double }
        if let v = node as? VarRef { return intVars.contains(v.name) }
        if let b = node as? BinaryOp { return isNumericExpr(b.left) || isNumericExpr(b.right) }
        if node is RandomExpr { return true }
        return false
    }

    private func exprWithNumericConversion(_ node: ASTNode, otherSide: ASTNode) -> String {
        // Always convert variables to integer when compared with numeric expressions
        // This is necessary because input() may reassign variables inside loops
        // Use _toInt helper for safe conversion (returns 0 for non-numeric strings)
        if let varRef = node as? VarRef, isNumericExpr(otherSide) {
            return "_toInt(\(safeName(varRef.name)))"
        }
        // Set flag to prevent expr from doing numeric conversion again (avoid infinite recursion)
        let wasInContext = inNumericConversionContext
        inNumericConversionContext = true
        defer { inNumericConversionContext = wasInContext }
        return expr(node)
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
            // Use numeric conversion for comparisons (only at top level to avoid infinite recursion)
            let isComparison = ["<", ">", "<=", ">=", "==", "!=", T.eq, T.neq, T.lte, T.gte,
                                OP.lt.emit, OP.gt.emit, OP.lte.emit, OP.gte.emit, OP.eq.emit, OP.neq.emit].contains(binaryOp.op)
            if isComparison && !inNumericConversionContext {
                let leftExpr = exprWithNumericConversion(binaryOp.left, otherSide: binaryOp.right)
                let rightExpr = exprWithNumericConversion(binaryOp.right, otherSide: binaryOp.left)
                return "(\(leftExpr) \(op) \(rightExpr))"
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
        } else if let randomExpr = node as? RandomExpr {
            if let tmpl = T.random {
                return tmpl
                    .replacingOccurrences(of: "{min}", with: expr(randomExpr.min))
                    .replacingOccurrences(of: "{max}", with: expr(randomExpr.max))
            }
            return "0"
        } else if let inputExpr = node as? InputExpr {
            if let tmpl = T.input {
                return tmpl.replacingOccurrences(of: "{prompt}", with: expr(inputExpr.prompt))
            }
            return "\"\""
        } else if let mc = node as? MethodCallExpr, mc.args.count >= 1 {
            let s = expr(mc.args[0])
            switch mc.method {
            case "upper": return "_jj_upper(\(s))"
            case "lower": return "_jj_lower(\(s))"
            case "length": return "(count of \(s))"
            case "trim": return "_jj_trim(\(s))"
            case "replace" where mc.args.count >= 3:
                return "_jj_replace(\(s), \(expr(mc.args[1])), \(expr(mc.args[2])))"
            case "contains" where mc.args.count >= 2:
                return "(\(s) contains \(expr(mc.args[1])))"
            case "split" where mc.args.count >= 2:
                return "_jj_split(\(s), \(expr(mc.args[1])))"
            case "substring" where mc.args.count >= 3:
                return "(text (\(expr(mc.args[1])) + 1) thru \(expr(mc.args[2])) of \(s))"
            default: return "\"\""
            }
        }
        return ""
    }

    private func containsStringMethod(_ stmts: [ASTNode]) -> Bool {
        for s in stmts {
            if containsStringMethodInNode(s) { return true }
        }
        return false
    }

    private func containsStringMethodInNode(_ node: ASTNode) -> Bool {
        if node is MethodCallExpr { return true }
        if let v = node as? VarDecl { return containsStringMethodInNode(v.value) }
        if let c = node as? ConstDecl { return containsStringMethodInNode(c.value) }
        if let p = node as? PrintStmt { return containsStringMethodInNode(p.expr) }
        if let l = node as? LogStmt { return containsStringMethodInNode(l.expr) }
        if let i = node as? IfStmt {
            if containsStringMethodInNode(i.condition) { return true }
            if containsStringMethod(i.thenBody) { return true }
            if let e = i.elseBody, containsStringMethod(e) { return true }
        }
        if let loop = node as? LoopStmt { return containsStringMethod(loop.body) }
        if let fn = node as? FuncDef { return containsStringMethod(fn.body) }
        if let t = node as? TryStmt {
            if containsStringMethod(t.tryBody) { return true }
            if let o = t.oopsBody, containsStringMethod(o) { return true }
        }
        if let b = node as? BinaryOp {
            return containsStringMethodInNode(b.left) || containsStringMethodInNode(b.right)
        }
        if let u = node as? UnaryOp { return containsStringMethodInNode(u.operand) }
        if let r = node as? ReturnStmt { return containsStringMethodInNode(r.value) }
        return false
    }

    private func stringHelpers() -> String {
        return """
        on _jj_upper(s)
        \treturn do shell script "echo " & quoted form of s & " | tr '[:lower:]' '[:upper:]'"
        end _jj_upper

        on _jj_lower(s)
        \treturn do shell script "echo " & quoted form of s & " | tr '[:upper:]' '[:lower:]'"
        end _jj_lower

        on _jj_trim(s)
        \treturn do shell script "echo " & quoted form of s & " | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'"
        end _jj_trim

        on _jj_replace(s, old, new)
        \tset AppleScript's text item delimiters to old
        \tset parts to text items of s
        \tset AppleScript's text item delimiters to new
        \tset r to parts as text
        \tset AppleScript's text item delimiters to ""
        \treturn r
        end _jj_replace

        on _jj_split(s, d)
        \tset AppleScript's text item delimiters to d
        \tset parts to text items of s
        \tset AppleScript's text item delimiters to ""
        \treturn parts
        end _jj_split
        """
    }
}
