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
                let elemExpr = "[\(varRef.name)[\(expr(idx.index))] \(meta.elemType == "str" ? "UTF8String" : meta.elemType == "double" ? "doubleValue" : "intValue")]"
                return ind() + printTemplateForType(meta.elemType).replacingOccurrences(of: "{expr}", with: elemExpr)
            }
            // Nested array element: matrix[0][1]
            if let innerIdx = idx.array as? IndexAccess,
               let varRef = innerIdx.array as? VarRef,
               let meta = arrayMeta[varRef.name], meta.isNested {
                let elemExpr = "[\(varRef.name)[\(expr(innerIdx.index))][\(expr(idx.index))] \(meta.innerElemType == "str" ? "UTF8String" : meta.innerElemType == "double" ? "doubleValue" : "intValue")]"
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
            return ind() + "NSLog(@\"%@\", \(name));"
        }
        if meta.isNested {
            var lines: [String] = []
            lines.append(ind() + "printf(\"[\");")
            lines.append(ind() + "for (NSUInteger _i = 0; _i < [\(name) count]; _i++) {")
            lines.append(ind() + "    if (_i > 0) printf(\", \");")
            lines.append(ind() + "    NSArray *_row = \(name)[_i];")
            lines.append(ind() + "    printf(\"[\");")
            lines.append(ind() + "    for (NSUInteger _j = 0; _j < [_row count]; _j++) {")
            lines.append(ind() + "        if (_j > 0) printf(\", \");")
            if meta.innerElemType == "str" {
                lines.append(ind() + "        printf(\"%s\", [_row[_j] UTF8String]);")
            } else if meta.innerElemType == "double" {
                lines.append(ind() + "        printf(\"%g\", [_row[_j] doubleValue]);")
            } else {
                lines.append(ind() + "        printf(\"%d\", [_row[_j] intValue]);")
            }
            lines.append(ind() + "    }")
            lines.append(ind() + "    printf(\"]\");")
            lines.append(ind() + "}")
            lines.append(ind() + "printf(\"]\\n\");")
            return lines.joined(separator: "\n")
        }
        var lines: [String] = []
        lines.append(ind() + "printf(\"[\");")
        lines.append(ind() + "for (NSUInteger _i = 0; _i < [\(name) count]; _i++) {")
        lines.append(ind() + "    if (_i > 0) printf(\", \");")
        if meta.elemType == "str" {
            lines.append(ind() + "    printf(\"%s\", [\(name)[_i] UTF8String]);")
        } else if meta.elemType == "double" {
            lines.append(ind() + "    printf(\"%g\", [\(name)[_i] doubleValue]);")
        } else {
            lines.append(ind() + "    printf(\"%d\", [\(name)[_i] intValue]);")
        }
        lines.append(ind() + "}")
        lines.append(ind() + "printf(\"]\\n\");")
        return lines.joined(separator: "\n")
    }

    override func varArrayToString(_ node: VarDecl, _ arr: ArrayLiteral) -> String {
        return ind() + "NSArray *\(node.name) = \(expr(node.value));"
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
