/// JibJab ARM64 Assembly Transpiler - Converts JJ to ARM64 Assembly (macOS)
/// Uses emit values from common/jj.json

private let OP = JJ.operators

struct ArrayInfo {
    let baseOffset: Int   // Stack offset of first element
    let count: Int        // Number of elements
    let isString: Bool    // String pointers vs int values
}

class AssemblyTranspiler {
    private var asmLines: [String] = []
    private var strings: [(label: String, value: String, addNewline: Bool)] = []
    private var labelCounter = 0
    private var variables: [String: Int] = [:]
    private var stackOffset = 0
    private var functions: [String: FuncDef] = [:]
    private var currentFunc: String? = nil
    private var enums: [String: [String: Int]] = [:]  // Track enum name -> case name -> value
    private var arrays: [String: ArrayInfo] = [:]     // Track array variables

    func transpile(_ program: Program) -> String {
        asmLines = []
        strings = []
        labelCounter = 0
        variables = [:]
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
        asmLines.append(".global _main")
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
        asmLines.append("_main:")
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
        asmLines.append("_fmt_int:")
        asmLines.append("    .asciz \"%d\\n\"")
        asmLines.append("_fmt_str:")
        asmLines.append("    .asciz \"%s\\n\"")

        for item in strings {
            var escaped = item.value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            if item.addNewline {
                escaped += "\\n"
            }
            asmLines.append("\(item.label):")
            asmLines.append("    .asciz \"\(escaped)\"")
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
        variables = [:]
        stackOffset = 16
        arrays = [:]

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
            asmLines.append("    b _\(currentFunc!)_ret")
        } else if let enumDef = node as? EnumDef {
            // Store enum case values (0, 1, 2, ...)
            var caseValues: [String: Int] = [:]
            for (i, caseName) in enumDef.cases.enumerated() {
                caseValues[caseName] = i
            }
            enums[enumDef.name] = caseValues
        }
    }

    private func genPrint(_ node: PrintStmt) {
        if let literal = node.expr as? Literal, let str = literal.value as? String {
            let strLabel = addStringRaw(str)
            asmLines.append("    adrp x0, \(strLabel)@PAGE")
            asmLines.append("    add x0, x0, \(strLabel)@PAGEOFF")
            asmLines.append("    bl _printf")
        } else if let varRef = node.expr as? VarRef, let arrInfo = arrays[varRef.name] {
            // Print entire array: loop through elements
            for i in 0..<arrInfo.count {
                let elemOffset = arrInfo.baseOffset + i * 8
                if arrInfo.isString {
                    // Load string pointer and print with %s (variadic: arg on stack)
                    asmLines.append("    ldur x0, [x29, #-\(elemOffset + 16)]")
                    asmLines.append("    str x0, [sp]")
                    asmLines.append("    adrp x0, _fmt_str@PAGE")
                    asmLines.append("    add x0, x0, _fmt_str@PAGEOFF")
                    asmLines.append("    bl _printf")
                } else {
                    // Load int and print with %d
                    asmLines.append("    ldur w1, [x29, #-\(elemOffset + 16)]")
                    asmLines.append("    sxtw x1, w1")
                    asmLines.append("    str x1, [sp]")
                    asmLines.append("    adrp x0, _fmt_int@PAGE")
                    asmLines.append("    add x0, x0, _fmt_int@PAGEOFF")
                    asmLines.append("    bl _printf")
                }
            }
        } else if let idx = node.expr as? IndexAccess,
                  let varRef = idx.array as? VarRef,
                  let arrInfo = arrays[varRef.name] {
            // Print single array element
            if arrInfo.isString {
                genArrayLoad(varRef: varRef, index: idx.index, arrInfo: arrInfo, useX: true)
                asmLines.append("    str x0, [sp]")
                asmLines.append("    adrp x0, _fmt_str@PAGE")
                asmLines.append("    add x0, x0, _fmt_str@PAGEOFF")
                asmLines.append("    bl _printf")
            } else {
                genArrayLoad(varRef: varRef, index: idx.index, arrInfo: arrInfo, useX: false)
                asmLines.append("    sxtw x0, w0")
                asmLines.append("    str x0, [sp]")
                asmLines.append("    adrp x0, _fmt_int@PAGE")
                asmLines.append("    add x0, x0, _fmt_int@PAGEOFF")
                asmLines.append("    bl _printf")
            }
        } else {
            genExpr(node.expr)
            asmLines.append("    sxtw x0, w0")
            asmLines.append("    str x0, [sp]")
            asmLines.append("    adrp x0, _fmt_int@PAGE")
            asmLines.append("    add x0, x0, _fmt_int@PAGEOFF")
            asmLines.append("    bl _printf")
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

    private func genVarDecl(_ node: VarDecl) {
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
                        asmLines.append("    adrp x0, \(strLabel)@PAGE")
                        asmLines.append("    add x0, x0, \(strLabel)@PAGEOFF")
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
            // Scalar variable
            genExpr(node.value)
            if variables[node.name] == nil {
                variables[node.name] = stackOffset
                stackOffset += 8
            }
            let offset = variables[node.name]!
            asmLines.append("    stur w0, [x29, #-\(offset + 16)]")
        }
    }

    // Track nested (2D) array dimensions
    private var nestedArrays: [String: (outerCount: Int, innerSize: Int)] = [:]

    private func genLoop(_ node: LoopStmt) {
        if node.start != nil && node.end != nil {
            let loopStart = newLabel(prefix: "loop")
            let loopEnd = newLabel(prefix: "endloop")

            genExpr(node.start!)
            if variables[node.var] == nil {
                variables[node.var] = stackOffset
                stackOffset += 8
            }
            let varOffset = variables[node.var]!
            asmLines.append("    stur w0, [x29, #-\(varOffset + 16)]")

            genExpr(node.end!)
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
            genExpr(binaryOp.left)
            asmLines.append("    mov w9, w0")
            genExpr(binaryOp.right)
            asmLines.append("    cmp w9, w0")

            let branches: [String: String] = [
                JJ.operators.eq.emit: "b.ne",
                JJ.operators.neq.emit: "b.eq",
                JJ.operators.lt.emit: "b.ge",
                JJ.operators.gt.emit: "b.le"
            ]
            if let branch = branches[binaryOp.op] {
                asmLines.append("    \(branch) \(falseLabel)")
            } else {
                genExpr(node)
                asmLines.append("    cmp w0, #0")
                asmLines.append("    b.eq \(falseLabel)")
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
            if let offset = variables[varRef.name] {
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
}
