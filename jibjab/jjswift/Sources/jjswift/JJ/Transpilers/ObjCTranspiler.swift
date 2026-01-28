/// JibJab Objective-C Transpiler - Converts JJ to Objective-C
/// Uses shared C-family base from CFamilyTranspiler.swift

class ObjCTranspiler: CFamilyTranspiler {
    init() { super.init(target: "objc") }

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
            return ind() + "NSLog(@\"%@\", @\(expr(e)));"
        }
        if let varRef = e as? VarRef {
            if enums.contains(varRef.name) {
                return ind() + "NSLog(@\"%@\", @\"enum \(varRef.name)\");"
            }
            if intVars.contains(varRef.name) {
                return ind() + "NSLog(@\"%ld\", (long)\(expr(e)));"
            }
            if doubleVars.contains(varRef.name) {
                return ind() + "NSLog(@\"%g\", \(expr(e)));"
            }
            return ind() + "NSLog(@\"%@\", \(expr(e)));"
        }
        if let idx = e as? IndexAccess {
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                return ind() + "NSLog(@\"%ld\", (long)\(expr(e)));"
            }
            return ind() + "NSLog(@\"%@\", \(expr(e)));"
        }
        if e is ArrayLiteral {
            return ind() + "NSLog(@\"%@\", \(expr(e)));"
        }
        if isFloatExpr(e) {
            return ind() + "NSLog(@\"%g\", \(expr(e)));"
        }
        return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
    }

    override func varArrayToString(_ node: VarDecl, _ arr: ArrayLiteral) -> String {
        return ind() + "NSArray *\(node.name) = \(expr(node.value));"
    }

    override func enumToString(_ node: EnumDef) -> String {
        enums.insert(node.name)
        let cases = node.cases.joined(separator: ", ")
        return ind() + "typedef NS_ENUM(NSInteger, \(node.name)) { \(cases) };"
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
        let pairs = node.pairs.map { "@\(expr($0.0)): @(\(expr($0.1)))" }.joined(separator: ", ")
        return "@{\(pairs)}"
    }

    override func exprTuple(_ node: TupleLiteral) -> String {
        let elements = node.elements.map { "@(\(expr($0)))" }.joined(separator: ", ")
        return "@[\(elements)]"
    }
}
