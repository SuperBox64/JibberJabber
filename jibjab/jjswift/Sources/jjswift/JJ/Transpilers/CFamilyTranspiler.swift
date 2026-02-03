/// JibJab C-Family Base Transpiler
/// Shared logic for C, C++, Objective-C, and Objective-C++ transpilers.
/// Subclasses override specific methods for target-specific behavior.

public protocol Transpiling {
    func transpile(_ program: Program) -> String
}

public class CFamilyTranspiler: Transpiling {
    var indentLevel = 0
    let T: TargetConfig
    var enums = Set<String>()
    var enumCases: [String: [String]] = [:]
    var enumVarTypes: [String: String] = [:]
    var doubleVars = Set<String>()
    var intVars = Set<String>()
    var dictVars = Set<String>()
    var tupleVars = Set<String>()
    var arrayVars = Set<String>()
    var stringVars = Set<String>()
    var boolVars = Set<String>()
    var dictFields: [String: [String: (String, String)]] = [:]
    var tupleFields: [String: [(String, String)]] = [:]
    var foundationDicts = Set<String>()
    var foundationTuples = Set<String>()

    struct ArrayMeta {
        let elemType: String      // "int", "str", "double"
        let count: Int
        let isNested: Bool
        let innerCount: Int       // only for nested
        let innerElemType: String // only for nested
    }
    var arrayMeta: [String: ArrayMeta] = [:]

    public init(target: String) {
        T = loadTarget(target)
    }

    func inferType(_ node: ASTNode) -> String {
        if let literal = node as? Literal {
            if literal.value is Bool { return "Bool" }
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
        if jjType == "String" { return expandedStringType() }
        return T.types?[jjType] ?? "int"
    }

    // --- Helpers for consolidated dict/tuple expansion ---

    /// String type for expanded dict/tuple string fields (ObjC uses const char* instead of NSString *)
    func expandedStringType() -> String {
        return T.expandStringType
    }

    /// Bool type and value for expanded dict/tuple fields
    func boolExpandType() -> String {
        return T.expandBoolAsInt ? "int" : "bool"
    }

    func boolExpandValue(_ val: Bool) -> String {
        if T.expandBoolAsInt {
            return val ? "1" : "0"
        }
        return val ? T.true : T.false
    }

    /// Build a variable declaration for expanded dict/tuple fields
    func expandedVarDecl(name: String, targetType: String, value: String) -> String {
        if let short = T.varShort {
            return ind() + short
                .replacingOccurrences(of: "{name}", with: name)
                .replacingOccurrences(of: "{value}", with: value)
        }
        return ind() + T.var
            .replacingOccurrences(of: "{type}", with: targetType)
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{value}", with: value)
    }

    /// Build an array declaration for dict fields containing arrays
    func expandedArrayDecl(name: String, arr: ArrayLiteral) -> String {
        if let short = T.varShort {
            // Go style: name := []type{elements}
            if !arr.elements.isEmpty {
                let first = arr.elements[0]
                let elemType: String
                if let lit = first as? Literal, lit.value is String {
                    elemType = T.stringType
                } else {
                    elemType = getTargetType(inferType(first))
                }
                let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
                return ind() + short
                    .replacingOccurrences(of: "{name}", with: name)
                    .replacingOccurrences(of: "{value}", with: "[]\(elemType){\(elements)}")
            }
            return ind() + short
                .replacingOccurrences(of: "{name}", with: name)
                .replacingOccurrences(of: "{value}", with: "[]int{}")
        }
        // C style: type name[] = {elements}
        if !arr.elements.isEmpty {
            let first = arr.elements[0]
            let elemType: String
            if let lit = first as? Literal, lit.value is String {
                elemType = expandedStringType()
            } else {
                elemType = getTargetType(inferType(first))
            }
            let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
            return ind() + "\(elemType) \(name)[] = {\(elements)};"
        }
        return ind() + "\(getTargetType("Int")) \(name)[] = {};"
    }

    /// Format specifier for printf-style targets
    func fmtSpecifier(_ type: String) -> String {
        switch type {
        case "str": return T.strFmt
        case "double": return T.doubleFmt
        case "bool": return T.boolFmt
        default: return T.intFmt
        }
    }

    /// Printf inline (no newline, no args) - e.g. printf("[");
    func printfInline(_ text: String) -> String {
        return T.printfInline
            .replacingOccurrences(of: "{fmt}", with: text)
            .replacingOccurrences(of: "{args}", with: "")
    }

    /// Printf inline with format and args - e.g. printf("%d", x);
    func printfInlineArgs(_ fmt: String, _ args: String) -> String {
        return T.printfInline
            .replacingOccurrences(of: "{fmt}", with: fmt)
            .replacingOccurrences(of: "{args}", with: ", \(args)")
    }

    /// Printf with newline (interp style) - e.g. printf("]\n");
    func printfInterpStr(_ text: String) -> String {
        return T.printfInterp
            .replacingOccurrences(of: "{fmt}", with: text)
            .replacingOccurrences(of: "{args}", with: "")
    }

    /// Print template by resolved type
    func printTemplateForType(_ type: String) -> String {
        switch type {
        case "str": return T.printStr
        case "double": return T.printFloat
        case "bool": return T.printBool
        default: return T.printInt
        }
    }

    /// Log template by resolved type
    func logTemplateForType(_ type: String) -> String {
        switch type {
        case "str": return T.logStr
        case "double": return T.logFloat
        case "bool": return T.logBool
        default: return T.logInt
        }
    }

    func stripOuterParens(_ s: String) -> String {
        if s.hasPrefix("(") && s.hasSuffix(")") {
            return String(s.dropFirst().dropLast())
        }
        return s
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
        guard !mainStmts.isEmpty, let mainTmpl = T.main else { return }
        let tmpl = mainTmpl.replacingOccurrences(of: "\\n", with: "\n")
        // Count nesting depth: { minus } before {body} in template
        if let bodyRange = tmpl.range(of: "{body}") {
            let beforeBody = String(tmpl[tmpl.startIndex..<bodyRange.lowerBound])
            let opens = beforeBody.filter { $0 == "{" }.count
            let closes = beforeBody.filter { $0 == "}" }.count
            indentLevel = max(1, opens - closes)
        } else {
            indentLevel = 1
        }
        let bodyLines = mainStmts.map { stmtToString($0) }
        let body = bodyLines.joined(separator: "\n") + "\n"
        let expanded = tmpl.replacingOccurrences(of: "{body}", with: body)
        lines.append(expanded)
    }

    func ind() -> String {
        return String(repeating: T.indent, count: indentLevel)
    }

    func stmtToString(_ node: ASTNode) -> String {
        if let printStmt = node as? PrintStmt {
            return printStmtToString(printStmt)
        } else if let logStmt = node as? LogStmt {
            return logStmtToString(logStmt)
        } else if let varDecl = node as? VarDecl {
            return varDeclToString(varDecl)
        } else if let constDecl = node as? ConstDecl {
            return constDeclToString(constDecl)
        } else if let loopStmt = node as? LoopStmt {
            return loopToString(loopStmt)
        } else if let ifStmt = node as? IfStmt {
            return ifToString(ifStmt)
        } else if let tryStmt = node as? TryStmt {
            return tryToString(tryStmt)
        } else if let funcDef = node as? FuncDef {
            return funcToString(funcDef)
        } else if let returnStmt = node as? ReturnStmt {
            return ind() + T.return.replacingOccurrences(of: "{value}", with: expr(returnStmt.value))
        } else if let throwStmt = node as? ThrowStmt {
            if let tmpl = T.throwStmt {
                return ind() + tmpl.replacingOccurrences(of: "{value}", with: expr(throwStmt.value))
            }
            return ind() + T.comment + " throw " + expr(throwStmt.value)
        } else if let enumDef = node as? EnumDef {
            return enumToString(enumDef)
        } else if let comment = node as? CommentNode {
            return ind() + T.comment + " " + comment.text
        }
        return ""
    }

    func interpFormatSpecifier(_ name: String) -> String {
        if doubleVars.contains(name) { return T.doubleFmt }
        if stringVars.contains(name) { return T.strFmt }
        if boolVars.contains(name) { return T.boolFmt }
        if enumVarTypes[name] != nil { return T.strFmt }
        return T.intFmt
    }

    /// Extract bool display strings from printBool template (e.g. "true"/"false" from ternary)
    lazy var boolDisplayStrings: (String, String) = {
        let tmpl = T.printBool
        // Match pattern: ? "X" : "Y"
        if let qIdx = tmpl.range(of: "? \""),
           let midIdx = tmpl.range(of: "\" : \"", range: qIdx.upperBound..<tmpl.endIndex),
           let endIdx = tmpl.range(of: "\"", range: midIdx.upperBound..<tmpl.endIndex) {
            let trueVal = String(tmpl[qIdx.upperBound..<midIdx.lowerBound])
            let falseVal = String(tmpl[midIdx.upperBound..<endIdx.lowerBound])
            return (trueVal, falseVal)
        }
        return ("true", "false")
    }()

    func interpVarExpr(_ name: String) -> String {
        if let enumName = enumVarTypes[name] {
            return "\(enumName)_names[\(name)]"
        }
        if boolVars.contains(name) {
            let (trueStr, falseStr) = boolDisplayStrings
            return "\(name) ? \"\(trueStr)\" : \"\(falseStr)\""
        }
        return name
    }

    func printStmtToString(_ node: PrintStmt) -> String {
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
            // Enum variable - print name via names array
            if let enumName = enumVarTypes[varRef.name] {
                return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: "\(enumName)_names[\(varRef.name)]")
            }
            // Full enum - print dict representation
            if enums.contains(varRef.name) {
                return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: "\"\(enumDictString(varRef.name))\"")
            }
            // Whole array
            if arrayVars.contains(varRef.name) {
                return printWholeArray(varRef.name)
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
            // Whole dict
            if dictVars.contains(varRef.name) {
                if let fields = dictFields[varRef.name], fields.isEmpty {
                    return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: "\"{}\"")
                }
                return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: "\"\(varRef.name)\"")
            }
            // Whole tuple
            if tupleVars.contains(varRef.name) {
                return printWholeTuple(varRef.name)
            }
        }
        if let idx = e as? IndexAccess {
            // Enum access - print case name as string
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                if let lit = idx.index as? Literal, let strVal = lit.value as? String {
                    return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: "\"\(strVal)\"")
                }
            }
            // Array element access
            if let varRef = idx.array as? VarRef, let meta = arrayMeta[varRef.name], !meta.isNested {
                return ind() + printTemplateForType(meta.elemType).replacingOccurrences(of: "{expr}", with: expr(e))
            }
            // Nested array element: matrix[0][1]
            if let innerIdx = idx.array as? IndexAccess,
               let varRef = innerIdx.array as? VarRef,
               let meta = arrayMeta[varRef.name], meta.isNested {
                return ind() + printTemplateForType(meta.innerElemType).replacingOccurrences(of: "{expr}", with: expr(e))
            }
            // Dict or tuple access
            if let resolved = resolveAccess(idx) {
                let (cVar, typ) = resolved
                return ind() + printTemplateForType(typ).replacingOccurrences(of: "{expr}", with: cVar)
            }
        }
        if isFloatExpr(e) {
            return ind() + T.printFloat.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
    }

    func logStmtToString(_ node: LogStmt) -> String {
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
            return ind() + T.logfInterp
                .replacingOccurrences(of: "{fmt}", with: fmt)
                .replacingOccurrences(of: "{args}", with: argStr)
        }
        if let lit = e as? Literal, lit.value is String {
            return ind() + T.logStr.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        if let varRef = e as? VarRef {
            if let enumName = enumVarTypes[varRef.name] {
                return ind() + T.logStr.replacingOccurrences(of: "{expr}", with: "\(enumName)_names[\(varRef.name)]")
            }
            if enums.contains(varRef.name) {
                return ind() + T.logStr.replacingOccurrences(of: "{expr}", with: "\"\(enumDictString(varRef.name))\"")
            }
            if doubleVars.contains(varRef.name) {
                return ind() + T.logFloat.replacingOccurrences(of: "{expr}", with: expr(e))
            }
            if stringVars.contains(varRef.name) {
                return ind() + T.logStr.replacingOccurrences(of: "{expr}", with: expr(e))
            }
            if boolVars.contains(varRef.name) {
                return ind() + T.logBool.replacingOccurrences(of: "{expr}", with: expr(e))
            }
            if dictVars.contains(varRef.name) {
                return ind() + T.logStr.replacingOccurrences(of: "{expr}", with: "\"\(varRef.name)\"")
            }
            if tupleVars.contains(varRef.name) {
                return ind() + T.logStr.replacingOccurrences(of: "{expr}", with: "\"\(varRef.name)\"")
            }
        }
        if let idx = e as? IndexAccess {
            if let resolved = resolveAccess(idx) {
                let (cVar, typ) = resolved
                return ind() + logTemplateForType(typ).replacingOccurrences(of: "{expr}", with: cVar)
            }
        }
        if isFloatExpr(e) {
            return ind() + T.logFloat.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        return ind() + T.logInt.replacingOccurrences(of: "{expr}", with: expr(e))
    }

    func printWholeArray(_ name: String) -> String {
        guard let meta = arrayMeta[name] else {
            return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: name)
        }
        if meta.isNested {
            var lines: [String] = []
            lines.append(ind() + printfInline("["))
            for i in 0..<meta.count {
                if i > 0 { lines.append(ind() + printfInline(", ")) }
                lines.append(ind() + printfInline("["))
                for j in 0..<meta.innerCount {
                    let fmt = fmtSpecifier(meta.innerElemType)
                    if j > 0 { lines.append(ind() + printfInline(", ")) }
                    lines.append(ind() + printfInlineArgs(fmt, "\(name)[\(i)][\(j)]"))
                }
                lines.append(ind() + printfInline("]"))
            }
            lines.append(ind() + printfInterpStr("]"))
            return lines.joined(separator: "\n")
        }
        let fmt = fmtSpecifier(meta.elemType)
        var lines: [String] = []
        lines.append(ind() + printfInline("["))
        lines.append(ind() + "for (int _i = 0; _i < \(meta.count); _i++) {")
        lines.append(ind() + "    if (_i > 0) " + printfInline(", "))
        lines.append(ind() + "    " + printfInlineArgs(fmt, "\(name)[_i]"))
        lines.append(ind() + "}")
        lines.append(ind() + printfInterpStr("]"))
        return lines.joined(separator: "\n")
    }

    func printWholeTuple(_ name: String) -> String {
        guard let fields = tupleFields[name], !fields.isEmpty else {
            return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: "\"()\"")
        }
        var partsFmt: [String] = []
        var partsArgs: [String] = []
        for (cVar, typ) in fields {
            partsFmt.append(fmtSpecifier(typ))
            partsArgs.append(cVar)
        }
        let fmtStr = "(" + partsFmt.joined(separator: ", ") + ")"
        let args = partsArgs.joined(separator: ", ")
        return ind() + T.printfInterp
            .replacingOccurrences(of: "{fmt}", with: fmtStr)
            .replacingOccurrences(of: "{args}", with: ", \(args)")
    }

    func constDeclToString(_ node: ConstDecl) -> String {
        // Constants are simpler - no arrays/dicts/tuples, just simple values
        let inferredType = inferType(node.value)
        if inferredType == "Bool" { boolVars.insert(node.name) }
        else if inferredType == "Int" { intVars.insert(node.name) }
        else if inferredType == "Double" { doubleVars.insert(node.name) }
        else if inferredType == "String" { stringVars.insert(node.name) }
        let varType = getTargetType(inferredType)
        // For C-family strings that are already const char*, don't double-const
        // Use var template instead to avoid "const const char*"
        let template = varType.hasPrefix("const ") ? T.var : T.const
        return ind() + template
            .replacingOccurrences(of: "{type}", with: varType)
            .replacingOccurrences(of: "{name}", with: node.name)
            .replacingOccurrences(of: "{value}", with: expr(node.value))
    }

    func varDeclToString(_ node: VarDecl) -> String {
        if let arr = node.value as? ArrayLiteral {
            arrayVars.insert(node.name)
            if let inner = arr.elements.first as? ArrayLiteral {
                let jjType = inner.elements.first.map { inferType($0) } ?? "Int"
                let iType = jjType == "String" ? "str" : (jjType == "Double" ? "double" : "int")
                arrayMeta[node.name] = ArrayMeta(elemType: "nested", count: arr.elements.count, isNested: true, innerCount: inner.elements.count, innerElemType: iType)
            } else {
                let jjType = arr.elements.first.map { inferType($0) } ?? "Int"
                let eType = jjType == "String" ? "str" : (jjType == "Double" ? "double" : "int")
                arrayMeta[node.name] = ArrayMeta(elemType: eType, count: arr.elements.count, isNested: false, innerCount: 0, innerElemType: "")
            }
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
        else if inferredType == "Int" { intVars.insert(node.name) }
        else if inferredType == "Double" { doubleVars.insert(node.name) }
        else if inferredType == "String" { stringVars.insert(node.name) }
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
                elemType = T.stringType
            } else {
                elemType = getTargetType(inferType(firstElem))
            }
            let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
            return ind() + "\(elemType) \(node.name)[] = {\(elements)};"
        }
        return ind() + "\(getTargetType("Int")) \(node.name)[] = {};"
    }

    func varTupleToString(_ node: VarDecl, _ tuple: TupleLiteral) -> String {
        var lines: [String] = []
        tupleFields[node.name] = []
        if tuple.elements.isEmpty {
            return ind() + "\(T.comment) empty tuple \(node.name)"
        }
        for (i, e) in tuple.elements.enumerated() {
            let varName = "\(node.name)_\(i)"
            if let lit = e as? Literal {
                if let strVal = lit.value as? String {
                    lines.append(expandedVarDecl(name: varName, targetType: expandedStringType(), value: "\"\(strVal)\""))
                    tupleFields[node.name]?.append((varName, "str"))
                } else if let boolVal = lit.value as? Bool {
                    lines.append(expandedVarDecl(name: varName, targetType: boolExpandType(), value: boolExpandValue(boolVal)))
                    tupleFields[node.name]?.append((varName, T.expandBoolAsInt ? "int" : "bool"))
                } else if let intVal = lit.value as? Int {
                    lines.append(expandedVarDecl(name: varName, targetType: getTargetType("Int"), value: "\(intVal)"))
                    tupleFields[node.name]?.append((varName, "int"))
                } else if let doubleVal = lit.value as? Double {
                    lines.append(expandedVarDecl(name: varName, targetType: getTargetType("Double"), value: "\(doubleVal)"))
                    tupleFields[node.name]?.append((varName, "double"))
                }
            } else {
                lines.append(expandedVarDecl(name: varName, targetType: getTargetType("Int"), value: expr(e)))
                tupleFields[node.name]?.append((varName, "int"))
            }
        }
        return lines.joined(separator: "\n")
    }

    func varDictToString(_ node: VarDecl) -> String {
        guard let dict = node.value as? DictLiteral else { return "" }
        var lines: [String] = []
        dictFields[node.name] = [:]
        if dict.pairs.isEmpty {
            return ind() + "\(T.comment) empty dict \(node.name)"
        }
        for (k, v) in dict.pairs {
            guard let kLit = k as? Literal, let key = kLit.value as? String else { continue }
            let varName = "\(node.name)_\(key)"
            if let vLit = v as? Literal {
                if let strVal = vLit.value as? String {
                    lines.append(expandedVarDecl(name: varName, targetType: expandedStringType(), value: "\"\(strVal)\""))
                    dictFields[node.name, default: [:]][key] = (varName, "str")
                } else if let boolVal = vLit.value as? Bool {
                    lines.append(expandedVarDecl(name: varName, targetType: boolExpandType(), value: boolExpandValue(boolVal)))
                    dictFields[node.name, default: [:]][key] = (varName, T.expandBoolAsInt ? "int" : "bool")
                } else if let intVal = vLit.value as? Int {
                    lines.append(expandedVarDecl(name: varName, targetType: getTargetType("Int"), value: "\(intVal)"))
                    dictFields[node.name, default: [:]][key] = (varName, "int")
                } else if let doubleVal = vLit.value as? Double {
                    lines.append(expandedVarDecl(name: varName, targetType: getTargetType("Double"), value: "\(doubleVal)"))
                    dictFields[node.name, default: [:]][key] = (varName, "double")
                }
            } else if let arrVal = v as? ArrayLiteral {
                lines.append(expandedArrayDecl(name: varName, arr: arrVal))
                dictFields[node.name, default: [:]][key] = (varName, "array")
            }
        }
        return lines.joined(separator: "\n")
    }

    func loopToString(_ node: LoopStmt) -> String {
        var header: String
        if let start = node.start, let end = node.end {
            header = ind() + T.forRange
                .replacingOccurrences(of: "{var}", with: node.var)
                .replacingOccurrences(of: "{start}", with: expr(start))
                .replacingOccurrences(of: "{end}", with: expr(end))
        } else if let condition = node.condition {
            header = ind() + T.while.replacingOccurrences(of: "{condition}", with: stripOuterParens(expr(condition)))
        } else {
            header = ind() + "\(T.comment) unsupported loop"
        }
        indentLevel += 1
        let body = node.body.map { stmtToString($0) }.joined(separator: "\n")
        indentLevel -= 1
        return "\(header)\n\(body)\n\(ind())\(T.blockEnd)"
    }

    func ifToString(_ node: IfStmt) -> String {
        let header = ind() + T.if.replacingOccurrences(of: "{condition}", with: stripOuterParens(expr(node.condition)))
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

    func tryToString(_ node: TryStmt) -> String {
        let header = ind() + T.tryBlock
        indentLevel += 1
        let tryBody = node.tryBody.map { stmtToString($0) }.joined(separator: "\n")
        indentLevel -= 1
        var result = "\(header)\n\(tryBody)\n\(ind())\(T.blockEnd)"
        if let oopsBody = node.oopsBody {
            // Use catchVar template when oopsVar is set, otherwise use catch
            var catchTemplate = T.catchBlock
            if let varName = node.oopsVar, let cv = T.catchVar {
                catchTemplate = cv.replacingOccurrences(of: "{var}", with: varName)
            }
            // Handle multi-line catch templates (e.g. Go's "}()\ndefer func() {")
            let catchLines = catchTemplate.components(separatedBy: "\n")
            let indentedCatch = catchLines.enumerated().map { i, line in
                i == 0 ? line : ind() + line
            }.joined(separator: "\n")
            result = String(result.dropLast(T.blockEnd.count)) + indentedCatch
            indentLevel += 1
            // Insert catchVarBind as first line if needed
            if let varName = node.oopsVar, let bind = T.catchVarBind {
                result += "\n" + ind() + bind.replacingOccurrences(of: "{var}", with: varName)
                stringVars.insert(varName)
            }
            result += "\n" + oopsBody.map { stmtToString($0) }.joined(separator: "\n")
            indentLevel -= 1
            let endBlock = T.blockEndTry ?? T.blockEnd
            result += "\n\(ind())\(endBlock)"
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
        enumCases[node.name] = node.cases
        let cases = node.cases.joined(separator: ", ")
        let result: String
        if let tmpl = T.enumTemplate {
            result = ind() + tmpl.replacingOccurrences(of: "{name}", with: node.name)
                               .replacingOccurrences(of: "{cases}", with: cases)
        } else {
            result = ind() + T.var.replacingOccurrences(of: "{type}", with: "enum")
                .replacingOccurrences(of: "{name}", with: node.name)
                .replacingOccurrences(of: "{value}", with: "{ \(cases) }")
        }
        let namesList = node.cases.map { "\"\($0)\"" }.joined(separator: ", ")
        return result + "\n" + ind() + "\(T.expandStringType) \(node.name)_names[] = {\(namesList)};"
    }

    func enumDictString(_ enumName: String) -> String {
        guard let cases = enumCases[enumName] else { return enumName }
        let pairs = cases.map { "\\\"\($0)\\\": \($0)" }.joined(separator: ", ")
        return "{\(pairs)}"
    }

    func resolveAccess(_ node: IndexAccess) -> (String, String)? {
        // Direct dict access: person["name"]
        if let varRef = node.array as? VarRef, let fields = dictFields[varRef.name] {
            if let lit = node.index as? Literal, let key = lit.value as? String {
                if let result = fields[key] { return result }
            }
        }
        // Direct tuple access: point[0]
        if let varRef = node.array as? VarRef, let fields = tupleFields[varRef.name] {
            if let lit = node.index as? Literal, let idx = lit.value as? Int {
                if idx < fields.count { return fields[idx] }
            }
        }
        // Nested: data["items"][0]
        if let innerIdx = node.array as? IndexAccess {
            if let parent = resolveAccess(innerIdx) {
                let (cVar, typ) = parent
                if typ == "array", let lit = node.index as? Literal, let idx = lit.value as? Int {
                    return ("\(cVar)[\(idx)]", "int")
                }
            }
        }
        return nil
    }

    /// Check if an IndexAccess is rooted in a Foundation collection (NSDictionary/NSArray)
    func isFoundationCollectionAccess(_ node: IndexAccess) -> Bool {
        if let varRef = node.array as? VarRef {
            return foundationDicts.contains(varRef.name) || foundationTuples.contains(varRef.name)
        }
        if let inner = node.array as? IndexAccess {
            return isFoundationCollectionAccess(inner)
        }
        return false
    }

    func expr(_ node: ASTNode) -> String {
        if let idx = node as? IndexAccess {
            if let resolved = resolveAccess(idx) { return resolved.0 }
        }
        if let interp = node as? StringInterpolation {
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
            // Expression context: best-effort format string
            if args.isEmpty { return "\"\(fmt)\"" }
            return "/* sprintf: */ \"\(fmt)\""
        }
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
                    return T.enumAccess
                        .replacingOccurrences(of: "{name}", with: varRef.name)
                        .replacingOccurrences(of: "{key}", with: strVal)
                }
            }
            return "\(expr(idx.array))[\(expr(idx.index))]"
        } else if let binaryOp = node as? BinaryOp {
            if binaryOp.op == "%" && (isFloatExpr(binaryOp.left) || isFloatExpr(binaryOp.right)),
               let fm = T.floatMod {
                return fm.replacingOccurrences(of: "{left}", with: expr(binaryOp.left))
                         .replacingOccurrences(of: "{right}", with: expr(binaryOp.right))
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
