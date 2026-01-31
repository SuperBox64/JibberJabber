/// JibJab C++ Transpiler - Converts JJ to C++
/// Overrides: transpile (string include), printWholeArray/printWholeTuple (cout syntax)

public class CppTranspiler: CFamilyTranspiler {
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
            let inc = T.stringInclude ?? "#include <string>"
            if !lines.contains(inc) {
                lines.insert(inc, at: insertIdx)
            }
            code = lines.joined(separator: "\n")
        }
        return code
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
        let coutExprStr = T.coutExpr?.replacingOccurrences(of: "{expr}", with: parts.joined(separator: T.coutSep))
            ?? "std::cout << \(parts.joined(separator: " << "))"
        return ind() + coutExprStr + T.coutEndl
    }

    // MARK: - Cout helpers

    /// cout with expression and endl
    private func coutLine(_ expr: String) -> String {
        if let tmpl = T.coutNewline {
            return tmpl.replacingOccurrences(of: "{expr}", with: expr)
        }
        return "std::cout << \(expr) << std::endl;"
    }

    /// cout inline with quoted string literal
    private func coutStr(_ text: String, quoted: Bool = true) -> String {
        let val = quoted ? "\"\(text)\"" : text
        if let tmpl = T.coutInline {
            return tmpl.replacingOccurrences(of: "{expr}", with: val)
        }
        return "std::cout << \(val);"
    }

    /// cout with string literal and endl
    private func coutLineStr(_ text: String) -> String {
        return coutLine("\"\(text)\"")
    }

}
