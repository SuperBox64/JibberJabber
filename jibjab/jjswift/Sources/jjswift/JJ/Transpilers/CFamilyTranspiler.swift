/// JibJab C-Family Base Transpiler
/// Shared logic for C, C++, Objective-C, and Objective-C++ transpilers.
/// Subclasses override specific methods for target-specific behavior.

public class CFamilyTranspiler {
    var indentLevel = 0
    let T: TargetConfig
    var enums = Set<String>()
    var doubleVars = Set<String>()
    var intVars = Set<String>()
    var dictVars = Set<String>()
    var tupleVars = Set<String>()

    public init(target: String) {
        T = loadTarget(target)
    }

    func inferType(_ node: ASTNode) -> String {
        if let literal = node as? Literal {
            if literal.value is Bool { return "Int" }
            else if literal.value is Int { return "Int" }
            else if literal.value is Double { return "Double" }
            else if literal.value is String { return "String" }
        } else if let arr = node as? ArrayLiteral {
            if let first = arr.elements.first { return inferType(first) }
            return "Int"
        }
        return "Int"
    }

    func getTargetType(_ jjType: String) -> String {
        return T.types?[jjType] ?? "int"
    }

    func isFloatExpr(_ node: ASTNode) -> Bool {
        if let lit = node as? Literal { return lit.value is Double }
        if let v = node as? VarRef { return doubleVars.contains(v.name) }
        if let b = node as? BinaryOp { return isFloatExpr(b.left) || isFloatExpr(b.right) }
        if let u = node as? UnaryOp { return isFloatExpr(u.operand) }
        return false
    }

    public func transpile(_ program: Program) -> String {
        var lines = [T.header.trimmingCharacters(in: .newlines), ""]

        let funcs = program.statements.compactMap { $0 as? FuncDef }
        for f in funcs {
            let paramType = getTargetType("Int")
            let params = f.params.map { "\(paramType) \($0)" }.joined(separator: ", ")
            let returnType = getTargetType("Int")
            lines.append(T.funcDecl
                .replacingOccurrences(of: "{type}", with: returnType)
                .replacingOccurrences(of: "{name}", with: f.name)
                .replacingOccurrences(of: "{params}", with: params))
        }
        if !funcs.isEmpty { lines.append("") }

        for f in funcs {
            lines.append(stmtToString(f))
            lines.append("")
        }

        emitMain(&lines, program)
        return lines.joined(separator: "\n")
    }

    func emitMain(_ lines: inout [String], _ program: Program) {
        let mainStmts = program.statements.filter { !($0 is FuncDef) }
        if !mainStmts.isEmpty {
            lines.append("int main() {")
            indentLevel = 1
            for s in mainStmts { lines.append(stmtToString(s)) }
            lines.append("\(T.indent)return 0;")
            lines.append("}")
        }
    }

    func ind() -> String {
        return String(repeating: T.indent, count: indentLevel)
    }

    func stmtToString(_ node: ASTNode) -> String {
        if let printStmt = node as? PrintStmt {
            return printStmtToString(printStmt)
        } else if let varDecl = node as? VarDecl {
            return varDeclToString(varDecl)
        } else if let loopStmt = node as? LoopStmt {
            return loopToString(loopStmt)
        } else if let ifStmt = node as? IfStmt {
            return ifToString(ifStmt)
        } else if let funcDef = node as? FuncDef {
            return funcToString(funcDef)
        } else if let returnStmt = node as? ReturnStmt {
            return ind() + T.return.replacingOccurrences(of: "{value}", with: expr(returnStmt.value))
        } else if let enumDef = node as? EnumDef {
            return enumToString(enumDef)
        }
        return ""
    }

    func printStmtToString(_ node: PrintStmt) -> String {
        let e = node.expr
        if let lit = e as? Literal, lit.value is String {
            return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        if let varRef = e as? VarRef {
            if enums.contains(varRef.name) {
                return ind() + "printf(\"%s\\n\", \"enum \(varRef.name)\");"
            }
            if doubleVars.contains(varRef.name) {
                return ind() + T.printFloat.replacingOccurrences(of: "{expr}", with: expr(e))
            }
        }
        if let idx = e as? IndexAccess {
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
            }
        }
        if isFloatExpr(e) {
            return ind() + T.printFloat.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
    }

    func varDeclToString(_ node: VarDecl) -> String {
        if let arr = node.value as? ArrayLiteral {
            return varArrayToString(node, arr)
        }
        if let tuple = node.value as? TupleLiteral {
            tupleVars.insert(node.name)
            return varTupleToString(node, tuple)
        }
        if node.value is DictLiteral {
            dictVars.insert(node.name)
            return varDictToString(node)
        }
        let inferredType = inferType(node.value)
        if inferredType == "Int" { intVars.insert(node.name) }
        else if inferredType == "Double" { doubleVars.insert(node.name) }
        let varType = getTargetType(inferredType)
        return ind() + T.var
            .replacingOccurrences(of: "{type}", with: varType)
            .replacingOccurrences(of: "{name}", with: node.name)
            .replacingOccurrences(of: "{value}", with: expr(node.value))
    }

    func varArrayToString(_ node: VarDecl, _ arr: ArrayLiteral) -> String {
        if let firstElem = arr.elements.first {
            if let nestedArr = firstElem as? ArrayLiteral {
                let innerType = nestedArr.elements.first.map { getTargetType(inferType($0)) } ?? "int"
                let innerSize = nestedArr.elements.count
                let outerSize = arr.elements.count
                let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
                return ind() + "\(innerType) \(node.name)[\(outerSize)][\(innerSize)] = {\(elements)};"
            }
            let elemType: String
            if let lit = firstElem as? Literal, lit.value is String {
                elemType = "const char*"
            } else {
                elemType = getTargetType(inferType(firstElem))
            }
            let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
            return ind() + "\(elemType) \(node.name)[] = {\(elements)};"
        }
        return ind() + "int \(node.name)[] = {};"
    }

    func varTupleToString(_ node: VarDecl, _ tuple: TupleLiteral) -> String {
        if let firstElem = tuple.elements.first {
            let elemType: String
            if let lit = firstElem as? Literal, lit.value is String {
                elemType = "const char*"
            } else {
                elemType = getTargetType(inferType(firstElem))
            }
            let elements = tuple.elements.map { expr($0) }.joined(separator: ", ")
            return ind() + "\(elemType) \(node.name)[] = {\(elements)};"
        }
        return ind() + "int \(node.name)[] = {};"
    }

    func varDictToString(_ node: VarDecl) -> String {
        return ind() + "// dict \(node.name) not supported in C"
    }

    func loopToString(_ node: LoopStmt) -> String {
        var header: String
        if let start = node.start, let end = node.end {
            header = ind() + T.forRange
                .replacingOccurrences(of: "{var}", with: node.var)
                .replacingOccurrences(of: "{start}", with: expr(start))
                .replacingOccurrences(of: "{end}", with: expr(end))
        } else if let condition = node.condition {
            header = ind() + T.while.replacingOccurrences(of: "{condition}", with: expr(condition))
        } else {
            header = ind() + "// unsupported loop"
        }
        indentLevel += 1
        let body = node.body.map { stmtToString($0) }.joined(separator: "\n")
        indentLevel -= 1
        return "\(header)\n\(body)\n\(ind())\(T.blockEnd)"
    }

    func ifToString(_ node: IfStmt) -> String {
        let header = ind() + T.if.replacingOccurrences(of: "{condition}", with: expr(node.condition))
        indentLevel += 1
        let thenBody = node.thenBody.map { stmtToString($0) }.joined(separator: "\n")
        indentLevel -= 1
        var result = "\(header)\n\(thenBody)\n\(ind())\(T.blockEnd)"
        if let elseBody = node.elseBody {
            result = String(result.dropLast(T.blockEnd.count)) + T.else
            indentLevel += 1
            result += "\n" + elseBody.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            result += "\n\(ind())\(T.blockEnd)"
        }
        return result
    }

    func funcToString(_ node: FuncDef) -> String {
        let paramType = getTargetType("Int")
        let params = node.params.map { "\(paramType) \($0)" }.joined(separator: ", ")
        let returnType = getTargetType("Int")
        let header = T.func
            .replacingOccurrences(of: "{type}", with: returnType)
            .replacingOccurrences(of: "{name}", with: node.name)
            .replacingOccurrences(of: "{params}", with: params)
        indentLevel = 1
        let body = node.body.map { stmtToString($0) }.joined(separator: "\n")
        indentLevel = 0
        return "\(header)\n\(body)\n\(T.blockEnd)"
    }

    func enumToString(_ node: EnumDef) -> String {
        enums.insert(node.name)
        let cases = node.cases.joined(separator: ", ")
        return ind() + "enum \(node.name) { \(cases) };"
    }

    func expr(_ node: ASTNode) -> String {
        if let literal = node as? Literal {
            if let str = literal.value as? String { return "\"\(escapeString(str))\"" }
            else if literal.value == nil { return T.nil }
            else if let bool = literal.value as? Bool { return bool ? T.true : T.false }
            else if let int = literal.value as? Int { return String(int) }
            else if let double = literal.value as? Double { return String(double) }
            return "0"
        } else if let varRef = node as? VarRef {
            return varRef.name
        } else if let arr = node as? ArrayLiteral {
            return exprArray(arr)
        } else if let dict = node as? DictLiteral {
            return exprDict(dict)
        } else if let tuple = node as? TupleLiteral {
            return exprTuple(tuple)
        } else if let idx = node as? IndexAccess {
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                if let lit = idx.index as? Literal, let strVal = lit.value as? String {
                    return strVal
                }
            }
            return "\(expr(idx.array))[\(expr(idx.index))]"
        } else if let binaryOp = node as? BinaryOp {
            if binaryOp.op == "%" && (isFloatExpr(binaryOp.left) || isFloatExpr(binaryOp.right)) {
                return "fmod(\(expr(binaryOp.left)), \(expr(binaryOp.right)))"
            }
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

    func exprArray(_ node: ArrayLiteral) -> String {
        let elements = node.elements.map { expr($0) }.joined(separator: ", ")
        return "{\(elements)}"
    }

    func exprDict(_ node: DictLiteral) -> String {
        let pairs = node.pairs.map { "/* \(expr($0.0)): \(expr($0.1)) */" }.joined(separator: ", ")
        return "/* dict: {\(pairs)} */"
    }

    func exprTuple(_ node: TupleLiteral) -> String {
        let elements = node.elements.map { expr($0) }.joined(separator: ", ")
        return "{\(elements)}"
    }
}
