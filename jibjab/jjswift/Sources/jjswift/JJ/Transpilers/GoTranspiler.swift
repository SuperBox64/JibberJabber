/// JibJab Go Transpiler - Converts JJ to Go
/// Uses shared C-family base from CFamilyTranspiler.swift
///
/// Dictionaries: expanded to individual variables (person_name, person_age, etc.)
/// Tuples: stored as numbered variables (_0, _1, _2)

public class GoTranspiler: CFamilyTranspiler {
    var needsMath = false

    public override init(target: String = "go") { super.init(target: target) }

    public override func transpile(_ program: Program) -> String {
        var lines: [String] = []

        let funcs = program.statements.compactMap { $0 as? FuncDef }
        let mainStmts = program.statements.filter { !($0 is FuncDef) }

        // First pass: generate function bodies and main to detect math import need
        var funcLines: [String] = []
        for f in funcs {
            funcLines.append(funcDefToString(f))
            funcLines.append("")
        }

        var mainLines: [String] = []
        if !mainStmts.isEmpty {
            mainLines.append("func main() {")
            indentLevel = 1
            for s in mainStmts { mainLines.append(stmtToString(s)) }
            mainLines.append("}")
        }

        // Build header with correct imports
        lines.append("// Transpiled from JibJab")
        lines.append("package main")
        lines.append("")
        if needsMath {
            lines.append("import (")
            lines.append("    \"fmt\"")
            lines.append("    \"math\"")
            lines.append(")")
        } else {
            lines.append("import \"fmt\"")
        }
        lines.append("")

        // Emit functions
        for fl in funcLines { lines.append(fl) }

        // Emit main
        for ml in mainLines { lines.append(ml) }

        return lines.joined(separator: "\n")
    }

    func funcDefToString(_ node: FuncDef) -> String {
        let params = node.params.map { "\($0) int" }.joined(separator: ", ")
        let header = "func \(node.name)(\(params)) int {"
        indentLevel = 1
        let body = node.body.map { stmtToString($0) }.joined(separator: "\n")
        indentLevel = 0
        return "\(header)\n\(body)\n}"
    }

    override func emitMain(_ lines: inout [String], _ program: Program) {
        // Not used - transpile() handles everything
    }

    override func varDeclToString(_ node: VarDecl) -> String {
        if let arr = node.value as? ArrayLiteral {
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
        let inferredType = inferType(node.value)
        if inferredType == "Int" { intVars.insert(node.name) }
        else if inferredType == "Double" { doubleVars.insert(node.name) }
        return ind() + "\(node.name) := \(expr(node.value))"
    }

    override func varArrayToString(_ node: VarDecl, _ arr: ArrayLiteral) -> String {
        if let firstElem = arr.elements.first {
            if let nestedArr = firstElem as? ArrayLiteral {
                let innerType = nestedArr.elements.first.map { getTargetType(inferType($0)) } ?? "int"
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
        return ind() + "\(node.name) := []int{}"
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
                let goVar = "\(node.name)_\(key)"
                if let vLit = v as? Literal {
                    if let strVal = vLit.value as? String {
                        lines.append(ind() + "\(goVar) := \"\(strVal)\"")
                        dictFields[node.name, default: [:]][key] = (goVar, "str")
                    } else if let boolVal = vLit.value as? Bool {
                        let val = boolVal ? "true" : "false"
                        lines.append(ind() + "\(goVar) := \(val)")
                        dictFields[node.name, default: [:]][key] = (goVar, "bool")
                    } else if let intVal = vLit.value as? Int {
                        lines.append(ind() + "\(goVar) := \(intVal)")
                        dictFields[node.name, default: [:]][key] = (goVar, "int")
                    } else if let doubleVal = vLit.value as? Double {
                        lines.append(ind() + "\(goVar) := \(doubleVal)")
                        dictFields[node.name, default: [:]][key] = (goVar, "double")
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
                        lines.append(ind() + "\(goVar) := []\(elemType){\(elements)}")
                        dictFields[node.name, default: [:]][key] = (goVar, "array")
                    } else {
                        lines.append(ind() + "\(goVar) := []int{}")
                        dictFields[node.name, default: [:]][key] = (goVar, "array")
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
            let goVar = "\(node.name)_\(i)"
            if let lit = e as? Literal {
                if let strVal = lit.value as? String {
                    lines.append(ind() + "\(goVar) := \"\(strVal)\"")
                    tupleFields[node.name]?.append((goVar, "str"))
                } else if let boolVal = lit.value as? Bool {
                    let val = boolVal ? "true" : "false"
                    lines.append(ind() + "\(goVar) := \(val)")
                    tupleFields[node.name]?.append((goVar, "bool"))
                } else if let intVal = lit.value as? Int {
                    lines.append(ind() + "\(goVar) := \(intVal)")
                    tupleFields[node.name]?.append((goVar, "int"))
                } else if let doubleVal = lit.value as? Double {
                    lines.append(ind() + "\(goVar) := \(doubleVal)")
                    tupleFields[node.name]?.append((goVar, "double"))
                }
            } else {
                lines.append(ind() + "\(goVar) := \(expr(e))")
                tupleFields[node.name]?.append((goVar, "int"))
            }
        }
        return lines.joined(separator: "\n")
    }

    override func printStmtToString(_ node: PrintStmt) -> String {
        let e = node.expr
        if let lit = e as? Literal, lit.value is String {
            return ind() + "fmt.Println(\(expr(e)))"
        }
        if let varRef = e as? VarRef {
            if enums.contains(varRef.name) {
                return ind() + "fmt.Println(\"enum \(varRef.name)\")"
            }
            if doubleVars.contains(varRef.name) {
                return ind() + "fmt.Println(\(expr(e)))"
            }
            // Print whole dict
            if dictVars.contains(varRef.name) {
                if let fields = dictFields[varRef.name], fields.isEmpty {
                    return ind() + "fmt.Println(\"{}\")"
                }
                return ind() + "fmt.Println(\"\(varRef.name)\")"
            }
            // Print whole tuple
            if tupleVars.contains(varRef.name) {
                return printWholeTuple(varRef.name)
            }
        }
        if let idx = e as? IndexAccess {
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                return ind() + "fmt.Println(\(expr(e)))"
            }
            // Dict or tuple access
            if let resolved = resolveAccess(idx) {
                let (goVar, _) = resolved
                return ind() + "fmt.Println(\(goVar))"
            }
        }
        if isFloatExpr(e) {
            return ind() + "fmt.Println(\(expr(e)))"
        }
        return ind() + "fmt.Println(\(expr(e)))"
    }

    func printWholeTuple(_ name: String) -> String {
        guard let fields = tupleFields[name], !fields.isEmpty else {
            return ind() + "fmt.Println(\"()\")"
        }
        let fmts = fields.map { _ in "%v" }.joined(separator: ", ")
        let args = fields.map { $0.0 }.joined(separator: ", ")
        return ind() + "fmt.Printf(\"(\(fmts))\\n\", \(args))"
    }

    override func enumToString(_ node: EnumDef) -> String {
        enums.insert(node.name)
        var lines: [String] = []
        lines.append(ind() + "const (")
        indentLevel += 1
        for (i, c) in node.cases.enumerated() {
            if i == 0 {
                lines.append(ind() + "\(node.name)_\(c) = iota")
            } else {
                lines.append(ind() + "\(node.name)_\(c)")
            }
        }
        indentLevel -= 1
        lines.append(ind() + ")")
        return lines.joined(separator: "\n")
    }

    override func expr(_ node: ASTNode) -> String {
        if let idx = node as? IndexAccess {
            // Handle enum access
            if let varRef = idx.array as? VarRef, enums.contains(varRef.name) {
                if let lit = idx.index as? Literal, let strVal = lit.value as? String {
                    return "\(varRef.name)_\(strVal)"
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
        return super.expr(node)
    }
}
