/// JibJab Objective-C++ Transpiler - Converts JJ to Objective-C++
/// Blends: C++ output (cout), ObjC collections (Foundation), C++ enums (enum class)

public class ObjCppTranspiler: ObjCTranspiler {
    public override init(target: String = "objcpp") { super.init(target: target) }

    // MARK: - C++ style bools (override ObjC's BOOL/YES/NO)

    override func boolExpandType() -> String { "bool" }
    override func boolExpandValue(_ val: Bool) -> String { val ? "true" : "false" }

    // MARK: - Print overrides using cout

    override func printStmtToString(_ node: PrintStmt) -> String {
        let e = node.expr
        if let interp = e as? StringInterpolation {
            // Use cout for interpolation
            var parts: [String] = []
            for part in interp.parts {
                switch part {
                case .literal(let text): parts.append("\"\(escapeString(text))\"")
                case .variable(let name):
                    if let enumName = enumVarTypes[name] {
                        parts.append("\(enumName)_names[static_cast<int>(\(name))]")
                    } else if boolVars.contains(name) {
                        let (trueStr, falseStr) = boolDisplayStrings
                        parts.append("(\(name) ? \"\(trueStr)\" : \"\(falseStr)\")")
                    } else {
                        parts.append(name)
                    }
                }
            }
            let sep = T.coutSep
            let expr = T.coutExpr.replacingOccurrences(of: "{expr}", with: parts.joined(separator: sep))
            return ind() + expr + T.coutEndl
        }
        if let lit = e as? Literal, lit.value is String {
            return ind() + coutLine(expr(e))
        }
        if let varRef = e as? VarRef {
            if let enumName = enumVarTypes[varRef.name] {
                return ind() + coutLine("\(enumName)_names[static_cast<int>(\(varRef.name))]")
            }
            if enums.contains(varRef.name) {
                return ind() + coutLine("\"\(enumDictString(varRef.name))\"")
            }
            if arrayVars.contains(varRef.name) {
                return printWholeArray(varRef.name)
            }
            if dictVars.contains(varRef.name) {
                if let fields = dictFields[varRef.name], fields.isEmpty {
                    return ind() + coutLine("\"{}\"")
                }
                return ind() + coutLine("\"\(varRef.name)\"")
            }
            if tupleVars.contains(varRef.name) {
                return printWholeTuple(varRef.name)
            }
            if doubleVars.contains(varRef.name) {
                return ind() + coutLine(expr(e))
            }
            if stringVars.contains(varRef.name) {
                return ind() + coutLine(selectorExpr(expr(e), "str"))
            }
            if boolVars.contains(varRef.name) {
                return ind() + coutLine("(\(varRef.name) ? \"true\" : \"false\")")
            }
            if intVars.contains(varRef.name) {
                return ind() + coutLine(expr(e))
            }
            return ind() + coutLine(expr(e))
        }
        if e is ArrayLiteral {
            return ind() + coutLine(expr(e))
        }
        if let idx = e as? IndexAccess {
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                if let lit = idx.index as? Literal, let strVal = lit.value as? String {
                    return ind() + coutLine("\"\(strVal)\"")
                }
            }
            // Array element access
            if let varRef = idx.array as? VarRef, let meta = arrayMeta[varRef.name], !meta.isNested {
                let elemExpr = selectorExpr("\(varRef.name)[\(expr(idx.index))]", meta.elemType)
                return ind() + coutLine(elemExpr)
            }
            // Nested array element
            if let innerIdx = idx.array as? IndexAccess,
               let varRef = innerIdx.array as? VarRef,
               let meta = arrayMeta[varRef.name], meta.isNested {
                let elemExpr = selectorExpr("\(varRef.name)[\(expr(innerIdx.index))][\(expr(idx.index))]", meta.innerElemType)
                return ind() + coutLine(elemExpr)
            }
            // Dict or tuple access (only apply selector for str - NSString* fields)
            if let resolved = resolveAccess(idx) {
                let (cVar, typ) = resolved
                let printExpr = typ == "str" ? selectorExpr(cVar, typ) : cVar
                return ind() + coutLine(printExpr)
            }
            return ind() + coutLine(expr(e))
        }
        if isFloatExpr(e) {
            return ind() + coutLine(expr(e))
        }
        return ind() + coutLine(expr(e))
    }

    override func printWholeArray(_ name: String) -> String {
        guard let meta = arrayMeta[name] else {
            return ind() + coutLine(name)
        }
        let idxType = T.loopIndexType
        if meta.isNested {
            var lines: [String] = []
            lines.append(ind() + coutStr("["))
            lines.append(ind() + "for (\(idxType) _i = 0; _i < [\(name) count]; _i++) {")
            lines.append(ind() + "    if (_i > 0) " + coutStr(", "))
            let arrType = T.arrayType ?? "NSArray *"
            lines.append(ind() + "    \(arrType)_row = \(name)[_i];")
            lines.append(ind() + "    " + coutStr("["))
            lines.append(ind() + "    for (\(idxType) _j = 0; _j < [_row count]; _j++) {")
            lines.append(ind() + "        if (_j > 0) " + coutStr(", "))
            let sel = selectorExpr("_row[_j]", meta.innerElemType)
            lines.append(ind() + "        " + coutStr(sel, quoted: false))
            lines.append(ind() + "    }")
            lines.append(ind() + "    " + coutStr("]"))
            lines.append(ind() + "}")
            lines.append(ind() + coutLineStr("]"))
            return lines.joined(separator: "\n")
        }
        var lines: [String] = []
        lines.append(ind() + coutStr("["))
        lines.append(ind() + "for (\(idxType) _i = 0; _i < [\(name) count]; _i++) {")
        lines.append(ind() + "    if (_i > 0) " + coutStr(", "))
        let sel = selectorExpr("\(name)[_i]", meta.elemType)
        lines.append(ind() + "    " + coutStr(sel, quoted: false))
        lines.append(ind() + "}")
        lines.append(ind() + coutLineStr("]"))
        return lines.joined(separator: "\n")
    }

    override func printWholeTuple(_ name: String) -> String {
        guard let fields = tupleFields[name], !fields.isEmpty else {
            return ind() + coutLine("\"()\"")
        }
        var parts: [String] = []
        for (i, (cppVar, typ)) in fields.enumerated() {
            if i == 0 { parts.append("\"(\"") }
            // Only apply selector for str type (NSString* fields)
            parts.append(typ == "str" ? selectorExpr(cppVar, typ) : cppVar)
            if i < fields.count - 1 { parts.append("\", \"") }
        }
        parts.append("\")\"")
        let coutExprStr = T.coutExpr.replacingOccurrences(of: "{expr}", with: parts.joined(separator: T.coutSep))
        return ind() + coutExprStr + T.coutEndl
    }

    // MARK: - Enum class overrides

    override func enumToString(_ node: EnumDef) -> String {
        enums.insert(node.name)
        enumCases[node.name] = node.cases
        let cases = node.cases.joined(separator: ", ")
        let result: String
        if let tmpl = T.enumTemplate {
            result = ind() + tmpl.replacingOccurrences(of: "{name}", with: node.name)
                               .replacingOccurrences(of: "{cases}", with: cases)
        } else {
            result = ind() + "enum class \(node.name) { \(cases) };"
        }
        let namesList = node.cases.map { "\"\($0)\"" }.joined(separator: ", ")
        return result + "\n" + ind() + "const char* \(node.name)_names[] = {\(namesList)};"
    }

    override func interpVarExpr(_ name: String) -> String {
        if let enumName = enumVarTypes[name] {
            return "\(enumName)_names[static_cast<int>(\(name))]"
        }
        return super.interpVarExpr(name)
    }

    // MARK: - Cout helpers

    private func coutLine(_ expr: String) -> String {
        return T.coutNewline.replacingOccurrences(of: "{expr}", with: expr)
    }

    private func coutStr(_ text: String, quoted: Bool = true) -> String {
        let val = quoted ? "\"\(text)\"" : text
        return T.coutInline.replacingOccurrences(of: "{expr}", with: val)
    }

    private func coutLineStr(_ text: String) -> String {
        return coutLine("\"\(text)\"")
    }
}
