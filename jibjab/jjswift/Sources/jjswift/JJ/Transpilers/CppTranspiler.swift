/// JibJab C++ Transpiler - Converts JJ to C++
/// Uses shared C-family base from CFamilyTranspiler.swift
///
/// Dictionaries: expanded to individual variables (person_name, person_age, etc.)
/// Tuples: stored as numbered variables (_0, _1, _2) with cout for printing

public class CppTranspiler: CFamilyTranspiler {
    var dictFields: [String: [String: (String, String)]] = [:]  // dict_name -> {key: (cpp_var, type)}
    var tupleFields: [String: [(String, String)]] = [:]          // tuple_name -> [(cpp_var, type)]

    public override init(target: String = "cpp") { super.init(target: target) }

    public override func transpile(_ program: Program) -> String {
        var code = super.transpile(program)
        // Add <string> include if any string fields are used
        var needsString = false
        for (_, fields) in dictFields {
            for (_, info) in fields {
                if info.1 == "str" { needsString = true }
            }
        }
        for (_, fields) in tupleFields {
            for (_, typ) in fields {
                if typ == "str" { needsString = true }
            }
        }
        if needsString {
            var lines = code.components(separatedBy: "\n")
            var insertIdx = 0
            for (i, line) in lines.enumerated() {
                if line.hasPrefix("#include") { insertIdx = i + 1 }
            }
            let inc = "#include <string>"
            if !lines.contains(inc) {
                lines.insert(inc, at: insertIdx)
            }
            code = lines.joined(separator: "\n")
        }
        return code
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
                let cppVar = "\(node.name)_\(key)"
                if let vLit = v as? Literal {
                    if let strVal = vLit.value as? String {
                        lines.append(ind() + "std::string \(cppVar) = \"\(strVal)\";")
                        dictFields[node.name, default: [:]][key] = (cppVar, "str")
                    } else if let boolVal = vLit.value as? Bool {
                        let val = boolVal ? "true" : "false"
                        lines.append(ind() + "bool \(cppVar) = \(val);")
                        dictFields[node.name, default: [:]][key] = (cppVar, "bool")
                    } else if let intVal = vLit.value as? Int {
                        lines.append(ind() + "int \(cppVar) = \(intVal);")
                        dictFields[node.name, default: [:]][key] = (cppVar, "int")
                    } else if let doubleVal = vLit.value as? Double {
                        lines.append(ind() + "double \(cppVar) = \(doubleVal);")
                        dictFields[node.name, default: [:]][key] = (cppVar, "double")
                    }
                } else if let arrVal = v as? ArrayLiteral {
                    if !arrVal.elements.isEmpty {
                        let first = arrVal.elements[0]
                        let elemType: String
                        if let lit = first as? Literal, lit.value is String {
                            elemType = "std::string"
                        } else {
                            elemType = getTargetType(inferType(first))
                        }
                        let elements = arrVal.elements.map { expr($0) }.joined(separator: ", ")
                        lines.append(ind() + "\(elemType) \(cppVar)[] = {\(elements)};")
                        dictFields[node.name, default: [:]][key] = (cppVar, "array")
                    } else {
                        lines.append(ind() + "int \(cppVar)[] = {};")
                        dictFields[node.name, default: [:]][key] = (cppVar, "array")
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
            let cppVar = "\(node.name)_\(i)"
            if let lit = e as? Literal {
                if let strVal = lit.value as? String {
                    lines.append(ind() + "std::string \(cppVar) = \"\(strVal)\";")
                    tupleFields[node.name]?.append((cppVar, "str"))
                } else if let boolVal = lit.value as? Bool {
                    let val = boolVal ? "true" : "false"
                    lines.append(ind() + "bool \(cppVar) = \(val);")
                    tupleFields[node.name]?.append((cppVar, "bool"))
                } else if let intVal = lit.value as? Int {
                    lines.append(ind() + "int \(cppVar) = \(intVal);")
                    tupleFields[node.name]?.append((cppVar, "int"))
                } else if let doubleVal = lit.value as? Double {
                    lines.append(ind() + "double \(cppVar) = \(doubleVal);")
                    tupleFields[node.name]?.append((cppVar, "double"))
                }
            } else {
                lines.append(ind() + "int \(cppVar) = \(expr(e));")
                tupleFields[node.name]?.append((cppVar, "int"))
            }
        }
        return lines.joined(separator: "\n")
    }

    override func printStmtToString(_ node: PrintStmt) -> String {
        let e = node.expr
        if let lit = e as? Literal, lit.value is String {
            return ind() + "std::cout << \(expr(e)) << std::endl;"
        }
        if let varRef = e as? VarRef {
            if enums.contains(varRef.name) {
                return ind() + "std::cout << \"enum \(varRef.name)\" << std::endl;"
            }
            if doubleVars.contains(varRef.name) {
                return ind() + T.printFloat.replacingOccurrences(of: "{expr}", with: expr(e))
            }
            // Print whole dict
            if dictVars.contains(varRef.name) {
                if let fields = dictFields[varRef.name], fields.isEmpty {
                    return ind() + "std::cout << \"{}\" << std::endl;"
                }
                return ind() + "std::cout << \"\(varRef.name)\" << std::endl;"
            }
            // Print whole tuple
            if tupleVars.contains(varRef.name) {
                return printWholeTuple(varRef.name)
            }
        }
        if let idx = e as? IndexAccess {
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                return ind() + "std::cout << \(expr(e)) << std::endl;"
            }
            // Dict or tuple access
            if let resolved = resolveAccess(idx) {
                let (cppVar, _) = resolved
                return ind() + "std::cout << \(cppVar) << std::endl;"
            }
        }
        if isFloatExpr(e) {
            return ind() + T.printFloat.replacingOccurrences(of: "{expr}", with: expr(e))
        }
        return ind() + T.printInt.replacingOccurrences(of: "{expr}", with: expr(e))
    }

    func printWholeTuple(_ name: String) -> String {
        guard let fields = tupleFields[name], !fields.isEmpty else {
            return ind() + "std::cout << \"()\" << std::endl;"
        }
        var parts: [String] = []
        for (i, (cppVar, _)) in fields.enumerated() {
            if i == 0 { parts.append("\"(\"") }
            parts.append(cppVar)
            if i < fields.count - 1 { parts.append("\", \"") }
        }
        parts.append("\")\"")
        return ind() + "std::cout << \(parts.joined(separator: " << ")) << std::endl;"
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
                let (cppVar, typ) = parent
                if typ == "array", let lit = node.index as? Literal, let idx = lit.value as? Int {
                    return ("\(cppVar)[\(idx)]", "int")
                }
            }
        }
        return nil
    }

    override func expr(_ node: ASTNode) -> String {
        if let idx = node as? IndexAccess {
            if let resolved = resolveAccess(idx) { return resolved.0 }
        }
        return super.expr(node)
    }
}
