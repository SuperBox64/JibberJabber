/// JibJab Objective-C Transpiler - Converts JJ to Objective-C
/// Uses shared C-family base from CFamilyTranspiler.swift

public class ObjCTranspiler: CFamilyTranspiler {
    public override init(target: String = "objc") { super.init(target: target) }

    override func emitMain(_ lines: inout [String], _ program: Program) {
        let mainStmts = program.statements.filter { !($0 is FuncDef) }
        if !mainStmts.isEmpty {
            lines.append("int main(int argc, const char * argv[]) {")
            lines.append("    @autoreleasepool {")
            indentLevel = 2
            for s in mainStmts { lines.append(stmtToString(s)) }
            lines.append("    }")
            lines.append("    return 0;")
            lines.append("}")
        }
    }

    override func loopToString(_ node: LoopStmt) -> String {
        intVars.insert(node.var)
        return super.loopToString(node)
    }

    override func printStmtToString(_ node: PrintStmt) -> String {
        let e = node.expr
        if let lit = e as? Literal, lit.value is String {
            return ind() + "printf(\"%s\\n\", \(expr(e)));"
        }
        if let varRef = e as? VarRef {
            if enums.contains(varRef.name) {
                return ind() + "printf(\"enum \(varRef.name)\\n\");"
            }
            if doubleVars.contains(varRef.name) {
                return ind() + "printf(\"%f\\n\", \(expr(e)));"
            }
            if intVars.contains(varRef.name) {
                return ind() + "printf(\"%ld\\n\", (long)\(expr(e)));"
            }
            return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        if e is ArrayLiteral {
            return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        if let idx = e as? IndexAccess {
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                return ind() + "printf(\"%ld\\n\", (long)\(expr(e)));"
            }
            return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        if isFloatExpr(e) {
            return ind() + "printf(\"%f\\n\", \(expr(e)));"
        }
        return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
    }

    override func varArrayToString(_ node: VarDecl, _ arr: ArrayLiteral) -> String {
        return ind() + "NSArray *\(node.name) = \(expr(node.value));"
    }

    override func varDictToString(_ node: VarDecl) -> String {
        guard let dict = node.value as? DictLiteral else { return "" }
        if dict.pairs.isEmpty {
            return ind() + "NSDictionary *\(node.name) = @{};"
        }
        return ind() + "NSDictionary *\(node.name) = \(expr(node.value));"
    }

    override func varTupleToString(_ node: VarDecl, _ tuple: TupleLiteral) -> String {
        return ind() + "NSArray *\(node.name) = \(expr(node.value));"
    }

    override func enumToString(_ node: EnumDef) -> String {
        enums.insert(node.name)
        let cases = node.cases.joined(separator: ", ")
        return ind() + "typedef NS_ENUM(NSInteger, \(node.name)) { \(cases) };"
    }

    override func expr(_ node: ASTNode) -> String {
        if let idx = node as? IndexAccess {
            // Dict access: use @"key" syntax
            if let varRef = idx.array as? VarRef, dictVars.contains(varRef.name) {
                if let lit = idx.index as? Literal, let key = lit.value as? String {
                    return "\(varRef.name)[@\"\(key)\"]"
                }
                return "\(expr(idx.array))[@(\(expr(idx.index)))]"
            }
            // Nested: data[@"items"][0]
            if let innerIdx = idx.array as? IndexAccess {
                if let innerVarRef = innerIdx.array as? VarRef, dictVars.contains(innerVarRef.name) {
                    let inner = expr(innerIdx)
                    return "\(inner)[\(expr(idx.index))]"
                }
            }
        }
        return super.expr(node)
    }

    override func exprArray(_ node: ArrayLiteral) -> String {
        let elements = node.elements.map { elem -> String in
            if let lit = elem as? Literal, lit.value is String {
                return "@\(expr(elem))"
            } else if elem is ArrayLiteral {
                return expr(elem)
            } else {
                return "@(\(expr(elem)))"
            }
        }.joined(separator: ", ")
        return "@[\(elements)]"
    }

    override func exprDict(_ node: DictLiteral) -> String {
        func boxValue(_ v: ASTNode) -> String {
            if let lit = v as? Literal, lit.value is String {
                return "@\(expr(v))"
            } else if v is ArrayLiteral {
                return expr(v)
            } else {
                return "@(\(expr(v)))"
            }
        }
        let pairs = node.pairs.map { "@\(expr($0.0)): \(boxValue($0.1))" }.joined(separator: ", ")
        return "@{\(pairs)}"
    }

    override func exprTuple(_ node: TupleLiteral) -> String {
        let elements = node.elements.map { elem -> String in
            if let lit = elem as? Literal, lit.value is String {
                return "@\(expr(elem))"
            } else {
                return "@(\(expr(elem)))"
            }
        }.joined(separator: ", ")
        return "@[\(elements)]"
    }
}
