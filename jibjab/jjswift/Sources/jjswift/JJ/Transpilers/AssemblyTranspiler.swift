/// JibJab ARM64 Assembly Transpiler - Converts JJ to ARM64 Assembly (macOS)
/// Uses emit values from common/jj.json

private let OP = JJ.operators

class AssemblyTranspiler {
    private var asmLines: [String] = []
    private var strings: [(label: String, value: String, addNewline: Bool)] = []
    private var labelCounter = 0
    private var variables: [String: Int] = [:]
    private var stackOffset = 0
    private var functions: [String: FuncDef] = [:]
    private var currentFunc: String? = nil

    func transpile(_ program: Program) -> String {
        asmLines = []
        strings = []
        labelCounter = 0
        variables = [:]
        stackOffset = 0
        functions = [:]

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

        // Allocate stack for variables
        let maxVars = 16
        asmLines.append("    sub sp, sp, #\(maxVars * 8 + 16)")
        stackOffset = 16
        variables = [:]

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

        let maxVars = 16
        asmLines.append("    sub sp, sp, #\(maxVars * 8 + 16)")

        let oldVars = variables
        let oldOffset = stackOffset
        variables = [:]
        stackOffset = 16

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
        }
    }

    private func genPrint(_ node: PrintStmt) {
        if let literal = node.expr as? Literal, let str = literal.value as? String {
            let strLabel = addStringRaw(str)
            asmLines.append("    adrp x0, \(strLabel)@PAGE")
            asmLines.append("    add x0, x0, \(strLabel)@PAGEOFF")
            asmLines.append("    bl _printf")
        } else {
            genExpr(node.expr)
            asmLines.append("    sxtw x0, w0")
            asmLines.append("    str x0, [sp]")
            asmLines.append("    adrp x0, _fmt_int@PAGE")
            asmLines.append("    add x0, x0, _fmt_int@PAGEOFF")
            asmLines.append("    bl _printf")
        }
    }

    private func genVarDecl(_ node: VarDecl) {
        genExpr(node.value)
        if variables[node.name] == nil {
            variables[node.name] = stackOffset
            stackOffset += 8
        }
        let offset = variables[node.name]!
        asmLines.append("    stur w0, [x29, #-\(offset + 16)]")
    }

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
            } else {
                asmLines.append("    mov w0, #0")
            }
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
