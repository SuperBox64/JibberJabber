/// JibJab Objective-C Transpiler - Converts JJ to Objective-C
/// Uses shared C-family base from CFamilyTranspiler.swift

public class ObjCTranspiler: CFamilyTranspiler {
    public override init(target: String = "objc") { super.init(target: target) }

    override func loopToString(_ node: LoopStmt) -> String {
        intVars.insert(node.var)
        return super.loopToString(node)
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
            if let tmpl = T.printfInterp {
                return ind() + tmpl
                    .replacingOccurrences(of: "{fmt}", with: fmt)
                    .replacingOccurrences(of: "{args}", with: argStr)
            }
            return ind() + "printf(\"\(fmt)\\n\"\(argStr));"
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
            // Print whole array
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
            if intVars.contains(varRef.name) {
                return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
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
            return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        if e is ArrayLiteral {
            return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
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
                let elemExpr = selectorExpr("\(varRef.name)[\(expr(idx.index))]", meta.elemType)
                return ind() + printTemplateForType(meta.elemType).replacingOccurrences(of: "{expr}", with: elemExpr)
            }
            // Nested array element: matrix[0][1]
            if let innerIdx = idx.array as? IndexAccess,
               let varRef = innerIdx.array as? VarRef,
               let meta = arrayMeta[varRef.name], meta.isNested {
                let elemExpr = selectorExpr("\(varRef.name)[\(expr(innerIdx.index))][\(expr(idx.index))]", meta.innerElemType)
                return ind() + printTemplateForType(meta.innerElemType).replacingOccurrences(of: "{expr}", with: elemExpr)
            }
            // Dict or tuple access
            if let resolved = resolveAccess(idx) {
                let (cVar, typ) = resolved
                return ind() + printTemplateForType(typ).replacingOccurrences(of: "{expr}", with: cVar)
            }
            return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        if isFloatExpr(e) {
            return ind() + T.printFloat.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
    }

    override func printWholeArray(_ name: String) -> String {
        guard let meta = arrayMeta[name] else {
            return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: name)
        }
        let idxType = T.loopIndexType
        if meta.isNested {
            var lines: [String] = []
            lines.append(ind() + printfInline("["))
            lines.append(ind() + "for (\(idxType) _i = 0; _i < [\(name) count]; _i++) {")
            lines.append(ind() + "    if (_i > 0) " + printfInline(", "))
            let arrType = T.arrayType ?? "NSArray *"
            lines.append(ind() + "    \(arrType)_row = \(name)[_i];")
            lines.append(ind() + "    " + printfInline("["))
            lines.append(ind() + "    for (\(idxType) _j = 0; _j < [_row count]; _j++) {")
            lines.append(ind() + "        if (_j > 0) " + printfInline(", "))
            let fmt = fmtSpecifier(meta.innerElemType)
            let sel = selectorExpr("_row[_j]", meta.innerElemType)
            lines.append(ind() + "        " + printfInlineArgs(fmt, sel))
            lines.append(ind() + "    }")
            lines.append(ind() + "    " + printfInline("]"))
            lines.append(ind() + "}")
            lines.append(ind() + printfInterpStr("]"))
            return lines.joined(separator: "\n")
        }
        var lines: [String] = []
        lines.append(ind() + printfInline("["))
        lines.append(ind() + "for (\(idxType) _i = 0; _i < [\(name) count]; _i++) {")
        lines.append(ind() + "    if (_i > 0) " + printfInline(", "))
        let fmt = fmtSpecifier(meta.elemType)
        let sel = selectorExpr("\(name)[_i]", meta.elemType)
        lines.append(ind() + "    " + printfInlineArgs(fmt, sel))
        lines.append(ind() + "}")
        lines.append(ind() + printfInterpStr("]"))
        return lines.joined(separator: "\n")
    }

    override func varArrayToString(_ node: VarDecl, _ arr: ArrayLiteral) -> String {
        let arrType = T.arrayType ?? "NSArray *"
        return ind() + "\(arrType)\(node.name) = \(expr(node.value));"
    }

    override func exprArray(_ node: ArrayLiteral) -> String {
        let elements = node.elements.map { elem -> String in
            if let lit = elem as? Literal, lit.value is String {
                return boxStr(expr(elem))
            } else if elem is ArrayLiteral {
                return expr(elem)
            } else {
                return boxVal(expr(elem))
            }
        }.joined(separator: ", ")
        return "\(T.arrayLitOpen)\(elements)\(T.arrayLitClose)"
    }

    override func exprDict(_ node: DictLiteral) -> String {
        func boxDictValue(_ v: ASTNode) -> String {
            if let lit = v as? Literal, lit.value is String {
                return boxStr(expr(v))
            } else if v is ArrayLiteral {
                return expr(v)
            } else {
                return boxVal(expr(v))
            }
        }
        let pairs = node.pairs.map { "\(boxStr(expr($0.0))): \(boxDictValue($0.1))" }.joined(separator: ", ")
        return "\(T.dictLitOpen)\(pairs)\(T.dictLitClose)"
    }

    override func exprTuple(_ node: TupleLiteral) -> String {
        let elements = node.elements.map { elem -> String in
            if let lit = elem as? Literal, lit.value is String {
                return boxStr(expr(elem))
            } else {
                return boxVal(expr(elem))
            }
        }.joined(separator: ", ")
        return "\(T.arrayLitOpen)\(elements)\(T.arrayLitClose)"
    }

    // MARK: - ObjC helpers

    /// Box a string expression (e.g. @"hello")
    private func boxStr(_ expr: String) -> String {
        if let tmpl = T.boxString {
            return tmpl.replacingOccurrences(of: "{expr}", with: expr)
        }
        return "@\(expr)"
    }

    /// Box a value expression (e.g. @(42))
    private func boxVal(_ expr: String) -> String {
        if let tmpl = T.boxValue {
            return tmpl.replacingOccurrences(of: "{expr}", with: expr)
        }
        return "@(\(expr))"
    }

    /// Apply selector access for a given type (e.g. [expr UTF8String])
    private func selectorExpr(_ expr: String, _ type: String) -> String {
        let selector: String?
        switch type {
        case "str": selector = T.strSelector
        case "double": selector = T.doubleSelector
        default: selector = T.intSelector
        }
        guard let sel = selector, let tmpl = T.selectorAccess else { return expr }
        return tmpl
            .replacingOccurrences(of: "{expr}", with: expr)
            .replacingOccurrences(of: "{selector}", with: sel)
    }
}
