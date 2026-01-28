/// JibJab Objective-C++ Transpiler - Converts JJ to Objective-C++
/// Uses shared config from common/jj.json

class ObjCppTranspiler {
    private var indentLevel = 0
    private let T = loadTarget("objcpp")
    private var enums = Set<String>()  // Track defined enum names
    private var intVars = Set<String>()  // Track integer variable names
    private var doubleVars = Set<String>()  // Track double variable names

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
        } else if node is ArrayLiteral {
            return "Array"
        }
        return "Int"
    }

    private func getTargetType(_ jjType: String) -> String {
        return T.types?[jjType] ?? "int"
    }

    private func isFloatExpr(_ node: ASTNode) -> Bool {
        if let lit = node as? Literal { return lit.value is Double }
        if let v = node as? VarRef { return doubleVars.contains(v.name) }
        if let b = node as? BinaryOp { return isFloatExpr(b.left) || isFloatExpr(b.right) }
        if let u = node as? UnaryOp { return isFloatExpr(u.operand) }
        return false
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
                return ind() + "NSLog(@\"%@\", @\(expr(e)));"
            } else if let varRef = e as? VarRef {
                // Check if trying to print an enum type (not a value)
                if enums.contains(varRef.name) {
                    return ind() + "NSLog(@\"%@\", @\"enum \(varRef.name)\");"
                }
                // Integer variables need %ld format
                if intVars.contains(varRef.name) {
                    return ind() + "NSLog(@\"%ld\", (long)\(expr(e)));"
                }
                // Double variables need %g format
                if doubleVars.contains(varRef.name) {
                    return ind() + "NSLog(@\"%g\", \(expr(e)));"
                }
                return ind() + "NSLog(@\"%@\", \(expr(e)));"
            } else if let idx = e as? IndexAccess {
                // Check if this is enum value access
                if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                    return ind() + "NSLog(@\"%ld\", (long)\(expr(e)));"
                }
                return ind() + "NSLog(@\"%@\", \(expr(e)));"
            } else if e is ArrayLiteral {
                return ind() + "NSLog(@\"%@\", \(expr(e)));"
            }
            if isFloatExpr(e) {
                return ind() + "NSLog(@\"%g\", \(expr(e)));"
            }
            return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
        } else if let varDecl = node as? VarDecl {
            // Check if it's an array
            if varDecl.value is ArrayLiteral {
                return ind() + "NSArray *\(varDecl.name) = \(expr(varDecl.value));"
            }
            // Track variable types
            let inferredType = inferType(varDecl.value)
            if inferredType == "Int" {
                intVars.insert(varDecl.name)
            } else if inferredType == "Double" {
                doubleVars.insert(varDecl.name)
            }
            let varType = getTargetType(inferredType)
            return ind() + T.var
                .replacingOccurrences(of: "{type}", with: varType)
                .replacingOccurrences(of: "{name}", with: varDecl.name)
                .replacingOccurrences(of: "{value}", with: expr(varDecl.value))
        } else if let loopStmt = node as? LoopStmt {
            // Track loop variable as int
            intVars.insert(loopStmt.var)
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
            return ind() + "typedef NS_ENUM(NSInteger, \(enumDef.name)) { \(cases) };"
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
            return varRef.name
        } else if let arr = node as? ArrayLiteral {
            let elements = arr.elements.map { elem -> String in
                if let lit = elem as? Literal, lit.value is String {
                    return "@\(expr(elem))"  // @"string"
                } else if elem is ArrayLiteral {
                    return expr(elem)  // Nested arrays
                } else {
                    return "@(\(expr(elem)))"  // @(number)
                }
            }.joined(separator: ", ")
            return "@[\(elements)]"
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
