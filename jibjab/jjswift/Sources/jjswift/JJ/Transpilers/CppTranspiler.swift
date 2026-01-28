/// JibJab C++ Transpiler - Converts JJ to C++
/// Uses shared config from common/jj.json

class CppTranspiler {
    private var indentLevel = 0
    private let T = loadTarget("cpp")
    private var enums = Set<String>()  // Track defined enum names
    private var intVars = Set<String>()  // Track integer variable names
    private var doubleVars = Set<String>()  // Track double variable names

    private func isFloatExpr(_ node: ASTNode) -> Bool {
        if let lit = node as? Literal { return lit.value is Double }
        if let v = node as? VarRef { return doubleVars.contains(v.name) }
        if let b = node as? BinaryOp { return isFloatExpr(b.left) || isFloatExpr(b.right) }
        if let u = node as? UnaryOp { return isFloatExpr(u.operand) }
        return false
    }

    private func inferType(_ node: ASTNode) -> String {
        if let literal = node as? Literal {
            if literal.value is Bool {
                return "Int"
            } else if literal.value is Int {
                return "Int"
            } else if literal.value is Double {
                return "Double"
            } else if literal.value is String {
                return "String"
            }
        } else if let arr = node as? ArrayLiteral {
            if let first = arr.elements.first {
                return inferType(first)
            }
            return "Int"
        }
        return "Int"
    }

    private func getTargetType(_ jjType: String) -> String {
        return T.types?[jjType] ?? "int"
    }

    func transpile(_ program: Program) -> String {
        var lines = [T.header.trimmingCharacters(in: .newlines), ""]

        // Forward declarations
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
            lines.append("\(T.indent)return 0;")
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
                return ind() + "std::cout << \(expr(e)) << std::endl;"
            } else if let varRef = e as? VarRef {
                // Check if trying to print an enum type (not a value)
                if enums.contains(varRef.name) {
                    return ind() + "std::cout << \"enum \(varRef.name)\" << std::endl;"
                }
            } else if let idx = e as? IndexAccess {
                // Check if this is enum value access
                if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                    return ind() + "std::cout << \(expr(e)) << std::endl;"
                }
            }
            return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(printStmt.expr))
        } else if let varDecl = node as? VarDecl {
            // Check if it's an array
            if let arr = varDecl.value as? ArrayLiteral {
                if let firstElem = arr.elements.first {
                    if let nestedArr = firstElem as? ArrayLiteral {
                        // 2D array
                        let innerType = nestedArr.elements.first.map { getTargetType(inferType($0)) } ?? "int"
                        let innerSize = nestedArr.elements.count
                        let outerSize = arr.elements.count
                        let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
                        return ind() + "\(innerType) \(varDecl.name)[\(outerSize)][\(innerSize)] = {\(elements)};"
                    }
                    // Check if it's a string array
                    let elemType: String
                    if let lit = firstElem as? Literal, lit.value is String {
                        elemType = "const char*"
                    } else {
                        elemType = getTargetType(inferType(firstElem))
                    }
                    let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
                    return ind() + "\(elemType) \(varDecl.name)[] = {\(elements)};"
                }
                return ind() + "int \(varDecl.name)[] = {};"
            }
            // Track variable types
            let inferredType = inferType(varDecl.value)
            if inferredType == "Int" {
                intVars.insert(varDecl.name)
            } else if inferredType == "Double" {
                doubleVars.insert(varDecl.name)
            }
            let varType = getTargetType(inferType(varDecl.value))
            return ind() + T.var
                .replacingOccurrences(of: "{type}", with: varType)
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
            let paramType = getTargetType("Int")
            let params = funcDef.params.map { "\(paramType) \($0)" }.joined(separator: ", ")
            let returnType = getTargetType("Int")
            let header = T.func
                .replacingOccurrences(of: "{type}", with: returnType)
                .replacingOccurrences(of: "{name}", with: funcDef.name)
                .replacingOccurrences(of: "{params}", with: params)
            indentLevel = 1
            let body = funcDef.body.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel = 0
            return "\(header)\n\(body)\n\(T.blockEnd)"
        } else if let returnStmt = node as? ReturnStmt {
            return ind() + T.return.replacingOccurrences(of: "{value}", with: expr(returnStmt.value))
        } else if let enumDef = node as? EnumDef {
            enums.insert(enumDef.name)
            let cases = enumDef.cases.joined(separator: ", ")
            return ind() + "enum \(enumDef.name) { \(cases) };"
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
                return String(double)
            }
            return "0"
        } else if let varRef = node as? VarRef {
            // Check if trying to use an enum type as a value (for printing)
            if enums.contains(varRef.name) {
                return "0"  // Placeholder for enum type printing
            }
            return varRef.name
        } else if let arr = node as? ArrayLiteral {
            let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
            return "{\(elements)}"
        } else if let dict = node as? DictLiteral {
            let pairs = dict.pairs.map { "{\(expr($0.0)), \(expr($0.1))}" }.joined(separator: ", ")
            return "{\(pairs)}"
        } else if let tuple = node as? TupleLiteral {
            let elements = tuple.elements.map { expr($0) }.joined(separator: ", ")
            return "std::make_tuple(\(elements))"
        } else if let idx = node as? IndexAccess {
            // Check if this is enum access (e.g., Color["Red"] -> Red)
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                if let lit = idx.index as? Literal, let strVal = lit.value as? String {
                    return strVal  // Just return the enum case name
                }
            }
            return "\(expr(idx.array))[\(expr(idx.index))]"
        } else if let binaryOp = node as? BinaryOp {
            // Use fmod for float modulo
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
}
