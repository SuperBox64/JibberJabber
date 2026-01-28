/// JibJab C++ Transpiler - Converts JJ to C++
/// Uses shared C-family base from CFamilyTranspiler.swift

class CppTranspiler: CFamilyTranspiler {
    init() { super.init(target: "cpp") }

    override func printStmtToString(_ node: PrintStmt) -> String {
        let e = node.expr
        if let lit = e as? Literal, lit.value is String {
            return ind() + "std::cout << \(expr(e)) << std::endl;"
        }
        if let varRef = e as? VarRef, enums.contains(varRef.name) {
            return ind() + "std::cout << \"enum \(varRef.name)\" << std::endl;"
        }
        if let idx = e as? IndexAccess {
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                return ind() + "std::cout << \(expr(e)) << std::endl;"
            }
        }
        return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
    }

    override func exprDict(_ node: DictLiteral) -> String {
        let pairs = node.pairs.map { "{\(expr($0.0)), \(expr($0.1))}" }.joined(separator: ", ")
        return "{\(pairs)}"
    }

    override func exprTuple(_ node: TupleLiteral) -> String {
        let elements = node.elements.map { expr($0) }.joined(separator: ", ")
        return "std::make_tuple(\(elements))"
    }
}
