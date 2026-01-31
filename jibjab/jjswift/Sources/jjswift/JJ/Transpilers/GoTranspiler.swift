/// JibJab Go Transpiler - Converts JJ to Go
/// Uses shared C-family base from CFamilyTranspiler.swift
///
/// Dictionaries: expanded to individual variables (person_name, person_age, etc.)
/// Tuples: stored as numbered variables (_0, _1, _2)

public class GoTranspiler: CFamilyTranspiler {
    var needsMath = false

    public override init(target: String = "go") { super.init(target: target) }

    public override func transpile(_ program: Program) -> String {
        var lines: [String] = []

        let funcs = program.statements.compactMap { $0 as? FuncDef }
        let mainStmts = program.statements.filter { !($0 is FuncDef) }

        // First pass: generate function bodies and main to detect math import need
        var funcLines: [String] = []
        for f in funcs {
            funcLines.append(funcDefToString(f))
            funcLines.append("")
        }

        var mainLines: [String] = []
        if !mainStmts.isEmpty, let mainTmpl = T.main {
            indentLevel = 1
            let bodyLines = mainStmts.map { stmtToString($0) }
            let body = bodyLines.joined(separator: "\n") + "\n"
            let expanded = mainTmpl
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "{body}", with: body)
            mainLines.append(expanded)
        }

        // Build header from config, adding math import if needed
        var header = T.header.replacingOccurrences(of: "\\n", with: "\n")
            .trimmingCharacters(in: .newlines)
        if needsMath {
            // Replace single import with multi-import block
            header = header.replacingOccurrences(of: "import \"fmt\"",
                with: "import (\n\(T.indent)\"fmt\"\n\(T.indent)\"math\"\n)")
        }
        lines.append(header)
        lines.append("")

        // Emit functions
        for fl in funcLines { lines.append(fl) }

        // Emit main
        for ml in mainLines { lines.append(ml) }

        return lines.joined(separator: "\n")
    }

    func funcDefToString(_ node: FuncDef) -> String {
        let paramType = getTargetType("Int")
        let params = node.params.map { "\($0) \(paramType)" }.joined(separator: ", ")
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

    override func emitMain(_ lines: inout [String], _ program: Program) {
        // Not used - transpile() handles everything
    }

    override func varDeclToString(_ node: VarDecl) -> String {
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
        // Track enum variable assignments
        if let idx = node.value as? IndexAccess,
           let varRef = idx.array as? VarRef,
           enums.contains(varRef.name) {
            enumVarTypes[node.name] = varRef.name
        }
        let inferredType = inferType(node.value)
        if inferredType == "Bool" { boolVars.insert(node.name) }
        else if inferredType == "Int" && enumVarTypes[node.name] == nil { intVars.insert(node.name) }
        else if inferredType == "Double" { doubleVars.insert(node.name) }
        let tmpl = T.varShort ?? T.var
        return ind() + tmpl
            .replacingOccurrences(of: "{name}", with: node.name)
            .replacingOccurrences(of: "{value}", with: expr(node.value))
    }

    override func varArrayToString(_ node: VarDecl, _ arr: ArrayLiteral) -> String {
        if let firstElem = arr.elements.first {
            if let nestedArr = firstElem as? ArrayLiteral {
                let innerType = nestedArr.elements.first.map { getTargetType(inferType($0)) } ?? getTargetType("Int")
                let innerSize = nestedArr.elements.count
                let outerSize = arr.elements.count
                let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
                return ind() + "\(node.name) := [\(outerSize)][\(innerSize)]\(innerType){\(elements)}"
            }
            let elemType: String
            if let lit = firstElem as? Literal, lit.value is String {
                elemType = T.stringType
            } else {
                elemType = getTargetType(inferType(firstElem))
            }
            let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
            return ind() + "\(node.name) := []\(elemType){\(elements)}"
        }
        let intType = getTargetType("Int")
        return ind() + "\(node.name) := []\(intType){}"
    }

    override func printStmtToString(_ node: PrintStmt) -> String {
        let e = node.expr
        if let interp = e as? StringInterpolation {
            var fmt = ""
            var args: [String] = []
            for part in interp.parts {
                switch part {
                case .literal(let text): fmt += escapeString(text)
                case .variable(let name):
                    fmt += "%v"
                    args.append(interpVarExpr(name))
                }
            }
            let argStr = args.isEmpty ? "" : ", " + args.joined(separator: ", ")
            return ind() + "fmt.Printf(\"\(fmt)\\n\"\(argStr))"
        }
        if let lit = e as? Literal, lit.value is String {
            return ind() + "fmt.Println(\(expr(e)))"
        }
        if let varRef = e as? VarRef {
            // Enum variable - already a string, just print
            if enumVarTypes[varRef.name] != nil {
                return ind() + "fmt.Println(\(varRef.name))"
            }
            // Full enum - print dict representation
            if enums.contains(varRef.name) {
                if let cases = enumCases[varRef.name] {
                    let pairs = cases.map { "\\\"\($0)\\\": \($0)" }.joined(separator: ", ")
                    return ind() + "fmt.Println(\"{\(pairs)}\")"
                }
            }
            if doubleVars.contains(varRef.name) {
                return ind() + "fmt.Println(\(expr(e)))"
            }
            if stringVars.contains(varRef.name) {
                return ind() + "fmt.Println(\(expr(e)))"
            }
            if boolVars.contains(varRef.name) {
                return ind() + T.printBool.replacingOccurrences(of: "{expr}", with: expr(e))
            }
            // Print whole dict
            if dictVars.contains(varRef.name) {
                if let fields = dictFields[varRef.name], fields.isEmpty {
                    return ind() + "fmt.Println(\"{}\")"
                }
                return ind() + "fmt.Println(\"\(varRef.name)\")"
            }
            // Print whole tuple
            if tupleVars.contains(varRef.name) {
                return printWholeTuple(varRef.name)
            }
        }
        if let idx = e as? IndexAccess {
            // Enum access - already a string
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                return ind() + "fmt.Println(\(expr(e)))"
            }
            // Dict or tuple access
            if let resolved = resolveAccess(idx) {
                let (goVar, _) = resolved
                return ind() + "fmt.Println(\(goVar))"
            }
        }
        if isFloatExpr(e) {
            return ind() + "fmt.Println(\(expr(e)))"
        }
        return ind() + "fmt.Println(\(expr(e)))"
    }

    override func printWholeTuple(_ name: String) -> String {
        guard let fields = tupleFields[name], !fields.isEmpty else {
            return ind() + "fmt.Println(\"()\")"
        }
        let fmts = fields.map { _ in "%v" }.joined(separator: ", ")
        let args = fields.map { $0.0 }.joined(separator: ", ")
        return ind() + "fmt.Printf(\"(\(fmts))\\n\", \(args))"
    }

    override func enumToString(_ node: EnumDef) -> String {
        enums.insert(node.name)
        enumCases[node.name] = node.cases
        var lines: [String] = []
        lines.append(ind() + "const (")
        indentLevel += 1
        for c in node.cases {
            lines.append(ind() + "\(node.name)_\(c) = \"\(c)\"")
        }
        indentLevel -= 1
        lines.append(ind() + ")")
        return lines.joined(separator: "\n")
    }

    override func expr(_ node: ASTNode) -> String {
        if let idx = node as? IndexAccess {
            // Handle enum access
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                if let lit = idx.index as? Literal, let strVal = lit.value as? String {
                    return "\(varRef.name)_\(strVal)"
                }
            }
            if let resolved = resolveAccess(idx) { return resolved.0 }
        }
        if let binaryOp = node as? BinaryOp {
            if binaryOp.op == "%" && (isFloatExpr(binaryOp.left) || isFloatExpr(binaryOp.right)),
               let fm = T.floatMod {
                needsMath = true
                return fm.replacingOccurrences(of: "{left}", with: expr(binaryOp.left))
                         .replacingOccurrences(of: "{right}", with: expr(binaryOp.right))
            }
        }
        return super.expr(node)
    }
}
