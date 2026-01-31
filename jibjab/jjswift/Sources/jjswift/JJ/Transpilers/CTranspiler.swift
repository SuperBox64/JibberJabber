/// JibJab C Transpiler - Converts JJ to C
/// Uses shared C-family base from CFamilyTranspiler.swift
///
/// Dictionaries: expanded to individual variables (person_name, person_age, etc.)
/// Tuples: stored as numbered variables (_0, _1, _2)

public class CTranspiler: CFamilyTranspiler {
    public override init(target: String = "c") { super.init(target: target) }

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
                        lines.append(ind() + "\(T.stringType) \(cVar) = \"\(strVal)\";")
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
                            elemType = T.stringType
                        } else {
                            elemType = getTargetType(inferType(first))
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
                    lines.append(ind() + "\(T.stringType) \(cVar) = \"\(strVal)\";")
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

    override func printStmtToString(_ node: PrintStmt) -> String {
        let e = node.expr
        if let lit = e as? Literal, lit.value is String {
            return ind() + T.printStr.replacingOccurrences(of: "{expr}", with: expr(e))
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
                return ind() + T.printFloat.replacingOccurrences(of: "{expr}", with: expr(e))
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
                let fmt = meta.elemType == "str" ? "%s" : (meta.elemType == "double" ? "%g" : "%d")
                return ind() + "printf(\"\(fmt)\\n\", \(expr(e)));"
            }
            // Nested array element: matrix[0][1]
            if let innerIdx = idx.array as? IndexAccess,
               let varRef = innerIdx.array as? VarRef,
               let meta = arrayMeta[varRef.name], meta.isNested {
                let fmt = meta.innerElemType == "str" ? "%s" : (meta.innerElemType == "double" ? "%g" : "%d")
                return ind() + "printf(\"\(fmt)\\n\", \(expr(e)));"
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
        }
        if isFloatExpr(e) {
            return ind() + T.printFloat.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
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

}
