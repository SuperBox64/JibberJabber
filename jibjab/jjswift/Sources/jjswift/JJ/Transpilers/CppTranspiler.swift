/// JibJab C++ Transpiler - Converts JJ to C++
/// Overrides: transpile (string/vector includes), arrays (std::vector), enums (enum class), print (cout)

public class CppTranspiler: CFamilyTranspiler {
    public override init(target: String = "cpp") { super.init(target: target) }

    public override func transpile(_ program: Program) -> String {
        var code = super.transpile(program)
        var needsString = false
        var needsVector = false
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
        if !arrayVars.isEmpty { needsVector = true }
        if needsString || needsVector {
            var lines = code.components(separatedBy: "\n")
            var insertIdx = 0
            for (i, line) in lines.enumerated() {
                if line.hasPrefix("#include") { insertIdx = i + 1 }
            }
            if needsVector {
                let vecInc = "#include <vector>"
                if !lines.contains(vecInc) {
                    lines.insert(vecInc, at: insertIdx)
                    insertIdx += 1
                }
            }
            if needsString {
                let strInc = T.stringInclude ?? "#include <string>"
                if !lines.contains(strInc) {
                    lines.insert(strInc, at: insertIdx)
                }
            }
            code = lines.joined(separator: "\n")
        }
        return code
    }

    // MARK: - Vector arrays

    override func varArrayToString(_ node: VarDecl, _ arr: ArrayLiteral) -> String {
        if let firstElem = arr.elements.first {
            if let nestedArr = firstElem as? ArrayLiteral {
                let innerType = nestedArr.elements.first.map { getTargetType(inferType($0)) } ?? "int"
                let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
                return ind() + "std::vector<std::vector<\(innerType)>> \(node.name) = {\(elements)};"
            }
            let elemType: String
            if let lit = firstElem as? Literal, lit.value is String {
                elemType = T.stringType
            } else {
                elemType = getTargetType(inferType(firstElem))
            }
            let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
            return ind() + "std::vector<\(elemType)> \(node.name) = {\(elements)};"
        }
        return ind() + "std::vector<\(getTargetType("Int"))> \(node.name) = {};"
    }

    override func expandedArrayDecl(name: String, arr: ArrayLiteral) -> String {
        if !arr.elements.isEmpty {
            let first = arr.elements[0]
            let elemType: String
            if let lit = first as? Literal, lit.value is String {
                elemType = expandedStringType()
            } else {
                elemType = getTargetType(inferType(first))
            }
            let elements = arr.elements.map { expr($0) }.joined(separator: ", ")
            return ind() + "std::vector<\(elemType)> \(name) = {\(elements)};"
        }
        return ind() + "std::vector<\(getTargetType("Int"))> \(name) = {};"
    }

    // MARK: - Enum class helpers

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
        // Names array uses const char* (not std::string) for C-compatible indexing
        let namesList = node.cases.map { "\"\($0)\"" }.joined(separator: ", ")
        return result + "\n" + ind() + "const char* \(node.name)_names[] = {\(namesList)};"
    }

    override func interpVarExpr(_ name: String) -> String {
        if let enumName = enumVarTypes[name] {
            return "\(enumName)_names[static_cast<int>(\(name))]"
        }
        return super.interpVarExpr(name)
    }

    override func printWholeArray(_ name: String) -> String {
        guard let meta = arrayMeta[name] else {
            return ind() + coutLine(name)
        }
        if meta.isNested {
            var lines: [String] = []
            lines.append(ind() + coutStr("["))
            for i in 0..<meta.count {
                if i > 0 { lines.append(ind() + coutStr(", ")) }
                lines.append(ind() + coutStr("["))
                for j in 0..<meta.innerCount {
                    if j > 0 { lines.append(ind() + coutStr(", ")) }
                    lines.append(ind() + coutStr("\(name)[\(i)][\(j)]", quoted: false))
                }
                lines.append(ind() + coutStr("]"))
            }
            lines.append(ind() + coutLineStr("]"))
            return lines.joined(separator: "\n")
        }
        var lines: [String] = []
        lines.append(ind() + coutStr("["))
        lines.append(ind() + "for (int _i = 0; _i < \(meta.count); _i++) {")
        lines.append(ind() + "    if (_i > 0) " + coutStr(", "))
        lines.append(ind() + "    " + coutStr("\(name)[_i]", quoted: false))
        lines.append(ind() + "}")
        lines.append(ind() + coutLineStr("]"))
        return lines.joined(separator: "\n")
    }

    override func printWholeTuple(_ name: String) -> String {
        guard let fields = tupleFields[name], !fields.isEmpty else {
            return ind() + coutLine("\"()\"")
        }
        var parts: [String] = []
        for (i, (cppVar, _)) in fields.enumerated() {
            if i == 0 { parts.append("\"(\"") }
            parts.append(cppVar)
            if i < fields.count - 1 { parts.append("\", \"") }
        }
        parts.append("\")\"")
        let coutExprStr = T.coutExpr.replacingOccurrences(of: "{expr}", with: parts.joined(separator: T.coutSep))
        return ind() + coutExprStr + T.coutEndl
    }

    // MARK: - Cout helpers

    /// cout with expression and endl
    private func coutLine(_ expr: String) -> String {
        return T.coutNewline.replacingOccurrences(of: "{expr}", with: expr)
    }

    /// cout inline with quoted string literal
    private func coutStr(_ text: String, quoted: Bool = true) -> String {
        let val = quoted ? "\"\(text)\"" : text
        return T.coutInline.replacingOccurrences(of: "{expr}", with: val)
    }

    /// cout with string literal and endl
    private func coutLineStr(_ text: String) -> String {
        return coutLine("\"\(text)\"")
    }

}
