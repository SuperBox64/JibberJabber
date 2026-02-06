/// JibJab Go Transpiler - Converts JJ to Go
/// Uses shared C-family base from CFamilyTranspiler.swift
///
/// Dictionaries: expanded to individual variables (person_name, person_age, etc.)
/// Tuples: stored as numbered variables (_0, _1, _2)

public class GoTranspiler: CFamilyTranspiler {
    var needsMath = false
    var needsLog = false
    var needsRandom = false
    var needsStrings = false
    var needsInputHelper = false
    var declaredVars = Set<String>()  // Track declared variables for := vs =

    public override init(target: String = "go") { super.init(target: target) }

    private func detectInput(_ stmts: [ASTNode]) -> Bool {
        for s in stmts {
            if let varDecl = s as? VarDecl, varDecl.value is InputExpr { return true }
            if let ifStmt = s as? IfStmt {
                if detectInput(ifStmt.thenBody) { return true }
                if let elseBody = ifStmt.elseBody, detectInput(elseBody) { return true }
            }
            if let loop = s as? LoopStmt, detectInput(loop.body) { return true }
            if let fn = s as? FuncDef, detectInput(fn.body) { return true }
            if let tryStmt = s as? TryStmt {
                if detectInput(tryStmt.tryBody) { return true }
                if let oops = tryStmt.oopsBody, detectInput(oops) { return true }
            }
        }
        return false
    }

    public override func transpile(_ program: Program) -> String {
        var lines: [String] = []

        // Detect if input is used
        needsInputHelper = detectInput(program.statements)

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
            var bodyLines: [String] = []
            var hadCode = false
            for s in mainStmts {
                if s is CommentNode && hadCode {
                    bodyLines.append("")  // Blank line before comment after code
                }
                if !(s is CommentNode) {
                    hadCode = true
                }
                bodyLines.append(stmtToString(s))
            }
            let body = bodyLines.joined(separator: "\n") + "\n"
            let expanded = mainTmpl
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "{body}", with: body)
            mainLines.append(expanded)
        }

        // Build header from config, adding imports conditionally
        var header = T.header.replacingOccurrences(of: "\\n", with: "\n")
            .trimmingCharacters(in: .newlines)
        // Replace placeholder with input imports or empty
        if needsInputHelper {
            header = header.replacingOccurrences(of: "{INPUT_IMPORT}", with: "    \"bufio\"\n    \"os\"\n    \"strconv\"\n")
        } else {
            header = header.replacingOccurrences(of: "{INPUT_IMPORT}", with: "")
        }
        // Replace placeholder with math import or empty
        if needsMath {
            header = header.replacingOccurrences(of: "{MATH_IMPORT}", with: "    \"math\"\n")
        } else {
            header = header.replacingOccurrences(of: "{MATH_IMPORT}", with: "")
        }
        // Replace placeholder with rand import or empty
        if needsRandom {
            header = header.replacingOccurrences(of: "{RAND_IMPORT}", with: "    \"math/rand\"\n")
        } else {
            header = header.replacingOccurrences(of: "{RAND_IMPORT}", with: "")
        }
        if needsStrings {
            header = header.replacingOccurrences(of: "{STRINGS_IMPORT}", with: "    \"strings\"\n")
        } else {
            header = header.replacingOccurrences(of: "{STRINGS_IMPORT}", with: "")
        }
        lines.append(header)

        // Add input helper if needed
        if needsInputHelper, let inputHelper = T.inputHelper {
            lines.append(inputHelper)
        }
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
            declaredVars.insert(node.name)
            return varArrayToString(node, arr)
        }
        if let tuple = node.value as? TupleLiteral {
            tupleVars.insert(node.name)
            declaredVars.insert(node.name)
            return varTupleToString(node, tuple)
        }
        if node.value is DictLiteral {
            dictVars.insert(node.name)
            declaredVars.insert(node.name)
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

        // Check if this is a reassignment (variable already declared)
        let isReassignment = declaredVars.contains(node.name)
        declaredVars.insert(node.name)

        // Handle input assignment to int variable - need to convert string to int
        var valueExpr = expr(node.value)
        if node.value is InputExpr && intVars.contains(node.name) {
            // Replace _input with _inputInt for int variables
            valueExpr = valueExpr.replacingOccurrences(of: "_input(", with: "_inputInt(")
        }

        // Use = for reassignment, := for new declaration
        let tmpl = isReassignment ? "{name} = {value}" : (T.varShort ?? T.var)
        return ind() + tmpl
            .replacingOccurrences(of: "{name}", with: node.name)
            .replacingOccurrences(of: "{value}", with: valueExpr)
    }

    override func constDeclToString(_ node: ConstDecl) -> String {
        let inferredType = inferType(node.value)
        if inferredType == "Bool" { boolVars.insert(node.name) }
        else if inferredType == "Int" { intVars.insert(node.name) }
        else if inferredType == "Double" { doubleVars.insert(node.name) }
        else if inferredType == "String" { stringVars.insert(node.name) }
        let tmpl = T.constInfer ?? T.const
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

    override func logStmtToString(_ node: LogStmt) -> String {
        needsLog = true
        return super.logStmtToString(node)
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
                    fmt += interpFormatSpecifier(name)
                    args.append(interpVarExpr(name))
                }
            }
            let argStr = args.isEmpty ? "" : ", " + args.joined(separator: ", ")
            return ind() + T.printfInterp
                .replacingOccurrences(of: "{fmt}", with: fmt)
                .replacingOccurrences(of: "{args}", with: argStr)
        }
        if let lit = e as? Literal, lit.value is String {
            return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        if let varRef = e as? VarRef {
            // Enum variable - already a string, just print
            if enumVarTypes[varRef.name] != nil {
                return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: varRef.name)
            }
            // Full enum - print dict representation
            if enums.contains(varRef.name) {
                if let cases = enumCases[varRef.name] {
                    let pairs = cases.map { "\\\"\($0)\\\": \($0)" }.joined(separator: ", ")
                    return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: "\"{\(pairs)}\"")
                }
            }
            if doubleVars.contains(varRef.name) {
                return ind() + T.printFloat.replacingOccurrences(of: "{expr}", with: expr(e))
            }
            if stringVars.contains(varRef.name) {
                return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: expr(e))
            }
            if boolVars.contains(varRef.name) {
                return ind() + T.printBool.replacingOccurrences(of: "{expr}", with: expr(e))
            }
            // Print whole dict
            if dictVars.contains(varRef.name) {
                if let fields = dictFields[varRef.name], fields.isEmpty {
                    return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: "\"{}\"")
                }
                return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: "\"\(varRef.name)\"")
            }
            // Print whole tuple
            if tupleVars.contains(varRef.name) {
                return printWholeTuple(varRef.name)
            }
        }
        if let idx = e as? IndexAccess {
            // Enum access - already a string
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: expr(e))
            }
            // Dict or tuple access
            if let resolved = resolveAccess(idx) {
                let (goVar, _) = resolved
                return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: goVar)
            }
        }
        if isFloatExpr(e) {
            return ind() + T.printFloat.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
    }

    override func printWholeTuple(_ name: String) -> String {
        guard let fields = tupleFields[name], !fields.isEmpty else {
            return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: "\"()\"")
        }
        let fmts = fields.map { _ in T.intFmt }.joined(separator: ", ")
        let args = fields.map { $0.0 }.joined(separator: ", ")
        return ind() + T.printfInterp
            .replacingOccurrences(of: "{fmt}", with: "(\(fmts))")
            .replacingOccurrences(of: "{args}", with: ", \(args)")
    }

    override func enumToString(_ node: EnumDef) -> String {
        enums.insert(node.name)
        enumCases[node.name] = node.cases
        let constTmpl = T.enumConst ?? "const (\n{cases}\n)"
        var casesLines: [String] = []
        indentLevel += 1
        for c in node.cases {
            let caseName = T.enumAccess
                .replacingOccurrences(of: "{name}", with: node.name)
                .replacingOccurrences(of: "{key}", with: c)
            casesLines.append(ind() + "\(caseName) = \"\(c)\"")
        }
        indentLevel -= 1
        let casesStr = casesLines.joined(separator: "\n")
        return ind() + constTmpl
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "{cases}", with: casesStr)
    }

    override func tryToString(_ node: TryStmt) -> String {
        var result = ind() + "func() {"
        indentLevel += 1
        if let oopsBody = node.oopsBody {
            result += "\n" + ind() + "defer func() {"
            indentLevel += 1
            result += "\n" + ind() + "if r := recover(); r != nil {"
            indentLevel += 1
            if let varName = node.oopsVar {
                result += "\n" + ind() + "\(varName) := fmt.Sprint(r)"
            }
            result += "\n" + oopsBody.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            result += "\n" + ind() + "}"
            indentLevel -= 1
            result += "\n" + ind() + "}()"
        }
        result += "\n" + node.tryBody.map { stmtToString($0) }.joined(separator: "\n")
        indentLevel -= 1
        result += "\n" + ind() + "}()"
        return result
    }

    override func expr(_ node: ASTNode) -> String {
        if let idx = node as? IndexAccess {
            // Handle enum access
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                if let lit = idx.index as? Literal, let strVal = lit.value as? String {
                    return T.enumAccess
                        .replacingOccurrences(of: "{name}", with: varRef.name)
                        .replacingOccurrences(of: "{key}", with: strVal)
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
        if let randomExpr = node as? RandomExpr {
            needsRandom = true
            if let tmpl = T.random {
                return tmpl
                    .replacingOccurrences(of: "{min}", with: expr(randomExpr.min))
                    .replacingOccurrences(of: "{max}", with: expr(randomExpr.max))
            }
            return "0"
        }
        if let inputExpr = node as? InputExpr {
            if let tmpl = T.input {
                return tmpl.replacingOccurrences(of: "{prompt}", with: expr(inputExpr.prompt))
            }
            return "\"\""
        }
        if let mc = node as? MethodCallExpr, mc.args.count >= 1 {
            needsStrings = true
            let s = expr(mc.args[0])
            switch mc.method {
            case "upper": return "strings.ToUpper(\(s))"
            case "lower": return "strings.ToLower(\(s))"
            case "length": return "len(\(s))"
            case "trim": return "strings.TrimSpace(\(s))"
            case "contains" where mc.args.count >= 2: return "strings.Contains(\(s), \(expr(mc.args[1])))"
            case "replace" where mc.args.count >= 3: return "strings.ReplaceAll(\(s), \(expr(mc.args[1])), \(expr(mc.args[2])))"
            case "split" where mc.args.count >= 2: return "strings.Split(\(s), \(expr(mc.args[1])))"
            case "substring" where mc.args.count >= 3: return "\(s)[\(expr(mc.args[1])):\(expr(mc.args[2]))]"
            default: return s
            }
        }
        return super.expr(node)
    }
}
