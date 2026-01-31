/// JibJab ARM64 Assembly Transpiler - Converts JJ to ARM64 Assembly (macOS)
/// Uses emit values from common/jj.json

private let OP = JJ.operators

struct ArrayInfo {
    let baseOffset: Int   // Stack offset of first element
    let count: Int        // Number of elements
    let isString: Bool    // String pointers vs int values
}

struct TupleInfo {
    let baseOffset: Int
    let count: Int
    let elemTypes: [TupleElemType]  // Type of each element
}

enum TupleElemType {
    case int
    case string
    case bool
}

struct DictInfo {
    let keys: [String]           // Key names in order
    let valueOffsets: [Int]      // Stack offsets for values
    let valueTypes: [TupleElemType]  // Type of each value
}

public class AssemblyTranspiler: Transpiling {
    private let T = loadTarget("asm")
    public init() {}
    private var asmLines: [String] = []
    private var strings: [(label: String, value: String, addNewline: Bool)] = []
    private var doubles: [(label: String, value: Double)] = []  // Float constants in data section
    private var labelCounter = 0
    private var variables: [String: Int] = [:]
    private var floatVars: Set<String> = []  // Track which variables are floats
    private var stackOffset = 0
    private var functions: [String: FuncDef] = [:]
    private var currentFunc: String? = nil
    private var enums: [String: [String: Int]] = [:]  // Track enum name -> case name -> value
    private var enumCaseStrings: [String: [String]] = [:]  // enum name -> ordered case name strings
    private var enumCaseLabels: [String: [String: String]] = [:]  // enum name -> case name -> string label
    private var arrays: [String: ArrayInfo] = [:]     // Track array variables
    private var tuples: [String: TupleInfo] = [:]     // Track tuple variables
    private var dicts: [String: DictInfo] = [:]       // Track dictionary variables

    public func transpile(_ program: Program) -> String {
        asmLines = []
        strings = []
        doubles = []
        labelCounter = 0
        variables = [:]
        floatVars = []
        stackOffset = 0
        functions = [:]
        arrays = [:]

        // Collect functions first
        for stmt in program.statements {
            if let funcDef = stmt as? FuncDef {
                functions[funcDef.name] = funcDef
            }
        }

        // Header
        asmLines.append("// JibJab -> ARM64 Assembly (macOS)")
        asmLines.append(".global \(T.mainLabel)")
        asmLines.append(".align 4")
        asmLines.append("")

        // Generate function code
        for stmt in program.statements {
            if let funcDef = stmt as? FuncDef {
                genFunc(funcDef)
            }
        }

        // Generate main
        let mainStmts = program.statements.filter { !($0 is FuncDef) }
        asmLines.append("\(T.mainLabel):")
        asmLines.append("    stp x29, x30, [sp, #-16]!")
        asmLines.append("    stp x19, x20, [sp, #-16]!")
        asmLines.append("    stp x21, x22, [sp, #-16]!")
        asmLines.append("    stp x23, x24, [sp, #-16]!")
        asmLines.append("    stp x25, x26, [sp, #-16]!")
        asmLines.append("    stp x27, x28, [sp, #-16]!")
        asmLines.append("    mov x29, sp")

        // Allocate stack for variables (larger for arrays)
        let maxVars = 64
        asmLines.append("    sub sp, sp, #\(maxVars * 8 + 16)")
        stackOffset = 16
        variables = [:]
        arrays = [:]
        tuples = [:]
        dicts = [:]
        floatVars = []
        nestedArrays = [:]

        for stmt in mainStmts {
            genStmt(stmt)
        }

        // Return 0
        asmLines.append("    mov w0, #0")
        asmLines.append("    add sp, sp, #\(maxVars * 8 + 16)")
        asmLines.append("    ldp x27, x28, [sp], #16")
        asmLines.append("    ldp x25, x26, [sp], #16")
        asmLines.append("    ldp x23, x24, [sp], #16")
        asmLines.append("    ldp x21, x22, [sp], #16")
        asmLines.append("    ldp x19, x20, [sp], #16")
        asmLines.append("    ldp x29, x30, [sp], #16")
        asmLines.append("    ret")
        asmLines.append("")

        // Data section
        asmLines.append(".data")
        asmLines.append("\(T.fmtIntLabel):")
        asmLines.append("    .asciz \"\(T.fmtIntStr)\"")
        asmLines.append("\(T.fmtStrLabel):")
        asmLines.append("    .asciz \"\(T.fmtStrStr)\"")
        asmLines.append("\(T.fmtFloatLabel):")
        asmLines.append("    .asciz \"\(T.fmtFloatStr)\"")
        asmLines.append("\(T.boolTrueLabel):")
        asmLines.append("    .asciz \"true\"")
        asmLines.append("\(T.boolFalseLabel):")
        asmLines.append("    .asciz \"false\"")

        for item in strings {
            var escaped = item.value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            if item.addNewline {
                escaped += "\\n"
            }
            asmLines.append("\(item.label):")
            asmLines.append("    .asciz \"\(escaped)\"")
        }

        // Double constants (8-byte aligned)
        if !doubles.isEmpty {
            asmLines.append(".align 3")  // 8-byte alignment for doubles
            for item in doubles {
                asmLines.append("\(item.label):")
                asmLines.append("    .double \(item.value)")
            }
        }

        return asmLines.joined(separator: "\n")
    }

    private func newLabel(prefix: String = "L") -> String {
        labelCounter += 1
        return "_\(prefix)\(labelCounter)"
    }

    private func addString(_ value: String) -> String {
        let label = newLabel(prefix: "str")
        strings.append((label, value, false))
        return label
    }

    private func addStringRaw(_ value: String) -> String {
        let label = newLabel(prefix: "str")
        strings.append((label, value, true))
        return label
    }

    private func addDouble(_ value: Double) -> String {
        let label = newLabel(prefix: "dbl")
        doubles.append((label, value))
        return label
    }

    private func genFunc(_ node: FuncDef) {
        currentFunc = node.name
        asmLines.append("_\(node.name):")
        asmLines.append("    stp x29, x30, [sp, #-16]!")
        asmLines.append("    stp x19, x20, [sp, #-16]!")
        asmLines.append("    stp x21, x22, [sp, #-16]!")
        asmLines.append("    stp x23, x24, [sp, #-16]!")
        asmLines.append("    stp x25, x26, [sp, #-16]!")
        asmLines.append("    stp x27, x28, [sp, #-16]!")
        asmLines.append("    mov x29, sp")

        let maxVars = 64
        asmLines.append("    sub sp, sp, #\(maxVars * 8 + 16)")

        let oldVars = variables
        let oldOffset = stackOffset
        let oldArrays = arrays
        let oldFloatVars = floatVars
        variables = [:]
        stackOffset = 16
        arrays = [:]
        floatVars = []

        // Store parameters
        let paramRegs = ["w0", "w1", "w2", "w3", "w4", "w5", "w6", "w7"]
        for (i, param) in node.params.enumerated() {
            variables[param] = stackOffset
            asmLines.append("    stur \(paramRegs[i]), [x29, #-\(stackOffset + 16)]")
            stackOffset += 8
        }

        for stmt in node.body {
            genStmt(stmt)
        }

        // Default return
        asmLines.append("    mov w0, #0")
        asmLines.append("_\(node.name)_ret:")
        asmLines.append("    add sp, sp, #\(maxVars * 8 + 16)")
        asmLines.append("    ldp x27, x28, [sp], #16")
        asmLines.append("    ldp x25, x26, [sp], #16")
        asmLines.append("    ldp x23, x24, [sp], #16")
        asmLines.append("    ldp x21, x22, [sp], #16")
        asmLines.append("    ldp x19, x20, [sp], #16")
        asmLines.append("    ldp x29, x30, [sp], #16")
        asmLines.append("    ret")
        asmLines.append("")

        variables = oldVars
        stackOffset = oldOffset
        arrays = oldArrays
        floatVars = oldFloatVars
    }

    private func genStmt(_ node: ASTNode) {
        if let printStmt = node as? PrintStmt {
            genPrint(printStmt)
        } else if let varDecl = node as? VarDecl {
            genVarDecl(varDecl)
        } else if let loopStmt = node as? LoopStmt {
            genLoop(loopStmt)
        } else if let ifStmt = node as? IfStmt {
            genIf(ifStmt)
        } else if let returnStmt = node as? ReturnStmt {
            genExpr(returnStmt.value)
            if let funcName = currentFunc {
                asmLines.append("    b _\(funcName)_ret")
            }
        } else if let enumDef = node as? EnumDef {
            // Store enum case values (0, 1, 2, ...)
            var caseValues: [String: Int] = [:]
            var caseLabels: [String: String] = [:]
            for (i, caseName) in enumDef.cases.enumerated() {
                caseValues[caseName] = i
                // Pre-create string labels for each case name
                let label = addString(caseName)
                caseLabels[caseName] = label
            }
            enums[enumDef.name] = caseValues
            enumCaseStrings[enumDef.name] = enumDef.cases
            enumCaseLabels[enumDef.name] = caseLabels
        }
    }

    private func genPrint(_ node: PrintStmt) {
        if let interp = node.expr as? StringInterpolation {
            // Build printf format string and args from interpolation parts
            var fmt = ""
            var varNames: [String] = []
            for part in interp.parts {
                switch part {
                case .literal(let text):
                    fmt += text.replacingOccurrences(of: "%", with: "%%")
                case .variable(let name):
                    if floatVars.contains(name) {
                        fmt += "%g"
                    } else if let offset = variables[name], enumVarLabels[name] != nil {
                        _ = offset // enum var is a string pointer
                        fmt += "%s"
                    } else {
                        fmt += "%d"
                    }
                    varNames.append(name)
                }
            }
            // Create format string with newline
            let fmtLabel = addStringRaw(fmt)
            // Load variable values onto stack before printf
            // ARM64 printf: x0=format, then args go to stack via str
            // For simplicity, build a single printf call with format + one arg at a time
            // Actually, printf supports multiple args. Load them in order.
            if varNames.isEmpty {
                asmLines.append("    adrp x0, \(fmtLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(fmtLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")
            } else {
                // For each variable, load onto stack
                for (i, name) in varNames.enumerated() {
                    if let offset = variables[name] {
                        if floatVars.contains(name) {
                            asmLines.append("    ldur d\(i), [x29, #-\(offset + 16)]")
                            asmLines.append("    str d\(i), [sp, #\(i * 8)]")
                        } else {
                            asmLines.append("    ldur w0, [x29, #-\(offset + 16)]")
                            asmLines.append("    sxtw x0, w0")
                            asmLines.append("    str x0, [sp, #\(i * 8)]")
                        }
                    }
                }
                asmLines.append("    adrp x0, \(fmtLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(fmtLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")
            }
            return
        }
        if let literal = node.expr as? Literal, let str = literal.value as? String {
            let strLabel = addStringRaw(str)
            asmLines.append("    adrp x0, \(strLabel)\(T.pageDirective)")
            asmLines.append("    add x0, x0, \(strLabel)\(T.pageOffDirective)")
            asmLines.append("    bl \(T.printfSymbol)")
        } else if let varRef = node.expr as? VarRef, let _ = enumVarLabels[varRef.name] {
            // Print enum variable by name (stored as string pointer)
            if let offset = variables[varRef.name] {
                asmLines.append("    ldur x0, [x29, #-\(offset + 16)]")
                asmLines.append("    str x0, [sp]")
                asmLines.append("    adrp x0, \(T.fmtStrLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(T.fmtStrLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")
            }
        } else if let idx = node.expr as? IndexAccess,
                  let varRef = idx.array as? VarRef,
                  let _ = enums[varRef.name] {
            // Print enum case access by name: Color["Red"] -> "Red"
            if let lit = idx.index as? Literal, let strVal = lit.value as? String,
               let caseLabels = enumCaseLabels[varRef.name],
               let label = caseLabels[strVal] {
                asmLines.append("    adrp x0, \(label)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(label)\(T.pageOffDirective)")
                asmLines.append("    str x0, [sp]")
                asmLines.append("    adrp x0, \(T.fmtStrLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(T.fmtStrLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")
            }
        } else if let varRef = node.expr as? VarRef, let enumCases = enums[varRef.name] {
            // Print full enum: {"Red": Red, "Green": Green, "Blue": Blue}
            // Build output at runtime from individual case labels
            let caseNames = enumCaseStrings[varRef.name] ?? Array(enumCases.keys)
            guard let caseLabels = enumCaseLabels[varRef.name] else { return }

            // Print opening brace
            let openLabel = addString("{")
            asmLines.append("    adrp x0, \(openLabel)\(T.pageDirective)")
            asmLines.append("    add x0, x0, \(openLabel)\(T.pageOffDirective)")
            asmLines.append("    bl \(T.printfSymbol)")

            for (i, caseName) in caseNames.enumerated() {
                // Print separator between pairs
                if i > 0 {
                    let sepLabel = addString(", ")
                    asmLines.append("    adrp x0, \(sepLabel)\(T.pageDirective)")
                    asmLines.append("    add x0, x0, \(sepLabel)\(T.pageOffDirective)")
                    asmLines.append("    bl \(T.printfSymbol)")
                }
                // Print "caseName": (with quotes around key)
                let keyLabel = addString("\"\(caseName)\": ")
                asmLines.append("    adrp x0, \(keyLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(keyLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")
                // Print case value (the case name string, unquoted)
                if let label = caseLabels[caseName] {
                    asmLines.append("    adrp x0, \(label)\(T.pageDirective)")
                    asmLines.append("    add x0, x0, \(label)\(T.pageOffDirective)")
                    asmLines.append("    str x0, [sp]")
                    let fmtLabel = addString("%s")
                    asmLines.append("    adrp x0, \(fmtLabel)\(T.pageDirective)")
                    asmLines.append("    add x0, x0, \(fmtLabel)\(T.pageOffDirective)")
                    asmLines.append("    bl \(T.printfSymbol)")
                }
            }

            // Print closing brace + newline
            let closeLabel = addStringRaw("}")
            asmLines.append("    adrp x0, \(closeLabel)\(T.pageDirective)")
            asmLines.append("    add x0, x0, \(closeLabel)\(T.pageOffDirective)")
            asmLines.append("    bl \(T.printfSymbol)")
        } else if let varRef = node.expr as? VarRef, let tupleInfo = tuples[varRef.name] {
            // Print full tuple: (elem1, elem2, ...)
            // We print it formatted like the interpreter
            genPrintTupleFull(varRef.name, tupleInfo)
        } else if let idx = node.expr as? IndexAccess,
                  let varRef = idx.array as? VarRef,
                  let tupleInfo = tuples[varRef.name] {
            // Print single tuple element by index
            if let lit = idx.index as? Literal, let intVal = lit.value as? Int {
                let elemOffset = tupleInfo.baseOffset + intVal * 8
                let elemType = tupleInfo.elemTypes[intVal]
                switch elemType {
                case .string:
                    asmLines.append("    ldur x0, [x29, #-\(elemOffset + 16)]")
                    asmLines.append("    str x0, [sp]")
                    asmLines.append("    adrp x0, \(T.fmtStrLabel)\(T.pageDirective)")
                    asmLines.append("    add x0, x0, \(T.fmtStrLabel)\(T.pageOffDirective)")
                    asmLines.append("    bl \(T.printfSymbol)")
                case .int:
                    asmLines.append("    ldur w0, [x29, #-\(elemOffset + 16)]")
                    asmLines.append("    sxtw x0, w0")
                    asmLines.append("    str x0, [sp]")
                    asmLines.append("    adrp x0, \(T.fmtIntLabel)\(T.pageDirective)")
                    asmLines.append("    add x0, x0, \(T.fmtIntLabel)\(T.pageOffDirective)")
                    asmLines.append("    bl \(T.printfSymbol)")
                case .bool:
                    asmLines.append("    ldur x0, [x29, #-\(elemOffset + 16)]")
                    asmLines.append("    str x0, [sp]")
                    asmLines.append("    adrp x0, \(T.fmtStrLabel)\(T.pageDirective)")
                    asmLines.append("    add x0, x0, \(T.fmtStrLabel)\(T.pageOffDirective)")
                    asmLines.append("    bl \(T.printfSymbol)")
                }
            }
        } else if let varRef = node.expr as? VarRef, let dictInfo = dicts[varRef.name] {
            // Print empty dict
            if dictInfo.keys.isEmpty {
                let strLabel = addStringRaw("{}")
                asmLines.append("    adrp x0, \(strLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(strLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")
            } else {
                // Print full dict: {"key": value, ...}
                let openLabel = addString("{")
                asmLines.append("    adrp x0, \(openLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(openLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")

                for (i, key) in dictInfo.keys.enumerated() {
                    if i > 0 {
                        let sepLabel = addString(", ")
                        asmLines.append("    adrp x0, \(sepLabel)\(T.pageDirective)")
                        asmLines.append("    add x0, x0, \(sepLabel)\(T.pageOffDirective)")
                        asmLines.append("    bl \(T.printfSymbol)")
                    }
                    // Print "key":
                    let keyLabel = addString("\"\(key)\": ")
                    asmLines.append("    adrp x0, \(keyLabel)\(T.pageDirective)")
                    asmLines.append("    add x0, x0, \(keyLabel)\(T.pageOffDirective)")
                    asmLines.append("    bl \(T.printfSymbol)")

                    // Check for nested array value (e.g., "items": [1, 2, 3])
                    let syntheticName = "\(varRef.name).\(key)"
                    if let arrInfo = arrays[syntheticName] {
                        // Print array inline: [elem, elem, ...]
                        let arrOpen = addString("[")
                        asmLines.append("    adrp x0, \(arrOpen)\(T.pageDirective)")
                        asmLines.append("    add x0, x0, \(arrOpen)\(T.pageOffDirective)")
                        asmLines.append("    bl \(T.printfSymbol)")
                        for j in 0..<arrInfo.count {
                            if j > 0 {
                                let s = addString(", ")
                                asmLines.append("    adrp x0, \(s)\(T.pageDirective)")
                                asmLines.append("    add x0, x0, \(s)\(T.pageOffDirective)")
                                asmLines.append("    bl \(T.printfSymbol)")
                            }
                            let elemOffset = arrInfo.baseOffset + j * 8
                            if arrInfo.isString {
                                asmLines.append("    ldur x0, [x29, #-\(elemOffset + 16)]")
                                asmLines.append("    str x0, [sp]")
                                let fmt = addString("%s")
                                asmLines.append("    adrp x0, \(fmt)\(T.pageDirective)")
                                asmLines.append("    add x0, x0, \(fmt)\(T.pageOffDirective)")
                                asmLines.append("    bl \(T.printfSymbol)")
                            } else {
                                asmLines.append("    ldur w1, [x29, #-\(elemOffset + 16)]")
                                asmLines.append("    sxtw x1, w1")
                                asmLines.append("    str x1, [sp]")
                                let fmt = addString("%d")
                                asmLines.append("    adrp x0, \(fmt)\(T.pageDirective)")
                                asmLines.append("    add x0, x0, \(fmt)\(T.pageOffDirective)")
                                asmLines.append("    bl \(T.printfSymbol)")
                            }
                        }
                        let arrClose = addString("]")
                        asmLines.append("    adrp x0, \(arrClose)\(T.pageDirective)")
                        asmLines.append("    add x0, x0, \(arrClose)\(T.pageOffDirective)")
                        asmLines.append("    bl \(T.printfSymbol)")
                    } else {
                        // Print scalar value by type
                        let valOffset = dictInfo.valueOffsets[i]
                        let valType = dictInfo.valueTypes[i]
                        switch valType {
                        case .string:
                            asmLines.append("    ldur x0, [x29, #-\(valOffset + 16)]")
                            asmLines.append("    str x0, [sp]")
                            let fmt = addString("%s")
                            asmLines.append("    adrp x0, \(fmt)\(T.pageDirective)")
                            asmLines.append("    add x0, x0, \(fmt)\(T.pageOffDirective)")
                            asmLines.append("    bl \(T.printfSymbol)")
                        case .int:
                            asmLines.append("    ldur w1, [x29, #-\(valOffset + 16)]")
                            asmLines.append("    sxtw x1, w1")
                            asmLines.append("    str x1, [sp]")
                            let fmt = addString("%d")
                            asmLines.append("    adrp x0, \(fmt)\(T.pageDirective)")
                            asmLines.append("    add x0, x0, \(fmt)\(T.pageOffDirective)")
                            asmLines.append("    bl \(T.printfSymbol)")
                        case .bool:
                            asmLines.append("    ldur x0, [x29, #-\(valOffset + 16)]")
                            asmLines.append("    str x0, [sp]")
                            let fmt = addString("%s")
                            asmLines.append("    adrp x0, \(fmt)\(T.pageDirective)")
                            asmLines.append("    add x0, x0, \(fmt)\(T.pageOffDirective)")
                            asmLines.append("    bl \(T.printfSymbol)")
                        }
                    }
                }

                // Print closing brace + newline
                let closeLabel = addStringRaw("}")
                asmLines.append("    adrp x0, \(closeLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(closeLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")
            }
        } else if let idx = node.expr as? IndexAccess,
                  let varRef = idx.array as? VarRef,
                  let dictInfo = dicts[varRef.name] {
            // Dict key access: person["name"]
            if let lit = idx.index as? Literal, let keyStr = lit.value as? String {
                if let keyIdx = dictInfo.keys.firstIndex(of: keyStr) {
                    let valOffset = dictInfo.valueOffsets[keyIdx]
                    let valType = dictInfo.valueTypes[keyIdx]
                    switch valType {
                    case .string:
                        asmLines.append("    ldur x0, [x29, #-\(valOffset + 16)]")
                        asmLines.append("    str x0, [sp]")
                        asmLines.append("    adrp x0, \(T.fmtStrLabel)\(T.pageDirective)")
                        asmLines.append("    add x0, x0, \(T.fmtStrLabel)\(T.pageOffDirective)")
                        asmLines.append("    bl \(T.printfSymbol)")
                    case .int:
                        asmLines.append("    ldur w0, [x29, #-\(valOffset + 16)]")
                        asmLines.append("    sxtw x0, w0")
                        asmLines.append("    str x0, [sp]")
                        asmLines.append("    adrp x0, \(T.fmtIntLabel)\(T.pageDirective)")
                        asmLines.append("    add x0, x0, \(T.fmtIntLabel)\(T.pageOffDirective)")
                        asmLines.append("    bl \(T.printfSymbol)")
                    case .bool:
                        asmLines.append("    ldur x0, [x29, #-\(valOffset + 16)]")
                        asmLines.append("    str x0, [sp]")
                        asmLines.append("    adrp x0, \(T.fmtStrLabel)\(T.pageDirective)")
                        asmLines.append("    add x0, x0, \(T.fmtStrLabel)\(T.pageOffDirective)")
                        asmLines.append("    bl \(T.printfSymbol)")
                    }
                }
            }
        } else if let idx = node.expr as? IndexAccess,
                  let outerIdx = idx.array as? IndexAccess,
                  let varRef = outerIdx.array as? VarRef,
                  let _ = dicts[varRef.name] {
            // Nested dict access: data["items"][0]
            if let keyLit = outerIdx.index as? Literal, let keyStr = keyLit.value as? String {
                let syntheticName = "\(varRef.name).\(keyStr)"
                if let arrInfo = arrays[syntheticName] {
                    genArrayLoad(varRef: VarRef(name: syntheticName), index: idx.index, arrInfo: arrInfo, useX: arrInfo.isString)
                    if arrInfo.isString {
                        asmLines.append("    str x0, [sp]")
                        asmLines.append("    adrp x0, \(T.fmtStrLabel)\(T.pageDirective)")
                        asmLines.append("    add x0, x0, \(T.fmtStrLabel)\(T.pageOffDirective)")
                    } else {
                        asmLines.append("    sxtw x0, w0")
                        asmLines.append("    str x0, [sp]")
                        asmLines.append("    adrp x0, \(T.fmtIntLabel)\(T.pageDirective)")
                        asmLines.append("    add x0, x0, \(T.fmtIntLabel)\(T.pageOffDirective)")
                    }
                    asmLines.append("    bl \(T.printfSymbol)")
                }
            }
        } else if let varRef = node.expr as? VarRef, let arrInfo = arrays[varRef.name] {
            // Print entire array with brackets: [elem, elem, ...]
            if let nested = nestedArrays[varRef.name] {
                // Nested (2D) array: [[1, 2], [3, 4]]
                let openLabel = addString("[")
                asmLines.append("    adrp x0, \(openLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(openLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")

                for outer in 0..<nested.outerCount {
                    if outer > 0 {
                        let sepLabel = addString(", ")
                        asmLines.append("    adrp x0, \(sepLabel)\(T.pageDirective)")
                        asmLines.append("    add x0, x0, \(sepLabel)\(T.pageOffDirective)")
                        asmLines.append("    bl \(T.printfSymbol)")
                    }
                    let innerOpen = addString("[")
                    asmLines.append("    adrp x0, \(innerOpen)\(T.pageDirective)")
                    asmLines.append("    add x0, x0, \(innerOpen)\(T.pageOffDirective)")
                    asmLines.append("    bl \(T.printfSymbol)")

                    for inner in 0..<nested.innerSize {
                        if inner > 0 {
                            let sepLabel = addString(", ")
                            asmLines.append("    adrp x0, \(sepLabel)\(T.pageDirective)")
                            asmLines.append("    add x0, x0, \(sepLabel)\(T.pageOffDirective)")
                            asmLines.append("    bl \(T.printfSymbol)")
                        }
                        let flatIdx = outer * nested.innerSize + inner
                        let elemOffset = arrInfo.baseOffset + flatIdx * 8
                        asmLines.append("    ldur w1, [x29, #-\(elemOffset + 16)]")
                        asmLines.append("    sxtw x1, w1")
                        asmLines.append("    str x1, [sp]")
                        let fmtLabel = addString("%d")
                        asmLines.append("    adrp x0, \(fmtLabel)\(T.pageDirective)")
                        asmLines.append("    add x0, x0, \(fmtLabel)\(T.pageOffDirective)")
                        asmLines.append("    bl \(T.printfSymbol)")
                    }

                    let innerClose = addString("]")
                    asmLines.append("    adrp x0, \(innerClose)\(T.pageDirective)")
                    asmLines.append("    add x0, x0, \(innerClose)\(T.pageOffDirective)")
                    asmLines.append("    bl \(T.printfSymbol)")
                }

                let closeLabel = addStringRaw("]")
                asmLines.append("    adrp x0, \(closeLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(closeLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")
            } else {
                // Flat array: [1, 2, 3]
                let openLabel = addString("[")
                asmLines.append("    adrp x0, \(openLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(openLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")

                for i in 0..<arrInfo.count {
                    if i > 0 {
                        let sepLabel = addString(", ")
                        asmLines.append("    adrp x0, \(sepLabel)\(T.pageDirective)")
                        asmLines.append("    add x0, x0, \(sepLabel)\(T.pageOffDirective)")
                        asmLines.append("    bl \(T.printfSymbol)")
                    }
                    let elemOffset = arrInfo.baseOffset + i * 8
                    if arrInfo.isString {
                        asmLines.append("    ldur x0, [x29, #-\(elemOffset + 16)]")
                        asmLines.append("    str x0, [sp]")
                        let fmtLabel = addString("%s")
                        asmLines.append("    adrp x0, \(fmtLabel)\(T.pageDirective)")
                        asmLines.append("    add x0, x0, \(fmtLabel)\(T.pageOffDirective)")
                        asmLines.append("    bl \(T.printfSymbol)")
                    } else {
                        asmLines.append("    ldur w1, [x29, #-\(elemOffset + 16)]")
                        asmLines.append("    sxtw x1, w1")
                        asmLines.append("    str x1, [sp]")
                        let fmtLabel = addString("%d")
                        asmLines.append("    adrp x0, \(fmtLabel)\(T.pageDirective)")
                        asmLines.append("    add x0, x0, \(fmtLabel)\(T.pageOffDirective)")
                        asmLines.append("    bl \(T.printfSymbol)")
                    }
                }

                let closeLabel = addStringRaw("]")
                asmLines.append("    adrp x0, \(closeLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(closeLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")
            }
        } else if let idx = node.expr as? IndexAccess,
                  let varRef = idx.array as? VarRef,
                  let arrInfo = arrays[varRef.name] {
            // Print single array element
            if arrInfo.isString {
                genArrayLoad(varRef: varRef, index: idx.index, arrInfo: arrInfo, useX: true)
                asmLines.append("    str x0, [sp]")
                asmLines.append("    adrp x0, \(T.fmtStrLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(T.fmtStrLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")
            } else {
                genArrayLoad(varRef: varRef, index: idx.index, arrInfo: arrInfo, useX: false)
                asmLines.append("    sxtw x0, w0")
                asmLines.append("    str x0, [sp]")
                asmLines.append("    adrp x0, \(T.fmtIntLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(T.fmtIntLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")
            }
        } else if isFloatExpr(node.expr) {
            // Float expression — print with %g
            genFloatExpr(node.expr)
            asmLines.append("    str d0, [sp]")
            asmLines.append("    adrp x0, \(T.fmtFloatLabel)\(T.pageDirective)")
            asmLines.append("    add x0, x0, \(T.fmtFloatLabel)\(T.pageOffDirective)")
            asmLines.append("    bl \(T.printfSymbol)")
        } else {
            genExpr(node.expr)
            asmLines.append("    sxtw x0, w0")
            asmLines.append("    str x0, [sp]")
            asmLines.append("    adrp x0, \(T.fmtIntLabel)\(T.pageDirective)")
            asmLines.append("    add x0, x0, \(T.fmtIntLabel)\(T.pageOffDirective)")
            asmLines.append("    bl \(T.printfSymbol)")
        }
    }

    /// Load an array element into w0 (int) or x0 (string pointer)
    private func genArrayLoad(varRef: VarRef, index: ASTNode, arrInfo: ArrayInfo, useX: Bool) {
        if let lit = index as? Literal, let intVal = lit.value as? Int {
            // Literal index: compute offset directly
            let elemOffset = arrInfo.baseOffset + intVal * 8
            if useX {
                asmLines.append("    ldur x0, [x29, #-\(elemOffset + 16)]")
            } else {
                asmLines.append("    ldur w0, [x29, #-\(elemOffset + 16)]")
            }
        } else {
            // Variable index: compute offset at runtime
            // 1. Load the index value into w1
            genExpr(index)
            asmLines.append("    mov w1, w0")
            // 2. Compute byte offset: index * 8
            asmLines.append("    lsl w1, w1, #3")
            // 3. Add base offset
            asmLines.append("    mov w2, #\(arrInfo.baseOffset + 16)")
            asmLines.append("    add w1, w1, w2")
            // 4. Negate and load from [x29, #-offset]
            //    x29 - offset => sub x3, x29, x1 (sign-extended)
            asmLines.append("    sxtw x1, w1")
            asmLines.append("    sub x3, x29, x1")
            if useX {
                asmLines.append("    ldr x0, [x3]")
            } else {
                asmLines.append("    ldr w0, [x3]")
            }
        }
    }

    /// Check if an expression is an enum access like Color["Red"]
    private func isEnumAccess(_ node: ASTNode) -> (enumName: String, caseName: String)? {
        if let idx = node as? IndexAccess,
           let varRef = idx.array as? VarRef,
           let _ = enums[varRef.name],
           let lit = idx.index as? Literal,
           let strVal = lit.value as? String {
            return (varRef.name, strVal)
        }
        return nil
    }

    private func genVarDecl(_ node: VarDecl) {
        // Handle enum variable assignment: store as string pointer
        if let enumAccess = isEnumAccess(node.value) {
            if let caseLabels = enumCaseLabels[enumAccess.enumName],
               let label = caseLabels[enumAccess.caseName] {
                asmLines.append("    adrp x0, \(label)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(label)\(T.pageOffDirective)")
                if variables[node.name] == nil {
                    variables[node.name] = stackOffset
                    stackOffset += 8
                }
                guard let offset = variables[node.name] else { return }
                asmLines.append("    stur x0, [x29, #-\(offset + 16)]")
                // Mark as a string-like variable for printing
                enumVarLabels[node.name] = (enumAccess.enumName, enumAccess.caseName)
                return
            }
        }

        if let tupleLit = node.value as? TupleLiteral {
            genTupleDecl(node.name, tupleLit)
            return
        }

        if let dictLit = node.value as? DictLiteral {
            genDictDecl(node.name, dictLit)
            return
        }

        if let arr = node.value as? ArrayLiteral {
            // Check if this is a nested array (2D)
            let isNested = arr.elements.first is ArrayLiteral
            if isNested {
                // For nested arrays, flatten and store as contiguous memory
                // Track as a special nested array
                let baseOffset = stackOffset
                var totalCount = 0
                var innerSizes: [Int] = []
                for elem in arr.elements {
                    if let innerArr = elem as? ArrayLiteral {
                        innerSizes.append(innerArr.elements.count)
                        for innerElem in innerArr.elements {
                            genExpr(innerElem)
                            asmLines.append("    stur w0, [x29, #-\(stackOffset + 16)]")
                            stackOffset += 8
                            totalCount += 1
                        }
                    }
                }
                // Store array info (flat representation)
                let info = ArrayInfo(baseOffset: baseOffset, count: totalCount, isString: false)
                arrays[node.name] = info
                // Also store inner sizes for nested access
                // We'll use a convention: nestedArrays stores outer count and inner size
                nestedArrays[node.name] = (outerCount: arr.elements.count, innerSize: innerSizes.first ?? 0)
                variables[node.name] = baseOffset
                return
            }

            // Determine if string array
            let isString: Bool
            if let first = arr.elements.first, let lit = first as? Literal, lit.value is String {
                isString = true
            } else {
                isString = false
            }

            let baseOffset = stackOffset

            // Store each element
            for elem in arr.elements {
                if isString {
                    if let lit = elem as? Literal, let str = lit.value as? String {
                        let strLabel = addString(str)
                        asmLines.append("    adrp x0, \(strLabel)\(T.pageDirective)")
                        asmLines.append("    add x0, x0, \(strLabel)\(T.pageOffDirective)")
                        asmLines.append("    stur x0, [x29, #-\(stackOffset + 16)]")
                    }
                } else {
                    genExpr(elem)
                    asmLines.append("    stur w0, [x29, #-\(stackOffset + 16)]")
                }
                stackOffset += 8
            }

            let info = ArrayInfo(baseOffset: baseOffset, count: arr.elements.count, isString: isString)
            arrays[node.name] = info
            variables[node.name] = baseOffset
        } else {
            // Scalar variable — check if float
            let isFloat = isFloatExpr(node.value)
            if isFloat {
                genFloatExpr(node.value)
                if variables[node.name] == nil {
                    variables[node.name] = stackOffset
                    stackOffset += 8
                }
                guard let offset = variables[node.name] else { return }
                floatVars.insert(node.name)
                asmLines.append("    stur d0, [x29, #-\(offset + 16)]")
            } else {
                genExpr(node.value)
                if variables[node.name] == nil {
                    variables[node.name] = stackOffset
                    stackOffset += 8
                }
                guard let offset = variables[node.name] else { return }
                asmLines.append("    stur w0, [x29, #-\(offset + 16)]")
            }
        }
    }

    // Track nested (2D) array dimensions
    private var nestedArrays: [String: (outerCount: Int, innerSize: Int)] = [:]
    // Track enum variable assignments: var name -> (enum name, case name)
    private var enumVarLabels: [String: (String, String)] = [:]

    private func genTupleDecl(_ name: String, _ tupleLit: TupleLiteral) {
        let baseOffset = stackOffset
        var elemTypes: [TupleElemType] = []

        for elem in tupleLit.elements {
            if let lit = elem as? Literal {
                if let str = lit.value as? String {
                    let strLabel = addString(str)
                    asmLines.append("    adrp x0, \(strLabel)\(T.pageDirective)")
                    asmLines.append("    add x0, x0, \(strLabel)\(T.pageOffDirective)")
                    asmLines.append("    stur x0, [x29, #-\(stackOffset + 16)]")
                    elemTypes.append(.string)
                } else if let boolVal = lit.value as? Bool {
                    // Store bool as string "true"/"false" for printing
                    let strLabel = addString(boolVal ? "true" : "false")
                    asmLines.append("    adrp x0, \(strLabel)\(T.pageDirective)")
                    asmLines.append("    add x0, x0, \(strLabel)\(T.pageOffDirective)")
                    asmLines.append("    stur x0, [x29, #-\(stackOffset + 16)]")
                    elemTypes.append(.string)
                } else if lit.value is Int {
                    genExpr(elem)
                    asmLines.append("    stur w0, [x29, #-\(stackOffset + 16)]")
                    elemTypes.append(.int)
                } else {
                    genExpr(elem)
                    asmLines.append("    stur w0, [x29, #-\(stackOffset + 16)]")
                    elemTypes.append(.int)
                }
            } else {
                genExpr(elem)
                asmLines.append("    stur w0, [x29, #-\(stackOffset + 16)]")
                elemTypes.append(.int)
            }
            stackOffset += 8
        }

        let info = TupleInfo(baseOffset: baseOffset, count: tupleLit.elements.count, elemTypes: elemTypes)
        tuples[name] = info
        variables[name] = baseOffset
    }

    private func genPrintTupleFull(_ name: String, _ info: TupleInfo) {
        if info.count == 0 {
            let strLabel = addStringRaw("()")
            asmLines.append("    adrp x0, \(strLabel)\(T.pageDirective)")
            asmLines.append("    add x0, x0, \(strLabel)\(T.pageOffDirective)")
            asmLines.append("    bl \(T.printfSymbol)")
            return
        }

        // Print opening paren (no newline)
        let openLabel = addString("(")
        asmLines.append("    adrp x0, \(openLabel)\(T.pageDirective)")
        asmLines.append("    add x0, x0, \(openLabel)\(T.pageOffDirective)")
        asmLines.append("    bl \(T.printfSymbol)")

        for i in 0..<info.count {
            let elemOffset = info.baseOffset + i * 8
            let elemType = info.elemTypes[i]

            // Print separator
            if i > 0 {
                let sepLabel = addString(", ")
                asmLines.append("    adrp x0, \(sepLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(sepLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")
            }

            // Use %s or %d without newline — we need custom format strings
            switch elemType {
            case .string, .bool:
                asmLines.append("    ldur x0, [x29, #-\(elemOffset + 16)]")
                asmLines.append("    str x0, [sp]")
                let fmtLabel = addString("%s")
                asmLines.append("    adrp x0, \(fmtLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(fmtLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")
            case .int:
                asmLines.append("    ldur w1, [x29, #-\(elemOffset + 16)]")
                asmLines.append("    sxtw x1, w1")
                asmLines.append("    str x1, [sp]")
                let fmtLabel = addString("%d")
                asmLines.append("    adrp x0, \(fmtLabel)\(T.pageDirective)")
                asmLines.append("    add x0, x0, \(fmtLabel)\(T.pageOffDirective)")
                asmLines.append("    bl \(T.printfSymbol)")
            }
        }

        // Print closing paren + newline
        let closeLabel = addStringRaw(")")
        asmLines.append("    adrp x0, \(closeLabel)\(T.pageDirective)")
        asmLines.append("    add x0, x0, \(closeLabel)\(T.pageOffDirective)")
        asmLines.append("    bl \(T.printfSymbol)")
    }

    private func genDictDecl(_ name: String, _ dictLit: DictLiteral) {
        var keys: [String] = []
        var valueOffsets: [Int] = []
        var valueTypes: [TupleElemType] = []

        for pair in dictLit.pairs {
            let keyStr: String
            if let lit = pair.key as? Literal, let s = lit.value as? String {
                keyStr = s
            } else {
                keyStr = "?"
            }
            keys.append(keyStr)

            let valOffset = stackOffset
            valueOffsets.append(valOffset)

            if let lit = pair.value as? Literal {
                if let str = lit.value as? String {
                    let strLabel = addString(str)
                    asmLines.append("    adrp x0, \(strLabel)\(T.pageDirective)")
                    asmLines.append("    add x0, x0, \(strLabel)\(T.pageOffDirective)")
                    asmLines.append("    stur x0, [x29, #-\(valOffset + 16)]")
                    valueTypes.append(.string)
                } else if let boolVal = lit.value as? Bool {
                    let strLabel = addString(boolVal ? "true" : "false")
                    asmLines.append("    adrp x0, \(strLabel)\(T.pageDirective)")
                    asmLines.append("    add x0, x0, \(strLabel)\(T.pageOffDirective)")
                    asmLines.append("    stur x0, [x29, #-\(valOffset + 16)]")
                    valueTypes.append(.string)
                } else if lit.value is Int {
                    genExpr(pair.value)
                    asmLines.append("    stur w0, [x29, #-\(valOffset + 16)]")
                    valueTypes.append(.int)
                } else {
                    genExpr(pair.value)
                    asmLines.append("    stur w0, [x29, #-\(valOffset + 16)]")
                    valueTypes.append(.int)
                }
            } else if let arrLit = pair.value as? ArrayLiteral {
                // Store nested array elements inline and track as array
                let arrBase = stackOffset
                let isStr = arrLit.elements.first.flatMap { ($0 as? Literal)?.value as? String } != nil
                for arrElem in arrLit.elements {
                    if isStr {
                        if let lit = arrElem as? Literal, let s = lit.value as? String {
                            let sl = addString(s)
                            asmLines.append("    adrp x0, \(sl)\(T.pageDirective)")
                            asmLines.append("    add x0, x0, \(sl)\(T.pageOffDirective)")
                            asmLines.append("    stur x0, [x29, #-\(stackOffset + 16)]")
                        }
                    } else {
                        genExpr(arrElem)
                        asmLines.append("    stur w0, [x29, #-\(stackOffset + 16)]")
                    }
                    stackOffset += 8
                }
                let arrInfo = ArrayInfo(baseOffset: arrBase, count: arrLit.elements.count, isString: isStr)
                // Use a synthetic name for the nested array
                arrays["\(name).\(keyStr)"] = arrInfo
                valueTypes.append(.int)  // placeholder
                continue
            } else {
                genExpr(pair.value)
                asmLines.append("    stur w0, [x29, #-\(valOffset + 16)]")
                valueTypes.append(.int)
            }
            stackOffset += 8
        }

        let info = DictInfo(keys: keys, valueOffsets: valueOffsets, valueTypes: valueTypes)
        dicts[name] = info
        variables[name] = valueOffsets.first ?? stackOffset
    }

    private func genLoop(_ node: LoopStmt) {
        guard let start = node.start, let end = node.end else { return }
        let loopStart = newLabel(prefix: "loop")
        let loopEnd = newLabel(prefix: "endloop")

        genExpr(start)
        if variables[node.var] == nil {
            variables[node.var] = stackOffset
            stackOffset += 8
        }
        guard let varOffset = variables[node.var] else { return }
        asmLines.append("    stur w0, [x29, #-\(varOffset + 16)]")

        genExpr(end)
        let endOffset = stackOffset
        stackOffset += 8
        asmLines.append("    stur w0, [x29, #-\(endOffset + 16)]")

        asmLines.append("\(loopStart):")
        asmLines.append("    ldur w0, [x29, #-\(varOffset + 16)]")
        asmLines.append("    ldur w1, [x29, #-\(endOffset + 16)]")
        asmLines.append("    cmp w0, w1")
        asmLines.append("    b.ge \(loopEnd)")

        for stmt in node.body {
            genStmt(stmt)
        }

        asmLines.append("    ldur w0, [x29, #-\(varOffset + 16)]")
        asmLines.append("    add w0, w0, #1")
        asmLines.append("    stur w0, [x29, #-\(varOffset + 16)]")
        asmLines.append("    b \(loopStart)")
        asmLines.append("\(loopEnd):")
    }

    private func genIf(_ node: IfStmt) {
        let elseLabel = newLabel(prefix: "else")
        let endLabel = newLabel(prefix: "endif")

        genCondition(node.condition, falseLabel: elseLabel)

        for stmt in node.thenBody {
            genStmt(stmt)
        }
        if node.elseBody != nil {
            asmLines.append("    b \(endLabel)")
        }

        asmLines.append("\(elseLabel):")

        if let elseBody = node.elseBody {
            for stmt in elseBody {
                genStmt(stmt)
            }
            asmLines.append("\(endLabel):")
        }
    }

    private func genCondition(_ node: ASTNode, falseLabel: String) {
        if let binaryOp = node as? BinaryOp {
            let useFloat = isFloatExpr(binaryOp.left) || isFloatExpr(binaryOp.right)

            if useFloat {
                // Float comparison using fcmp
                genFloatExpr(binaryOp.left)
                asmLines.append("    str d0, [sp, #-16]!")
                genFloatExpr(binaryOp.right)
                asmLines.append("    fmov d1, d0")
                asmLines.append("    ldr d0, [sp], #16")
                asmLines.append("    fcmp d0, d1")

                let floatBranches: [String: String] = [
                    JJ.operators.eq.emit: "b.ne",
                    JJ.operators.neq.emit: "b.eq",
                    JJ.operators.lt.emit: "b.ge",
                    JJ.operators.gt.emit: "b.le",
                    JJ.operators.lte.emit: "b.gt",
                    JJ.operators.gte.emit: "b.lt"
                ]
                if let branch = floatBranches[binaryOp.op] {
                    asmLines.append("    \(branch) \(falseLabel)")
                }
            } else {
                // Integer comparison
                genExpr(binaryOp.left)
                asmLines.append("    mov w9, w0")
                genExpr(binaryOp.right)
                asmLines.append("    cmp w9, w0")

                let branches: [String: String] = [
                    JJ.operators.eq.emit: "b.ne",
                    JJ.operators.neq.emit: "b.eq",
                    JJ.operators.lt.emit: "b.ge",
                    JJ.operators.gt.emit: "b.le",
                    JJ.operators.lte.emit: "b.gt",
                    JJ.operators.gte.emit: "b.lt"
                ]
                if let branch = branches[binaryOp.op] {
                    asmLines.append("    \(branch) \(falseLabel)")
                } else {
                    genExpr(node)
                    asmLines.append("    cmp w0, #0")
                    asmLines.append("    b.eq \(falseLabel)")
                }
            }
        } else {
            genExpr(node)
            asmLines.append("    cmp w0, #0")
            asmLines.append("    b.eq \(falseLabel)")
        }
    }

    private func genExpr(_ node: ASTNode) {
        if let literal = node as? Literal {
            if let int = literal.value as? Int {
                if int >= -65536 && int <= 65535 {
                    asmLines.append("    mov w0, #\(int)")
                } else {
                    asmLines.append("    movz w0, #\(int & 0xFFFF)")
                    if int > 65535 {
                        asmLines.append("    movk w0, #\((int >> 16) & 0xFFFF), lsl #16")
                    }
                }
            } else if let bool = literal.value as? Bool {
                asmLines.append("    mov w0, #\(bool ? 1 : 0)")
            } else {
                asmLines.append("    mov w0, #0")
            }
        } else if let varRef = node as? VarRef {
            if let _ = enumVarLabels[varRef.name], let offset = variables[varRef.name] {
                // Enum variable stored as string pointer — load as x0 for comparison
                asmLines.append("    ldur x0, [x29, #-\(offset + 16)]")
                asmLines.append("    mov w0, w0")  // truncate to w0 for int comparison context
            } else if let offset = variables[varRef.name] {
                asmLines.append("    ldur w0, [x29, #-\(offset + 16)]")
            } else if enums[varRef.name] != nil {
                asmLines.append("    mov w0, #0")
            } else {
                asmLines.append("    mov w0, #0")
            }
        } else if let idx = node as? IndexAccess {
            // Check if this is enum access (e.g., Color["Red"] -> enum value)
            if let varRef = idx.array as? VarRef, let enumCases = enums[varRef.name] {
                if let lit = idx.index as? Literal, let strVal = lit.value as? String {
                    // Load string pointer for comparison (consistent with enum var storage)
                    if let caseLabels = enumCaseLabels[varRef.name],
                       let label = caseLabels[strVal] {
                        asmLines.append("    adrp x0, \(label)\(T.pageDirective)")
                        asmLines.append("    add x0, x0, \(label)\(T.pageOffDirective)")
                        asmLines.append("    mov w0, w0")  // truncate to w0 for comparison
                        return
                    }
                    let value = enumCases[strVal] ?? 0
                    asmLines.append("    mov w0, #\(value)")
                    return
                }
            }
            // Check if this is array access
            if let varRef = idx.array as? VarRef, let arrInfo = arrays[varRef.name] {
                genArrayLoad(varRef: varRef, index: idx.index, arrInfo: arrInfo, useX: arrInfo.isString)
                return
            }
            // Check if this is nested array access: matrix[0][1]
            if let outerIdx = idx.array as? IndexAccess,
               let varRef = outerIdx.array as? VarRef,
               let arrInfo = arrays[varRef.name],
               let nested = nestedArrays[varRef.name] {
                // Compute flat index: outerIndex * innerSize + innerIndex
                if let outerLit = outerIdx.index as? Literal, let outerVal = outerLit.value as? Int,
                   let innerLit = idx.index as? Literal, let innerVal = innerLit.value as? Int {
                    let flatIndex = outerVal * nested.innerSize + innerVal
                    let elemOffset = arrInfo.baseOffset + flatIndex * 8
                    asmLines.append("    ldur w0, [x29, #-\(elemOffset + 16)]")
                    return
                }
            }
            asmLines.append("    mov w0, #0")
        } else if let binaryOp = node as? BinaryOp {
            genExpr(binaryOp.left)
            asmLines.append("    str w0, [sp, #-16]!")
            genExpr(binaryOp.right)
            asmLines.append("    mov w1, w0")
            asmLines.append("    ldr w0, [sp], #16")

            switch binaryOp.op {
            case let op where op == OP.add.emit:
                asmLines.append("    add w0, w0, w1")
            case let op where op == OP.sub.emit:
                asmLines.append("    sub w0, w0, w1")
            case let op where op == OP.mul.emit:
                asmLines.append("    mul w0, w0, w1")
            case let op where op == OP.div.emit:
                asmLines.append("    sdiv w0, w0, w1")
            case let op where op == OP.mod.emit:
                asmLines.append("    sdiv w2, w0, w1")
                asmLines.append("    msub w0, w2, w1, w0")
            case let op where op == OP.eq.emit:
                asmLines.append("    cmp w0, w1")
                asmLines.append("    cset w0, eq")
            case let op where op == OP.neq.emit:
                asmLines.append("    cmp w0, w1")
                asmLines.append("    cset w0, ne")
            case let op where op == OP.lt.emit:
                asmLines.append("    cmp w0, w1")
                asmLines.append("    cset w0, lt")
            case let op where op == OP.gt.emit:
                asmLines.append("    cmp w0, w1")
                asmLines.append("    cset w0, gt")
            case let op where op == OP.lte.emit:
                asmLines.append("    cmp w0, w1")
                asmLines.append("    cset w0, le")
            case let op where op == OP.gte.emit:
                asmLines.append("    cmp w0, w1")
                asmLines.append("    cset w0, ge")
            case let op where op == OP.and.emit:
                asmLines.append("    and w0, w0, w1")
            case let op where op == OP.or.emit:
                asmLines.append("    orr w0, w0, w1")
            default:
                break
            }
        } else if let funcCall = node as? FuncCall {
            if functions[funcCall.name] != nil {
                let argRegs = ["w20", "w21", "w22", "w23", "w24", "w25", "w26", "w27"]
                for (i, arg) in funcCall.args.prefix(8).enumerated() {
                    genExpr(arg)
                    asmLines.append("    mov \(argRegs[i]), w0")
                }
                for i in 0..<min(funcCall.args.count, 8) {
                    asmLines.append("    mov w\(i), \(argRegs[i])")
                }
                asmLines.append("    bl _\(funcCall.name)")
            }
        }
    }

    // MARK: - Float Support

    /// Determine if an expression evaluates to a float
    private func isFloatExpr(_ node: ASTNode) -> Bool {
        if let literal = node as? Literal {
            return literal.value is Double
        } else if let varRef = node as? VarRef {
            return floatVars.contains(varRef.name)
        } else if let binaryOp = node as? BinaryOp {
            return isFloatExpr(binaryOp.left) || isFloatExpr(binaryOp.right)
        } else if let unaryOp = node as? UnaryOp {
            return isFloatExpr(unaryOp.operand)
        }
        return false
    }

    /// Generate code that leaves a float result in d0
    private func genFloatExpr(_ node: ASTNode) {
        if let literal = node as? Literal {
            if let dblVal = literal.value as? Double {
                let label = addDouble(dblVal)
                asmLines.append("    adrp x8, \(label)\(T.pageDirective)")
                asmLines.append("    ldr d0, [x8, \(label)\(T.pageOffDirective)]")
            } else if let intVal = literal.value as? Int {
                // Int literal in float context — convert
                if intVal >= -65536 && intVal <= 65535 {
                    asmLines.append("    mov w0, #\(intVal)")
                } else {
                    asmLines.append("    movz w0, #\(intVal & 0xFFFF)")
                    if intVal > 65535 {
                        asmLines.append("    movk w0, #\((intVal >> 16) & 0xFFFF), lsl #16")
                    }
                }
                asmLines.append("    scvtf d0, w0")
            }
        } else if let varRef = node as? VarRef {
            if floatVars.contains(varRef.name), let offset = variables[varRef.name] {
                asmLines.append("    ldur d0, [x29, #-\(offset + 16)]")
            } else if let offset = variables[varRef.name] {
                // Int variable in float context — load and convert
                asmLines.append("    ldur w0, [x29, #-\(offset + 16)]")
                asmLines.append("    scvtf d0, w0")
            }
        } else if let binaryOp = node as? BinaryOp {
            // Left operand -> d0, push to stack, right operand -> d0, pop left into d1
            genFloatExpr(binaryOp.left)
            asmLines.append("    str d0, [sp, #-16]!")
            genFloatExpr(binaryOp.right)
            asmLines.append("    fmov d1, d0")
            asmLines.append("    ldr d0, [sp], #16")

            switch binaryOp.op {
            case let op where op == OP.add.emit:
                asmLines.append("    fadd d0, d0, d1")
            case let op where op == OP.sub.emit:
                asmLines.append("    fsub d0, d0, d1")
            case let op where op == OP.mul.emit:
                asmLines.append("    fmul d0, d0, d1")
            case let op where op == OP.div.emit:
                asmLines.append("    fdiv d0, d0, d1")
            case let op where op == OP.mod.emit:
                // Float mod: d0 = d0 - (trunc(d0/d1) * d1)
                asmLines.append("    fdiv d2, d0, d1")      // d2 = d0 / d1
                asmLines.append("    frintz d2, d2")         // d2 = trunc(d2) (round toward zero)
                asmLines.append("    fmsub d0, d2, d1, d0")  // d0 = d0 - d2*d1
            default:
                break
            }
        } else if let unaryOp = node as? UnaryOp {
            genFloatExpr(unaryOp.operand)
            if unaryOp.op == "-" || unaryOp.op == OP.sub.emit {
                asmLines.append("    fneg d0, d0")
            }
        }
    }
}
