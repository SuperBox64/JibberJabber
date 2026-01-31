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
            // Enum variable - print name via names array
            if let enumName = enumVarTypes[varRef.name] {
                return ind() + "printf(\"%s\\n\", \(enumName)_names[\(varRef.name)]);"
            }
            // Full enum - print dict representation
            if enums.contains(varRef.name) {
                return ind() + "printf(\"%s\\n\", \"\(enumDictString(varRef.name))\");"
            }
            // Print whole array
            if arrayVars.contains(varRef.name) {
                return printWholeArray(varRef.name)
            }
            if doubleVars.contains(varRef.name) {
                return ind() + "printf(\"%f\\n\", \(expr(e)));"
            }
            if intVars.contains(varRef.name) {
                return ind() + "printf(\"%ld\\n\", (long)\(expr(e)));"
            }
            // Print whole dict
            if dictVars.contains(varRef.name) {
                if let fields = dictFields[varRef.name], fields.isEmpty {
                    return ind() + "printf(\"{}\\n\");"
                }
                return ind() + "printf(\"%s\\n\", \"\(varRef.name)\");"
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
                    return ind() + "printf(\"%s\\n\", \"\(strVal)\");"
                }
            }
            // Array element access
            if let varRef = idx.array as? VarRef, let meta = arrayMeta[varRef.name], !meta.isNested {
                if meta.elemType == "str" {
                    return ind() + "printf(\"%s\\n\", [\(varRef.name)[\(expr(idx.index))] UTF8String]);"
                } else if meta.elemType == "double" {
                    return ind() + "printf(\"%g\\n\", [\(varRef.name)[\(expr(idx.index))] doubleValue]);"
                } else {
                    return ind() + "printf(\"%d\\n\", [\(varRef.name)[\(expr(idx.index))] intValue]);"
                }
            }
            // Nested array element: matrix[0][1]
            if let innerIdx = idx.array as? IndexAccess,
               let varRef = innerIdx.array as? VarRef,
               let meta = arrayMeta[varRef.name], meta.isNested {
                if meta.innerElemType == "str" {
                    return ind() + "printf(\"%s\\n\", [\(varRef.name)[\(expr(innerIdx.index))][\(expr(idx.index))] UTF8String]);"
                } else if meta.innerElemType == "double" {
                    return ind() + "printf(\"%g\\n\", [\(varRef.name)[\(expr(innerIdx.index))][\(expr(idx.index))] doubleValue]);"
                } else {
                    return ind() + "printf(\"%d\\n\", [\(varRef.name)[\(expr(innerIdx.index))][\(expr(idx.index))] intValue]);"
                }
            }
            // Dict or tuple access
            if let resolved = resolveAccess(idx) {
                let (cVar, typ) = resolved
                if typ == "str" {
                    return ind() + "printf(\"%s\\n\", \(cVar));"
                } else if typ == "double" {
                    return ind() + "printf(\"%g\\n\", \(cVar));"
                } else {
                    return ind() + "printf(\"%d\\n\", \(cVar));"
                }
            }
            return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        if isFloatExpr(e) {
            return ind() + "printf(\"%f\\n\", \(expr(e)));"
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

    override func varDictToString(_ node: VarDecl) -> String {
        guard let dict = node.value as? DictLiteral else { return "" }
        var lines: [String] = []
        dictFields[node.name] = [:]
        if dict.pairs.isEmpty {
            return ind() + "// empty dict \(node.name)"
        }
        for (k, v) in dict.pairs {
            if let kLit = k as? Literal, let key = kLit.value as? String {
                let cVar = "\(node.name)_\(key)"
                if let vLit = v as? Literal {
                    if let strVal = vLit.value as? String {
                        lines.append(ind() + "const char* \(cVar) = \"\(strVal)\";")
                        dictFields[node.name, default: [:]][key] = (cVar, "str")
                    } else if let boolVal = vLit.value as? Bool {
                        let val = boolVal ? 1 : 0
                        lines.append(ind() + "int \(cVar) = \(val);")
                        dictFields[node.name, default: [:]][key] = (cVar, "int")
                    } else if let intVal = vLit.value as? Int {
                        lines.append(ind() + "int \(cVar) = \(intVal);")
                        dictFields[node.name, default: [:]][key] = (cVar, "int")
                    } else if let doubleVal = vLit.value as? Double {
                        lines.append(ind() + "double \(cVar) = \(doubleVal);")
                        dictFields[node.name, default: [:]][key] = (cVar, "double")
                    }
                } else if let arrVal = v as? ArrayLiteral {
                    if !arrVal.elements.isEmpty {
                        let first = arrVal.elements[0]
                        let elemType: String
                        if let lit = first as? Literal, lit.value is String {
                            elemType = "const char*"
                        } else {
                            let jjType = inferType(first)
                            elemType = jjType == "Double" ? "double" : "int"
                        }
                        let elements = arrVal.elements.map { expr($0) }.joined(separator: ", ")
                        lines.append(ind() + "\(elemType) \(cVar)[] = {\(elements)};")
                        dictFields[node.name, default: [:]][key] = (cVar, "array")
                    } else {
                        lines.append(ind() + "int \(cVar)[] = {};")
                        dictFields[node.name, default: [:]][key] = (cVar, "array")
                    }
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    override func varTupleToString(_ node: VarDecl, _ tuple: TupleLiteral) -> String {
        var lines: [String] = []
        tupleFields[node.name] = []
        if tuple.elements.isEmpty {
            return ind() + "// empty tuple \(node.name)"
        }
        for (i, e) in tuple.elements.enumerated() {
            let cVar = "\(node.name)_\(i)"
            if let lit = e as? Literal {
                if let strVal = lit.value as? String {
                    lines.append(ind() + "const char* \(cVar) = \"\(strVal)\";")
                    tupleFields[node.name]?.append((cVar, "str"))
                } else if let boolVal = lit.value as? Bool {
                    let val = boolVal ? 1 : 0
                    lines.append(ind() + "int \(cVar) = \(val);")
                    tupleFields[node.name]?.append((cVar, "int"))
                } else if let intVal = lit.value as? Int {
                    lines.append(ind() + "int \(cVar) = \(intVal);")
                    tupleFields[node.name]?.append((cVar, "int"))
                } else if let doubleVal = lit.value as? Double {
                    lines.append(ind() + "double \(cVar) = \(doubleVal);")
                    tupleFields[node.name]?.append((cVar, "double"))
                }
            } else {
                lines.append(ind() + "int \(cVar) = \(expr(e));")
                tupleFields[node.name]?.append((cVar, "int"))
            }
        }
        return lines.joined(separator: "\n")
    }

    func printWholeTuple(_ name: String) -> String {
        guard let fields = tupleFields[name], !fields.isEmpty else {
            return ind() + "printf(\"()\\n\");"
        }
        var partsFmt: [String] = []
        var partsArgs: [String] = []
        for (cVar, typ) in fields {
            if typ == "str" { partsFmt.append("%s") }
            else if typ == "double" { partsFmt.append("%g") }
            else { partsFmt.append("%d") }
            partsArgs.append(cVar)
        }
        let fmt = "(" + partsFmt.joined(separator: ", ") + ")\\n"
        let args = partsArgs.joined(separator: ", ")
        return ind() + "printf(\"\(fmt)\", \(args));"
    }

    override func expr(_ node: ASTNode) -> String {
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
