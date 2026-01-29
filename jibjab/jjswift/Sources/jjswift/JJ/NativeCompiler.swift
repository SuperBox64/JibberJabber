/// JibJab Native Compiler - Compiles JJ directly to ARM64 Mach-O binary
/// Uses direct syscalls for I/O - no external library dependencies

import Foundation

public class NativeCompiler {
    public init() {}
    private var code: [UInt8] = []
    private var data: [UInt8] = []
    private var variables: [String: Int] = [:]
    private var functions: [String: (codeOffset: Int, def: FuncDef)] = [:]
    private var labelOffsets: [String: Int] = [:]
    private var pendingBranches: [(offset: Int, label: String, type: BranchType)] = []
    private var stringOffsets: [String: Int] = [:]
    private var stackOffset = 0
    private var currentFunc: String? = nil
    private var printIntOffset = 0  // Offset of print_int routine in code
    private var printFloatOffset = 0  // Offset of print_float routine in code
    private var floatVars: Set<String> = []  // Variables that hold float values
    private var enums: [String: [String]] = [:]  // enum name -> case names
    private var enumVarTypes: [String: String] = [:]  // var name -> "enum" if it holds an enum string ptr

    enum VarType { case int, string, bool, array, stringArray, nestedArray }
    private var arrays: [String: (offset: Int, count: Int, elemType: VarType)] = [:]  // array metadata

    enum TupleElemType { case int, string, bool }
    private var tuples: [String: (offset: Int, types: [TupleElemType])] = [:]

    struct DictEntry { let key: String; let type: TupleElemType; let offset: Int; let subArray: String? }
    private var dicts: [String: [DictEntry]] = [:]

    enum BranchType { case b, beq, bne, bge, ble, bgt, blt, bl }

    public func compile(_ program: Program, outputPath: String) throws {
        code = []
        data = []
        variables = [:]
        functions = [:]
        labelOffsets = [:]
        pendingBranches = []
        stringOffsets = [:]
        stackOffset = 0
        enums = [:]
        enumVarTypes = [:]
        arrays = [:]
        tuples = [:]
        dicts = [:]
        floatVars = []

        // Generate helper routines
        printIntOffset = code.count
        genPrintIntRoutine()
        printFloatOffset = code.count
        genPrintFloatRoutine()

        // Collect function definitions
        for stmt in program.statements {
            if let funcDef = stmt as? FuncDef {
                functions[funcDef.name] = (codeOffset: 0, def: funcDef)
            }
        }

        // Generate user function code
        for stmt in program.statements {
            if let funcDef = stmt as? FuncDef {
                functions[funcDef.name]?.codeOffset = code.count
                genFunc(funcDef)
            }
        }

        // Generate _main
        let mainOffset = code.count
        let mainStmts = program.statements.filter { !($0 is FuncDef) }

        // Prologue
        emit(0xA9BF7BFD)  // stp x29, x30, [sp, #-16]!
        emit(0xA9BF53F3)  // stp x19, x20, [sp, #-16]!
        emit(0x910003FD)  // mov x29, sp
        emit(0xD10403FF)  // sub sp, sp, #256

        stackOffset = 16
        variables = [:]

        for stmt in mainStmts {
            genStmt(stmt)
        }

        // Epilogue - exit(0) syscall
        emit(0x52800000)  // mov w0, #0
        emit(0xD2800030)  // movz x16, #1
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16 -> x16 = 0x2000001
        emit(0xD4001001)  // svc #0x80

        // Resolve internal branches
        resolveBranches()

        // Write Mach-O
        try writeMachO(to: outputPath, mainOffset: mainOffset)
    }

    // MARK: - Print Integer Routine (syscall-based)

    private func genPrintIntRoutine() {
        // Input: w0 = integer to print
        // Uses syscall write(1, buf, len) via svc #0x80
        // Stack buffer for digits

        emit(0xA9BF7BFD)  // stp x29, x30, [sp, #-16]!
        emit(0x910003FD)  // mov x29, sp
        emit(0xD100C3FF)  // sub sp, sp, #48 (buffer space, 16-byte aligned)

        // Check if negative
        emit(0x7100001F)  // cmp w0, #0
        emit(0x540000CA)  // b.ge skip_neg (6 instructions forward)

        // Negate for processing
        emit(0x4B0003E8)  // neg w8, w0
        emit(0x528005A9)  // mov w9, #'-' (45 = 0x2D)
        emit(0x390003E9)  // strb w9, [sp]
        emit(0x52800029)  // mov w9, #1 (wrote minus sign)
        emit(0x14000003)  // b continue

        // skip_neg:
        emit(0x2A0003E8)  // mov w8, w0
        emit(0x52800009)  // mov w9, #0 (no minus sign)

        // continue: w8 = abs value, w9 = prefix length (0 or 1)
        // Convert to string (reversed)
        emit(0x910083EA)  // add x10, sp, #32 (end of buffer)
        emit(0x5280014B)  // mov w11, #10

        // digit_loop:
        let loopOffset = code.count
        emit(0x1ACB08EC)  // udiv w12, w7, w11 -> use w8
        // Actually: udiv w12, w8, w11
        code[code.count-4] = 0x0C
        code[code.count-3] = 0x09
        code[code.count-2] = 0xCB
        code[code.count-1] = 0x1A

        emit(0x1B0BA18C)  // msub w12, w12, w11, w8 (remainder = w8 - w12*w11)

        emit(0x1100C18C)  // add w12, w12, #'0' (48)
        emit(0x381FFD4C)  // strb w12, [x10, #-1]! (pre-index, decrement x10)
        emit(0x1ACB0908)  // udiv w8, w8, w11
        emit(0x7100011F)  // cmp w8, #0
        let branchBack = code.count
        emit(0x54000001)  // b.ne digit_loop

        // Patch branch
        let delta = (loopOffset - branchBack) / 4
        let d = UInt32(bitPattern: Int32(delta))
        code[branchBack] = UInt8((0x54000001 | ((d & 0x7FFFF) << 5)) & 0xFF)
        code[branchBack+1] = UInt8(((0x54000001 | ((d & 0x7FFFF) << 5)) >> 8) & 0xFF)
        code[branchBack+2] = UInt8(((0x54000001 | ((d & 0x7FFFF) << 5)) >> 16) & 0xFF)
        code[branchBack+3] = UInt8(((0x54000001 | ((d & 0x7FFFF) << 5)) >> 24) & 0xFF)

        // Copy minus sign if needed
        emit(0x7100013F)  // cmp w9, #0
        emit(0x54000060)  // b.eq skip_copy (3 instructions forward, skip ldrb+strb)
        emit(0x394003ED)  // ldrb w13, [sp] (load minus sign)
        emit(0x381FFD4D)  // strb w13, [x10, #-1]! (pre-index, store before digits)
        // skip_copy: (length calculation for BOTH paths)

        // Calculate length: 32+sp - x10 + newline
        emit(0xD10083EE)  // sub x14, sp, #32 -> add x14, sp, #32
        code[code.count-4] = 0xEE
        code[code.count-3] = 0x83
        code[code.count-2] = 0x00
        code[code.count-1] = 0x91

        emit(0xCB0A01C2)  // sub x2, x14, x10 (length)

        // Add newline at end
        emit(0x910083EE)  // add x14, sp, #32
        emit(0x0B0201CF)  // add w15, w14, w2 -> calculate end pos
        code[code.count-4] = 0xCF
        code[code.count-3] = 0x01
        code[code.count-2] = 0x02
        code[code.count-1] = 0x0B

        // Simpler approach: write syscall
        emit(0xAA0A03E1)  // mov x1, x10 (buffer start)
        emit(0xD2800020)  // mov x0, #1 (stdout)
        emit(0x11000442)  // add w2, w2, #1 (include newline... skip for now)
        code[code.count-4] = 0x42  // Actually just use length
        code[code.count-3] = 0x00
        code[code.count-2] = 0x00
        code[code.count-1] = 0x11

        emit(0xD2800090)  // mov x16, #0x2000004 (SYS_write with UNIX class)
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16
        emit(0xD4001001)  // svc #0x80

        // Print newline
        emit(0x5280014D)  // mov w13, #'\n' (10)
        emit(0x390003ED)  // strb w13, [sp]
        emit(0x910003E1)  // mov x1, sp
        emit(0xD2800020)  // mov x0, #1
        emit(0xD2800022)  // mov x2, #1
        emit(0xD2800090)  // movz x16, #4
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16 -> x16 = 0x2000004
        emit(0xD4001001)  // svc #0x80

        // Epilogue
        emit(0x9100C3FF)  // add sp, sp, #48
        emit(0xA8C17BFD)  // ldp x29, x30, [sp], #16
        emit(0xD65F03C0)  // ret
    }

    // MARK: - Print Float Routine (syscall-based, %g-like formatting)

    private func genPrintFloatRoutine() {
        // Input: d0 = double to print
        // %g-like output: no trailing zeros, whole numbers without decimal point
        // Stack layout (96 bytes):
        //   [sp+0..7]:   saved d0
        //   [sp+16..47]: integer digit buffer (write backwards from sp+48)
        //   [sp+48..63]: fractional digit buffer (write forwards)
        //   [sp+80]:     single char write area

        emit(0xA9BF7BFD)  // stp x29, x30, [sp, #-16]!
        emit(0x910003FD)  // mov x29, sp
        emit(0xD10183FF)  // sub sp, sp, #96

        // Save d0
        emit(0xFD0003E0)  // str d0, [sp]

        // Check if negative
        emit(0x1E602008)  // fcmp d0, #0.0
        let skipNegOff = code.count
        emit(0x54000000)  // b.ge skip_neg (placeholder)

        // === Negative: print '-' and negate ===
        emit(0x528005A8)  // mov w8, #45 ('-')
        emit(0x390143E8)  // strb w8, [sp, #80]
        emit(0xD2800020)  // mov x0, #1
        emit(0x910143E1)  // add x1, sp, #80
        emit(0xD2800022)  // mov x2, #1
        emit(0xD2800090)  // movz x16, #4
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16
        emit(0xD4001001)  // svc #0x80

        emit(0xFD4003E0)  // ldr d0, [sp]
        emit(0x1E614000)  // fneg d0, d0
        emit(0xFD0003E0)  // str d0, [sp]

        // skip_neg:
        patchCondBranch(at: skipNegOff, target: code.count, cond: 0xA)

        // Load abs value
        emit(0xFD4003E0)  // ldr d0, [sp]
        emit(0x9E780008)  // fcvtzs x8, d0 (integer part)
        emit(0x9E620101)  // scvtf d1, x8
        emit(0x1E613802)  // fsub d2, d0, d1 (fractional part)

        // Check if whole number
        emit(0x1E602048)  // fcmp d2, #0.0
        let hasDecOff = code.count
        emit(0x54000001)  // b.ne has_decimal (placeholder)

        // === Whole number path ===
        emit(0x9100C3EA)  // add x10, sp, #48 (end of int buffer)
        emit(0x5280014B)  // mov w11, #10

        let wholeLoopOff = code.count
        emit(0x9ACB090C)  // udiv x12, x8, x11
        emit(0x9B0BA18C)  // msub x12, x12, x11, x8
        emit(0x1100C18C)  // add w12, w12, #'0'
        emit(0x381FFD4C)  // strb w12, [x10, #-1]!
        emit(0x9ACB0908)  // udiv x8, x8, x11
        emit(0xF100011F)  // cmp x8, #0
        let whBrOff = code.count
        emit(0x54000001)  // b.ne wholeLoop
        patchCondBranch(at: whBrOff, target: wholeLoopOff, cond: 0x1)

        // Write integer string
        emit(0x9100C3EE)  // add x14, sp, #48
        emit(0xCB0A01C2)  // sub x2, x14, x10
        emit(0xAA0A03E1)  // mov x1, x10
        emit(0xD2800020)  // mov x0, #1
        emit(0xD2800090)  // movz x16, #4
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16
        emit(0xD4001001)  // svc #0x80

        // Print newline
        emit(0x5280014D)  // mov w13, #10 ('\n')
        emit(0x390143ED)  // strb w13, [sp, #80]
        emit(0xD2800020)  // mov x0, #1
        emit(0x910143E1)  // add x1, sp, #80
        emit(0xD2800022)  // mov x2, #1
        emit(0xD2800090)  // movz x16, #4
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16
        emit(0xD4001001)  // svc #0x80

        // Branch to epilogue
        let wholeEndOff = code.count
        emit(0x14000000)  // b epilogue (placeholder)

        // === Decimal path ===
        patchCondBranch(at: hasDecOff, target: code.count, cond: 0x1)

        // Print integer part
        emit(0x9100C3EA)  // add x10, sp, #48
        emit(0x5280014B)  // mov w11, #10

        // Check if integer part is 0
        emit(0xF100011F)  // cmp x8, #0
        let intZeroOff = code.count
        emit(0x54000000)  // b.eq int_is_zero (placeholder)

        let decIntLoopOff = code.count
        emit(0x9ACB090C)  // udiv x12, x8, x11
        emit(0x9B0BA18C)  // msub x12, x12, x11, x8
        emit(0x1100C18C)  // add w12, w12, #'0'
        emit(0x381FFD4C)  // strb w12, [x10, #-1]!
        emit(0x9ACB0908)  // udiv x8, x8, x11
        emit(0xF100011F)  // cmp x8, #0
        let diBrOff = code.count
        emit(0x54000001)  // b.ne decIntLoop
        patchCondBranch(at: diBrOff, target: decIntLoopOff, cond: 0x1)

        let pastZeroOff = code.count
        emit(0x14000000)  // b past_zero (placeholder)

        // int_is_zero: write '0'
        patchCondBranch(at: intZeroOff, target: code.count, cond: 0x0)
        emit(0x52800608)  // mov w8, #'0'
        emit(0x381FFD48)  // strb w8, [x10, #-1]!

        // past_zero: patch branch
        let pastZeroTarget = code.count
        let pzDelta = (pastZeroTarget - pastZeroOff) / 4
        let pzD = UInt32(bitPattern: Int32(pzDelta))
        let pzInst: UInt32 = 0x14000000 | (pzD & 0x3FFFFFF)
        code[pastZeroOff] = UInt8(pzInst & 0xFF)
        code[pastZeroOff+1] = UInt8((pzInst >> 8) & 0xFF)
        code[pastZeroOff+2] = UInt8((pzInst >> 16) & 0xFF)
        code[pastZeroOff+3] = UInt8((pzInst >> 24) & 0xFF)

        // Write integer string
        emit(0x9100C3EE)  // add x14, sp, #48
        emit(0xCB0A01C2)  // sub x2, x14, x10
        emit(0xAA0A03E1)  // mov x1, x10
        emit(0xD2800020)  // mov x0, #1
        emit(0xD2800090)  // movz x16, #4
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16
        emit(0xD4001001)  // svc #0x80

        // Print '.'
        emit(0x528005C8)  // mov w8, #46 ('.')
        emit(0x390143E8)  // strb w8, [sp, #80]
        emit(0xD2800020)  // mov x0, #1
        emit(0x910143E1)  // add x1, sp, #80
        emit(0xD2800022)  // mov x2, #1
        emit(0xD2800090)  // movz x16, #4
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16
        emit(0xD4001001)  // svc #0x80

        // Recompute fractional part (registers were clobbered)
        emit(0xFD4003E0)  // ldr d0, [sp]
        emit(0x9E780008)  // fcvtzs x8, d0
        emit(0x9E620101)  // scvtf d1, x8
        emit(0x1E613802)  // fsub d2, d0, d1

        // Extract up to 16 fractional digits into sp+48..63
        emit(0x52800009)  // mov w9, #0

        // Load 10.0 constant from data section
        let tenOff = addDouble(10.0)
        emitAdrpAdd(reg: 8, dataOffset: tenOff)
        emit(0xFD400103)  // ldr d3, [x8]

        let fracLoopOff = code.count
        emit(0x1E630842)  // fmul d2, d2, d3
        emit(0x9E78004A)  // fcvtzs x10, d2
        emit(0x1100C14A)  // add w10, w10, #'0'
        emit(0x9100C3EB)  // add x11, sp, #48
        emit(0x3829496A)  // strb w10, [x11, w9, uxtw]
        // Subtract integer part of d2
        emit(0x9E78004A)  // fcvtzs x10, d2
        emit(0x9E620144)  // scvtf d4, x10
        emit(0x1E643842)  // fsub d2, d2, d4
        emit(0x11000529)  // add w9, w9, #1
        emit(0x7100413F)  // cmp w9, #16
        let fracBrOff = code.count
        emit(0x5400000B)  // b.lt fracLoop
        patchCondBranch(at: fracBrOff, target: fracLoopOff, cond: 0xB)

        // Trim trailing zeros
        emit(0x51000529)  // sub w9, w9, #1
        let trimLoopOff = code.count
        emit(0x9100C3EB)  // add x11, sp, #48
        emit(0x3869496A)  // ldrb w10, [x11, w9, uxtw]
        emit(0x7100C15F)  // cmp w10, #'0'
        let trimDoneOff = code.count
        emit(0x54000001)  // b.ne trim_done
        emit(0x51000529)  // sub w9, w9, #1
        emit(0x7100013F)  // cmp w9, #0
        let trimBrOff = code.count
        emit(0x5400000A)  // b.ge trimLoop
        patchCondBranch(at: trimBrOff, target: trimLoopOff, cond: 0xA)

        // trim_done:
        patchCondBranch(at: trimDoneOff, target: code.count, cond: 0x1)

        // Print w9+1 frac digits from sp+48
        emit(0x11000522)  // add w2, w9, #1
        emit(0x9100C3E1)  // add x1, sp, #48
        emit(0xD2800020)  // mov x0, #1
        emit(0xD2800090)  // movz x16, #4
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16
        emit(0xD4001001)  // svc #0x80

        // Print newline
        emit(0x5280014D)  // mov w13, #10
        emit(0x390143ED)  // strb w13, [sp, #80]
        emit(0xD2800020)  // mov x0, #1
        emit(0x910143E1)  // add x1, sp, #80
        emit(0xD2800022)  // mov x2, #1
        emit(0xD2800090)  // movz x16, #4
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16
        emit(0xD4001001)  // svc #0x80

        // Epilogue: patch whole-number branch to here
        let epilogueOff = code.count
        let whDelta = (epilogueOff - wholeEndOff) / 4
        let whD = UInt32(bitPattern: Int32(whDelta))
        let whInst: UInt32 = 0x14000000 | (whD & 0x3FFFFFF)
        code[wholeEndOff] = UInt8(whInst & 0xFF)
        code[wholeEndOff+1] = UInt8((whInst >> 8) & 0xFF)
        code[wholeEndOff+2] = UInt8((whInst >> 16) & 0xFF)
        code[wholeEndOff+3] = UInt8((whInst >> 24) & 0xFF)

        emit(0x910183FF)  // add sp, sp, #96
        emit(0xA8C17BFD)  // ldp x29, x30, [sp], #16
        emit(0xD65F03C0)  // ret
    }

    private func patchCondBranch(at offset: Int, target: Int, cond: UInt32) {
        let delta = (target - offset) / 4
        let d = UInt32(bitPattern: Int32(delta))
        let inst = 0x54000000 | ((d & 0x7FFFF) << 5) | cond
        code[offset] = UInt8(inst & 0xFF)
        code[offset+1] = UInt8((inst >> 8) & 0xFF)
        code[offset+2] = UInt8((inst >> 16) & 0xFF)
        code[offset+3] = UInt8((inst >> 24) & 0xFF)
    }

    private func addDouble(_ value: Double) -> Int {
        // Align data to 8 bytes
        while data.count % 8 != 0 { data.append(0) }
        let off = data.count
        var v = value
        let bytes = withUnsafeBytes(of: &v) { Array($0) }
        data.append(contentsOf: bytes)
        return off
    }

    // MARK: - Code Generation

    private func genFunc(_ node: FuncDef) {
        currentFunc = node.name
        labelOffsets["_\(node.name)"] = code.count

        emit(0xA9BF7BFD)  // stp x29, x30, [sp, #-16]!
        emit(0xA9BF53F3)  // stp x19, x20, [sp, #-16]!
        emit(0x910003FD)  // mov x29, sp
        emit(0xD10403FF)  // sub sp, sp, #256

        let oldVars = variables
        let oldOffset = stackOffset
        variables = [:]
        stackOffset = 16

        for (i, param) in node.params.enumerated() {
            variables[param] = stackOffset
            emitStore(reg: i, offset: stackOffset)
            stackOffset += 8
        }

        for stmt in node.body {
            genStmt(stmt)
        }

        emit(0x52800000)  // mov w0, #0
        labelOffsets["_\(node.name)_ret"] = code.count
        emit(0x910403FF)  // add sp, sp, #256
        emit(0xA8C153F3)  // ldp x19, x20, [sp], #16
        emit(0xA8C17BFD)  // ldp x29, x30, [sp], #16
        emit(0xD65F03C0)  // ret

        variables = oldVars
        stackOffset = oldOffset
        currentFunc = nil
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
            addBranch(to: "_\(currentFunc!)_ret", type: .b)
        } else if let enumDef = node as? EnumDef {
            enums[enumDef.name] = enumDef.cases
            // Pre-add case name strings to data section
            for caseName in enumDef.cases {
                _ = addString(caseName)
            }
        }
    }

    private func genPrint(_ node: PrintStmt) {
        if let lit = node.expr as? Literal, let str = lit.value as? String {
            // Print string using write syscall
            let strWithNewline = str + "\n"
            let strOff = addString(strWithNewline)
            let strLen = strWithNewline.utf8.count
            emitWriteSyscall(dataOffset: strOff, length: strLen)
        } else if let varRef = node.expr as? VarRef, enumVarTypes[varRef.name] != nil {
            // Print enum variable (string pointer) + newline
            emitLoadX(reg: 0, offset: variables[varRef.name]!)
            emitPrintCString()
        } else if let idx = node.expr as? IndexAccess, let ref = idx.array as? VarRef, enums[ref.name] != nil {
            // Print enum access: Color["Red"] -> print "Red"
            if let lit = idx.index as? Literal, let key = lit.value as? String {
                let strWithNewline = key + "\n"
                let strOff = addString(strWithNewline)
                let strLen = strWithNewline.utf8.count
                emitWriteSyscall(dataOffset: strOff, length: strLen)
            }
        } else if let varRef = node.expr as? VarRef, let cases = enums[varRef.name] {
            // Print full enum: {"Red": Red, "Green": Green, "Blue": Blue}
            var parts: [String] = []
            for c in cases {
                parts.append("\"\(c)\": \(c)")
            }
            let str = "{" + parts.joined(separator: ", ") + "}\n"
            let strOff = addString(str)
            let strLen = str.utf8.count
            emitWriteSyscall(dataOffset: strOff, length: strLen)
        } else if let varRef = node.expr as? VarRef, let tupInfo = tuples[varRef.name] {
            // Print full tuple: (elem1, elem2, ...)
            let lp = addString("(")
            emitWriteSyscall(dataOffset: lp, length: 1)
            for (i, t) in tupInfo.types.enumerated() {
                if i > 0 {
                    let comma = addString(", ")
                    emitWriteSyscall(dataOffset: comma, length: 2)
                }
                switch t {
                case .string:
                    emitLoadX(reg: 0, offset: tupInfo.offset + i * 8)
                    emitPrintCStringNoNewline()
                case .bool:
                    emitLoad(reg: 0, offset: tupInfo.offset + i * 8)
                    // Print "true" or "false" — emit runtime check
                    emit(0x7100001F)  // cmp w0, #0
                    let falseLabel = "_tf\(code.count)"
                    let doneLabel = "_td\(code.count)"
                    addBranch(to: falseLabel, type: .beq)
                    let trueStr = addString("true")
                    emitWriteSyscall(dataOffset: trueStr, length: 4)
                    addBranch(to: doneLabel, type: .b)
                    labelOffsets[falseLabel] = code.count
                    let falseStr = addString("false")
                    emitWriteSyscall(dataOffset: falseStr, length: 5)
                    labelOffsets[doneLabel] = code.count
                case .int:
                    emitLoad(reg: 0, offset: tupInfo.offset + i * 8)
                    emitPrintIntNoNewline()
                }
            }
            let rp = addString(")\n")
            emitWriteSyscall(dataOffset: rp, length: 2)
        } else if let idx = node.expr as? IndexAccess, let ref = idx.array as? VarRef, let tupInfo = tuples[ref.name] {
            // Tuple index access
            if let lit = idx.index as? Literal, let i = lit.value as? Int, i < tupInfo.types.count {
                let t = tupInfo.types[i]
                switch t {
                case .string:
                    emitLoadX(reg: 0, offset: tupInfo.offset + i * 8)
                    emitPrintCString()
                case .bool:
                    emitLoad(reg: 0, offset: tupInfo.offset + i * 8)
                    emit(0x7100001F)
                    let fl = "_tf\(code.count)"
                    let dl = "_td\(code.count)"
                    addBranch(to: fl, type: .beq)
                    let ts = addString("true\n")
                    emitWriteSyscall(dataOffset: ts, length: 5)
                    addBranch(to: dl, type: .b)
                    labelOffsets[fl] = code.count
                    let fs = addString("false\n")
                    emitWriteSyscall(dataOffset: fs, length: 6)
                    labelOffsets[dl] = code.count
                case .int:
                    emitLoad(reg: 0, offset: tupInfo.offset + i * 8)
                    let delta2 = (printIntOffset - code.count) / 4
                    let d2 = UInt32(bitPattern: Int32(delta2))
                    emit(0x94000000 | (d2 & 0x3FFFFFF))
                }
            }
        } else if let varRef = node.expr as? VarRef, let entries = dicts[varRef.name] {
            // Print full dict or empty dict
            if entries.isEmpty {
                let s = addString("{}\n")
                emitWriteSyscall(dataOffset: s, length: 3)
            } else {
                let lb = addString("{")
                emitWriteSyscall(dataOffset: lb, length: 1)
                for (i, e) in entries.enumerated() {
                    if i > 0 {
                        let cm = addString(", ")
                        emitWriteSyscall(dataOffset: cm, length: 2)
                    }
                    // Print "key": value
                    let keyStr = addString("\"\(e.key)\": ")
                    emitWriteSyscall(dataOffset: keyStr, length: e.key.count + 4)
                    switch e.type {
                    case .string:
                        emitLoadX(reg: 0, offset: e.offset)
                        emitPrintCStringNoNewline()
                    case .bool:
                        emitLoad(reg: 0, offset: e.offset)
                        emit(0x7100001F)
                        let fl = "_tf\(code.count)"; let dl = "_td\(code.count)"
                        addBranch(to: fl, type: .beq)
                        let ts = addString("true"); emitWriteSyscall(dataOffset: ts, length: 4)
                        addBranch(to: dl, type: .b)
                        labelOffsets[fl] = code.count
                        let fs = addString("false"); emitWriteSyscall(dataOffset: fs, length: 5)
                        labelOffsets[dl] = code.count
                    case .int:
                        if let sub = e.subArray, let arrInfo = arrays[sub] {
                            emitPrintFullArrayInline(name: sub, info: arrInfo)
                        } else {
                            emitLoad(reg: 0, offset: e.offset)
                            emitPrintIntNoNewline()
                        }
                    }
                }
                let rb = addString("}\n")
                emitWriteSyscall(dataOffset: rb, length: 2)
            }
        } else if let idx = node.expr as? IndexAccess, let ref = idx.array as? VarRef, let entries = dicts[ref.name] {
            // Dict key access: person["name"]
            if let lit = idx.index as? Literal, let key = lit.value as? String {
                if let entry = entries.first(where: { $0.key == key }) {
                    switch entry.type {
                    case .string:
                        emitLoadX(reg: 0, offset: entry.offset)
                        emitPrintCString()
                    case .bool:
                        emitLoad(reg: 0, offset: entry.offset)
                        emit(0x7100001F)
                        let fl = "_tf\(code.count)"; let dl = "_td\(code.count)"
                        addBranch(to: fl, type: .beq)
                        let ts = addString("true\n"); emitWriteSyscall(dataOffset: ts, length: 5)
                        addBranch(to: dl, type: .b)
                        labelOffsets[fl] = code.count
                        let fs = addString("false\n"); emitWriteSyscall(dataOffset: fs, length: 6)
                        labelOffsets[dl] = code.count
                    case .int:
                        if let sub = entry.subArray, arrays[sub] != nil {
                            emitPrintFullArray(name: sub, info: arrays[sub]!)
                        } else {
                            emitLoad(reg: 0, offset: entry.offset)
                            let delta2 = (printIntOffset - code.count) / 4
                            let d2 = UInt32(bitPattern: Int32(delta2))
                            emit(0x94000000 | (d2 & 0x3FFFFFF))
                        }
                    }
                }
            }
        } else if let idx = node.expr as? IndexAccess, let innerIdx = idx.array as? IndexAccess,
                  let ref = innerIdx.array as? VarRef, let entries = dicts[ref.name] {
            // Nested: data["items"][0]
            if let keyLit = innerIdx.index as? Literal, let key = keyLit.value as? String {
                if let entry = entries.first(where: { $0.key == key }), let sub = entry.subArray, arrays[sub] != nil {
                    genArrayIndexLoad(name: sub, index: idx.index, isString: arrays[sub]!.elemType == .stringArray)
                    if arrays[sub]!.elemType == .stringArray {
                        emitPrintCString()
                    } else {
                        let delta2 = (printIntOffset - code.count) / 4
                        let d2 = UInt32(bitPattern: Int32(delta2))
                        emit(0x94000000 | (d2 & 0x3FFFFFF))
                    }
                }
            }
        } else if let varRef = node.expr as? VarRef, let arrInfo = arrays[varRef.name] {
            // Print full array: [elem, elem, ...]
            emitPrintFullArray(name: varRef.name, info: arrInfo)
        } else if let idx = node.expr as? IndexAccess, let ref = idx.array as? VarRef, let arrInfo = arrays[ref.name] {
            if arrInfo.elemType == .stringArray {
                // String array index access - print string
                genArrayIndexLoad(name: ref.name, index: idx.index, isString: true)
                emitPrintCString()
            } else if arrInfo.elemType == .nestedArray {
                // Nested array index: matrix[0][1]
                if let outerIdx = idx.index as? Literal, let outerI = outerIdx.value as? Int {
                    // This is just matrix[i] — but if it's followed by another index, it's handled differently
                    // For now, print the sub-array
                    let subName = "\(ref.name)_\(outerI)"
                    if let subInfo = arrays[subName] {
                        emitPrintFullArray(name: subName, info: subInfo)
                    }
                }
            } else {
                // Integer array index access - print int
                genArrayIndexLoad(name: ref.name, index: idx.index, isString: false)
                let delta = (printIntOffset - code.count) / 4
                let d = UInt32(bitPattern: Int32(delta))
                emit(0x94000000 | (d & 0x3FFFFFF))
            }
        } else if let idx = node.expr as? IndexAccess, let innerIdx = idx.array as? IndexAccess,
                  let ref = innerIdx.array as? VarRef, arrays[ref.name]?.elemType == .nestedArray {
            // Nested index: matrix[0][1] -> load from sub-array
            if let outerLit = innerIdx.index as? Literal, let outerI = outerLit.value as? Int {
                let subName = "\(ref.name)_\(outerI)"
                if arrays[subName] != nil {
                    genArrayIndexLoad(name: subName, index: idx.index, isString: false)
                    let delta = (printIntOffset - code.count) / 4
                    let d = UInt32(bitPattern: Int32(delta))
                    emit(0x94000000 | (d & 0x3FFFFFF))
                }
            }
        } else if isFloatExpr(node.expr) {
            // Print float - call print_float routine
            genFloatExpr(node.expr)
            let delta = (printFloatOffset - code.count) / 4
            let d = UInt32(bitPattern: Int32(delta))
            emit(0x94000000 | (d & 0x3FFFFFF))
        } else {
            // Print integer - call print_int routine
            genExpr(node.expr)
            let delta = (printIntOffset - code.count) / 4
            let d = UInt32(bitPattern: Int32(delta))
            emit(0x94000000 | (d & 0x3FFFFFF))
        }
    }

    /// Write a string from data section to stdout
    private func emitWriteSyscall(dataOffset: Int, length: Int) {
        emit(0xD2800020)  // mov x0, #1 (stdout)
        emitAdrpAdd(reg: 1, dataOffset: dataOffset)
        emitMovImm(reg: 2, value: length)
        emit(0xD2800090)  // movz x16, #4
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16
        emit(0xD4001001)  // svc #0x80
    }

    /// Print a C string whose pointer is in x0, followed by newline
    private func emitPrintCString() {
        // x0 has pointer to null-terminated string
        // We need to find length, then write, then print newline
        emit(0xAA0003E1)  // mov x1, x0 (save string ptr in x1)
        emit(0xAA0003E2)  // mov x2, x0 (use x2 as scanner)
        // Loop to find null terminator
        let scanLoop = code.count
        emit(0x39400048)  // ldrb w8, [x2]
        emit(0x91000442)  // add x2, x2, #1
        emit(0x7100011F)  // cmp w8, #0
        // b.ne scanLoop
        let branchOff = code.count
        emit(0x54000001)  // b.ne (placeholder)
        let delta = (scanLoop - branchOff) / 4
        let d = UInt32(bitPattern: Int32(delta))
        code[branchOff] = UInt8((0x54000001 | ((d & 0x7FFFF) << 5)) & 0xFF)
        code[branchOff+1] = UInt8(((0x54000001 | ((d & 0x7FFFF) << 5)) >> 8) & 0xFF)
        code[branchOff+2] = UInt8(((0x54000001 | ((d & 0x7FFFF) << 5)) >> 16) & 0xFF)
        code[branchOff+3] = UInt8(((0x54000001 | ((d & 0x7FFFF) << 5)) >> 24) & 0xFF)

        // x2 is now past the null terminator, length = x2 - x1 - 1
        emit(0xCB010042)  // sub x2, x2, x1
        emit(0xD1000442)  // sub x2, x2, #1

        // write(1, x1, x2)
        emit(0xD2800020)  // mov x0, #1 (stdout)
        emit(0xD2800090)  // movz x16, #4
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16
        emit(0xD4001001)  // svc #0x80

        // Print newline
        emit(0xD100C3FF)  // sub sp, sp, #48
        emit(0x5280014D)  // mov w13, #'\n' (10)
        emit(0x390003ED)  // strb w13, [sp]
        emit(0x910003E1)  // mov x1, sp
        emit(0xD2800020)  // mov x0, #1
        emit(0xD2800022)  // mov x2, #1
        emit(0xD2800090)  // movz x16, #4
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16
        emit(0xD4001001)  // svc #0x80
        emit(0x9100C3FF)  // add sp, sp, #48
    }

    private func genVarDecl(_ node: VarDecl) {
        // Check if this is an enum access assignment
        if let idx = node.value as? IndexAccess, let ref = idx.array as? VarRef, enums[ref.name] != nil {
            enumVarTypes[node.name] = "enum"
        }

        // Handle array literal
        if let arrLit = node.value as? ArrayLiteral {
            genArrayDecl(node.name, arrLit)
            return
        }

        // Handle tuple literal
        if let tupLit = node.value as? TupleLiteral {
            genTupleDecl(node.name, tupLit)
            return
        }

        // Handle dict literal
        if let dictLit = node.value as? DictLiteral {
            genDictDecl(node.name, dictLit)
            return
        }

        // Check if float expression
        if isFloatExpr(node.value) {
            genFloatExpr(node.value)
            if variables[node.name] == nil {
                variables[node.name] = stackOffset
                stackOffset += 8
            }
            floatVars.insert(node.name)
            emitStoreD(reg: 0, offset: variables[node.name]!)
            return
        }

        genExpr(node.value)
        if variables[node.name] == nil {
            variables[node.name] = stackOffset
            stackOffset += 8
        }
        // Store x0 (pointer for enums, value for ints)
        emitStoreX(reg: 0, offset: variables[node.name]!)
    }

    private func genArrayDecl(_ name: String, _ arrLit: ArrayLiteral) {
        let baseOff = stackOffset
        // Determine element type
        var elemType: VarType = .int
        if let first = arrLit.elements.first {
            if let lit = first as? Literal, lit.value is String {
                elemType = .stringArray
            } else if first is ArrayLiteral {
                elemType = .nestedArray
            }
        }

        if elemType == .nestedArray {
            // Nested arrays: store each sub-array, then store pointers to them
            var subArrayNames: [String] = []
            for (i, elem) in arrLit.elements.enumerated() {
                if let subArr = elem as? ArrayLiteral {
                    let subName = "\(name)_\(i)"
                    genArrayDecl(subName, subArr)
                    subArrayNames.append(subName)
                }
            }
            // Store base offsets of sub-arrays as the outer array
            let outerBase = stackOffset
            for subName in subArrayNames {
                let subInfo = arrays[subName]!
                emitMovImm(reg: 0, value: subInfo.offset)
                if variables[name] == nil || stackOffset == outerBase + subArrayNames.count * 8 {
                    // Just keep stacking
                }
                emitStore(reg: 0, offset: stackOffset)
                stackOffset += 8
            }
            arrays[name] = (offset: outerBase, count: subArrayNames.count, elemType: .nestedArray)
            variables[name] = outerBase
        } else if elemType == .stringArray {
            // String array: store string pointers
            for elem in arrLit.elements {
                if let lit = elem as? Literal, let s = lit.value as? String {
                    let strOff = addString(s)
                    emitAdrpAdd(reg: 0, dataOffset: strOff)
                    emitStoreX(reg: 0, offset: stackOffset)
                    stackOffset += 8
                }
            }
            arrays[name] = (offset: baseOff, count: arrLit.elements.count, elemType: .stringArray)
            variables[name] = baseOff
        } else {
            // Integer array: store values
            for elem in arrLit.elements {
                genExpr(elem)
                emitStore(reg: 0, offset: stackOffset)
                stackOffset += 8
            }
            arrays[name] = (offset: baseOff, count: arrLit.elements.count, elemType: .int)
            variables[name] = baseOff
        }
    }

    private func genTupleDecl(_ name: String, _ tupLit: TupleLiteral) {
        let baseOff = stackOffset
        var types: [TupleElemType] = []

        for elem in tupLit.elements {
            if let lit = elem as? Literal {
                if let s = lit.value as? String {
                    types.append(.string)
                    let strOff = addString(s)
                    emitAdrpAdd(reg: 0, dataOffset: strOff)
                    emitStoreX(reg: 0, offset: stackOffset)
                } else if let b = lit.value as? Bool {
                    types.append(.bool)
                    emitMovImm(reg: 0, value: b ? 1 : 0)
                    emitStore(reg: 0, offset: stackOffset)
                } else if let n = lit.value as? Int {
                    types.append(.int)
                    emitMovImm(reg: 0, value: n)
                    emitStore(reg: 0, offset: stackOffset)
                } else {
                    types.append(.int)
                    emit(0x52800000)
                    emitStore(reg: 0, offset: stackOffset)
                }
            } else {
                types.append(.int)
                genExpr(elem)
                emitStore(reg: 0, offset: stackOffset)
            }
            stackOffset += 8
        }

        tuples[name] = (offset: baseOff, types: types)
        variables[name] = baseOff
    }

    private func genDictDecl(_ name: String, _ dictLit: DictLiteral) {
        var entries: [DictEntry] = []

        for pair in dictLit.pairs {
            guard let keyLit = pair.key as? Literal, let key = keyLit.value as? String else { continue }

            if let arrLit = pair.value as? ArrayLiteral {
                // Nested array value
                let subName = "\(name)_\(key)"
                genArrayDecl(subName, arrLit)
                entries.append(DictEntry(key: key, type: .int, offset: 0, subArray: subName))
            } else if let lit = pair.value as? Literal {
                let off = stackOffset
                if let s = lit.value as? String {
                    let strOff = addString(s)
                    emitAdrpAdd(reg: 0, dataOffset: strOff)
                    emitStoreX(reg: 0, offset: off)
                    entries.append(DictEntry(key: key, type: .string, offset: off, subArray: nil))
                } else if let b = lit.value as? Bool {
                    emitMovImm(reg: 0, value: b ? 1 : 0)
                    emitStore(reg: 0, offset: off)
                    entries.append(DictEntry(key: key, type: .bool, offset: off, subArray: nil))
                } else if let n = lit.value as? Int {
                    emitMovImm(reg: 0, value: n)
                    emitStore(reg: 0, offset: off)
                    entries.append(DictEntry(key: key, type: .int, offset: off, subArray: nil))
                } else {
                    entries.append(DictEntry(key: key, type: .int, offset: off, subArray: nil))
                }
                stackOffset += 8
            }
        }

        dicts[name] = entries
        variables[name] = stackOffset
    }

    private func genLoop(_ node: LoopStmt) {
        guard node.start != nil, node.end != nil else { return }

        let loopLabel = "_L\(code.count)"
        let endLabel = "_E\(code.count)"

        genExpr(node.start!)
        if variables[node.var] == nil {
            variables[node.var] = stackOffset
            stackOffset += 8
        }
        let varOff = variables[node.var]!
        emitStore(reg: 0, offset: varOff)

        genExpr(node.end!)
        let endOff = stackOffset
        stackOffset += 8
        emitStore(reg: 0, offset: endOff)

        labelOffsets[loopLabel] = code.count

        emitLoad(reg: 0, offset: varOff)
        emitLoad(reg: 1, offset: endOff)
        emit(0x6B01001F)  // cmp w0, w1
        addBranch(to: endLabel, type: .bge)

        for stmt in node.body { genStmt(stmt) }

        emitLoad(reg: 0, offset: varOff)
        emit(0x11000400)  // add w0, w0, #1
        emitStore(reg: 0, offset: varOff)
        addBranch(to: loopLabel, type: .b)

        labelOffsets[endLabel] = code.count
    }

    private func genIf(_ node: IfStmt) {
        let elseLabel = "_else\(code.count)"
        let endLabel = "_end\(code.count)"

        if let bin = node.condition as? BinaryOp {
            let useFloat = isFloatExpr(bin.left) || isFloatExpr(bin.right)

            if useFloat {
                // Float comparison using fcmp
                genFloatExpr(bin.left)
                emit(0xFC1F0FE0)  // str d0, [sp, #-16]!
                genFloatExpr(bin.right)
                emit(0x1E604001)  // fmov d1, d0
                emit(0xFC4107E0)  // ldr d0, [sp], #16
                emit(0x1E612010)  // fcmp d0, d1

                let op = bin.op
                if op == "==" { addBranch(to: elseLabel, type: .bne) }
                else if op == "!=" { addBranch(to: elseLabel, type: .beq) }
                else if op == "<" { addBranch(to: elseLabel, type: .bge) }
                else if op == ">" { addBranch(to: elseLabel, type: .ble) }
                else if op == "<=" { addBranch(to: elseLabel, type: .bgt) }
                else if op == ">=" { addBranch(to: elseLabel, type: .blt) }
            } else {
                let isEnumCmp = isEnumExpr(bin.left) || isEnumExpr(bin.right)
                genExpr(bin.left)
                if isEnumCmp {
                    emit(0xAA0003E9)  // mov x9, x0 (64-bit for pointers)
                } else {
                    emit(0x2A0003E9)  // mov w9, w0
                }
                genExpr(bin.right)
                if isEnumCmp {
                    emit(0xEB00013F)  // cmp x9, x0 (64-bit)
                } else {
                    emit(0x6B00013F)  // cmp w9, w0
                }

                let op = bin.op
                if op == "==" { addBranch(to: elseLabel, type: .bne) }
                else if op == "!=" { addBranch(to: elseLabel, type: .beq) }
                else if op == "<" { addBranch(to: elseLabel, type: .bge) }
                else if op == ">" { addBranch(to: elseLabel, type: .ble) }
                else if op == "<=" { addBranch(to: elseLabel, type: .bgt) }
                else if op == ">=" { addBranch(to: elseLabel, type: .blt) }
            }
        } else {
            genExpr(node.condition)
            emit(0x7100001F)  // cmp w0, #0
            addBranch(to: elseLabel, type: .beq)
        }

        for stmt in node.thenBody { genStmt(stmt) }
        if node.elseBody != nil { addBranch(to: endLabel, type: .b) }

        labelOffsets[elseLabel] = code.count
        if let elseBody = node.elseBody {
            for stmt in elseBody { genStmt(stmt) }
            labelOffsets[endLabel] = code.count
        }
    }

    private func genExpr(_ node: ASTNode) {
        if let lit = node as? Literal {
            if let n = lit.value as? Int {
                emitMovImm(reg: 0, value: n)
            } else if let b = lit.value as? Bool {
                emitMovImm(reg: 0, value: b ? 1 : 0)
            } else {
                emit(0x52800000)
            }
        } else if let varRef = node as? VarRef {
            if let off = variables[varRef.name] {
                if enumVarTypes[varRef.name] != nil {
                    emitLoadX(reg: 0, offset: off)
                } else {
                    emitLoad(reg: 0, offset: off)
                }
            } else {
                emit(0x52800000)
            }
        } else if let bin = node as? BinaryOp {
            genExpr(bin.left)
            emit(0xF81F0FE0)  // str x0, [sp, #-16]!
            genExpr(bin.right)
            emit(0x2A0003E1)  // mov w1, w0
            emit(0xF84107E0)  // ldr x0, [sp], #16

            let op = bin.op
            if op == "+" { emit(0x0B010000) }
            else if op == "-" { emit(0x4B010000) }
            else if op == "*" { emit(0x1B017C00) }
            else if op == "/" { emit(0x1AC10C00) }
            else if op == "%" {
                emit(0x1AC10C02)
                emit(0x1B018040)
            }
            else if op == "==" { emit(0x6B01001F); emit(0x1A9F17E0) }
            else if op == "!=" { emit(0x6B01001F); emit(0x1A9F07E0) }
            else if op == "<" { emit(0x6B01001F); emit(0x1A9FB7E0) }
            else if op == ">" { emit(0x6B01001F); emit(0x1A9FC7E0) }
        } else if let idx = node as? IndexAccess, let ref = idx.array as? VarRef, enums[ref.name] != nil {
            // Enum access: Color["Red"] -> load pointer to "Red" string
            if let lit = idx.index as? Literal, let key = lit.value as? String {
                let strOff = addString(key)
                emitAdrpAdd(reg: 0, dataOffset: strOff)
            }
        } else if let idx = node as? IndexAccess, let ref = idx.array as? VarRef, arrays[ref.name] != nil {
            // Array index access
            let isStr = arrays[ref.name]!.elemType == .stringArray
            genArrayIndexLoad(name: ref.name, index: idx.index, isString: isStr)
        } else if let idx = node as? IndexAccess, let innerIdx = idx.array as? IndexAccess,
                  let ref = innerIdx.array as? VarRef, arrays[ref.name]?.elemType == .nestedArray {
            // Nested array: matrix[0][1]
            if let outerLit = innerIdx.index as? Literal, let outerI = outerLit.value as? Int {
                let subName = "\(ref.name)_\(outerI)"
                if arrays[subName] != nil {
                    genArrayIndexLoad(name: subName, index: idx.index, isString: false)
                }
            }
        } else if let call = node as? FuncCall {
            if functions[call.name] != nil {
                for (i, arg) in call.args.prefix(8).enumerated() {
                    genExpr(arg)
                    emit(0x2A0003E0 | UInt32(19 + i))
                }
                for i in 0..<min(call.args.count, 8) {
                    emit(0x2A0003E0 | UInt32(i) | (UInt32(19 + i) << 16))
                }
                addBranch(to: "_\(call.name)", type: .bl)
            }
        }
    }

    private func emitPrintFullArray(name: String, info: (offset: Int, count: Int, elemType: VarType)) {
        if info.elemType == .stringArray {
            // Build string: [elem1, elem2, ...] at compile time by reading string offsets
            // We stored string pointers but need the actual strings for compile-time formatting
            // Instead, emit runtime printing: "[" then each elem then "]"
            let lbracket = addString("[")
            emitWriteSyscall(dataOffset: lbracket, length: 1)
            for i in 0..<info.count {
                if i > 0 {
                    let comma = addString(", ")
                    emitWriteSyscall(dataOffset: comma, length: 2)
                }
                emitLoadX(reg: 0, offset: info.offset + i * 8)
                emitPrintCStringNoNewline()
            }
            let rbracket = addString("]\n")
            emitWriteSyscall(dataOffset: rbracket, length: 2)
        } else if info.elemType == .nestedArray {
            let lbracket = addString("[")
            emitWriteSyscall(dataOffset: lbracket, length: 1)
            for i in 0..<info.count {
                if i > 0 {
                    let comma = addString(", ")
                    emitWriteSyscall(dataOffset: comma, length: 2)
                }
                let subName = "\(name)_\(i)"
                if let subInfo = arrays[subName] {
                    emitPrintFullArrayInline(name: subName, info: subInfo)
                }
            }
            let rbracket = addString("]\n")
            emitWriteSyscall(dataOffset: rbracket, length: 2)
        } else {
            // Integer array: build at compile time from literals if possible
            // For runtime, emit "[" then print_int for each, then "]"
            let lbracket = addString("[")
            emitWriteSyscall(dataOffset: lbracket, length: 1)
            for i in 0..<info.count {
                if i > 0 {
                    let comma = addString(", ")
                    emitWriteSyscall(dataOffset: comma, length: 2)
                }
                emitLoad(reg: 0, offset: info.offset + i * 8)
                emitPrintIntNoNewline()
            }
            let rbracket = addString("]\n")
            emitWriteSyscall(dataOffset: rbracket, length: 2)
        }
    }

    private func emitPrintFullArrayInline(name: String, info: (offset: Int, count: Int, elemType: VarType)) {
        // Print array inline (no trailing newline) - for nested arrays
        let lbracket = addString("[")
        emitWriteSyscall(dataOffset: lbracket, length: 1)
        for i in 0..<info.count {
            if i > 0 {
                let comma = addString(", ")
                emitWriteSyscall(dataOffset: comma, length: 2)
            }
            emitLoad(reg: 0, offset: info.offset + i * 8)
            emitPrintIntNoNewline()
        }
        let rbracket = addString("]")
        emitWriteSyscall(dataOffset: rbracket, length: 1)
    }

    private func genArrayIndexLoad(name: String, index: ASTNode, isString: Bool) {
        guard let info = arrays[name] else { return }
        // Load index into w1
        if let lit = index as? Literal, let i = lit.value as? Int {
            // Static index
            if isString {
                emitLoadX(reg: 0, offset: info.offset + i * 8)
            } else {
                emitLoad(reg: 0, offset: info.offset + i * 8)
            }
        } else {
            // Dynamic index (variable) - compute offset at runtime
            genExpr(index)
            // w0 has index value
            // Element i is stored at stur offset (info.offset + i*8)
            // Address = x29 - (info.offset + 16) - i*8
            let baseAddr = info.offset + 16
            // w0 * 8 -> w2
            emitMovImm(reg: 1, value: 8)
            emit(0x1B017C02)  // mul w2, w0, w1
            // base = x29 - baseAddr
            emitMovImm(reg: 1, value: baseAddr)
            emit(0xCB0103A1)  // sub x1, x29, x1
            // addr = x1 - x2 (sign-extend w2 to x2 first)
            emit(0x93407C42)  // sxtw x2, w2
            emit(0xCB020021)  // sub x1, x1, x2
            if isString {
                emit(0xF9400020)  // ldr x0, [x1]
            } else {
                emit(0xB9400020)  // ldr w0, [x1]
            }
        }
    }

    /// Print int in w0 without newline (for array formatting)
    private func emitPrintIntNoNewline() {
        // Save registers, call a modified print routine
        // Simpler approach: use stack buffer, convert int to string, write without newline
        // We'll reuse the existing print_int but it always adds newline...
        // Instead, inline a simpler version

        emit(0xA9BF7BFD)  // stp x29, x30, [sp, #-16]!
        emit(0x910003FD)  // mov x29, sp
        emit(0xD100C3FF)  // sub sp, sp, #48

        // Check negative
        emit(0x7100001F)  // cmp w0, #0
        emit(0x540000CA)  // b.ge skip_neg
        emit(0x4B0003E8)  // neg w8, w0
        emit(0x528005A9)  // mov w9, #'-'
        emit(0x390003E9)  // strb w9, [sp]
        emit(0x52800029)  // mov w9, #1
        emit(0x14000003)  // b continue
        // skip_neg:
        emit(0x2A0003E8)  // mov w8, w0
        emit(0x52800009)  // mov w9, #0
        // continue:
        emit(0x910083EA)  // add x10, sp, #32
        emit(0x5280014B)  // mov w11, #10

        let loopOff = code.count
        emit(0x1ACB090C)  // udiv w12, w8, w11
        emit(0x1B0BA18C)  // msub w12, w12, w11, w8
        emit(0x1100C18C)  // add w12, w12, #'0'
        emit(0x381FFD4C)  // strb w12, [x10, #-1]!
        emit(0x1ACB0908)  // udiv w8, w8, w11
        emit(0x7100011F)  // cmp w8, #0
        let brOff = code.count
        emit(0x54000001)  // b.ne loop
        let d = (loopOff - brOff) / 4
        let dd = UInt32(bitPattern: Int32(d))
        code[brOff] = UInt8((0x54000001 | ((dd & 0x7FFFF) << 5)) & 0xFF)
        code[brOff+1] = UInt8(((0x54000001 | ((dd & 0x7FFFF) << 5)) >> 8) & 0xFF)
        code[brOff+2] = UInt8(((0x54000001 | ((dd & 0x7FFFF) << 5)) >> 16) & 0xFF)
        code[brOff+3] = UInt8(((0x54000001 | ((dd & 0x7FFFF) << 5)) >> 24) & 0xFF)

        // Copy minus if needed
        emit(0x7100013F)  // cmp w9, #0
        emit(0x54000060)  // b.eq skip_copy
        emit(0x394003ED)  // ldrb w13, [sp]
        emit(0x381FFD4D)  // strb w13, [x10, #-1]!

        // Length and write
        emit(0x910083EE)  // add x14, sp, #32 (fix: this is correct direction)
        code[code.count-4] = 0xEE; code[code.count-3] = 0x83; code[code.count-2] = 0x00; code[code.count-1] = 0x91
        emit(0xCB0A01C2)  // sub x2, x14, x10
        emit(0xAA0A03E1)  // mov x1, x10
        emit(0xD2800020)  // mov x0, #1
        emit(0xD2800090)  // movz x16, #4
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16
        emit(0xD4001001)  // svc #0x80

        emit(0x9100C3FF)  // add sp, sp, #48
        emit(0xA8C17BFD)  // ldp x29, x30, [sp], #16
    }

    /// Print C string in x0 without newline
    private func emitPrintCStringNoNewline() {
        emit(0xAA0003E1)  // mov x1, x0
        emit(0xAA0003E2)  // mov x2, x0
        let scanLoop = code.count
        emit(0x39400048)  // ldrb w8, [x2]
        emit(0x91000442)  // add x2, x2, #1
        emit(0x7100011F)  // cmp w8, #0
        let branchOff = code.count
        emit(0x54000001)  // b.ne
        let delta = (scanLoop - branchOff) / 4
        let d2 = UInt32(bitPattern: Int32(delta))
        code[branchOff] = UInt8((0x54000001 | ((d2 & 0x7FFFF) << 5)) & 0xFF)
        code[branchOff+1] = UInt8(((0x54000001 | ((d2 & 0x7FFFF) << 5)) >> 8) & 0xFF)
        code[branchOff+2] = UInt8(((0x54000001 | ((d2 & 0x7FFFF) << 5)) >> 16) & 0xFF)
        code[branchOff+3] = UInt8(((0x54000001 | ((d2 & 0x7FFFF) << 5)) >> 24) & 0xFF)

        emit(0xCB010042)  // sub x2, x2, x1
        emit(0xD1000442)  // sub x2, x2, #1
        emit(0xD2800020)  // mov x0, #1
        emit(0xD2800090)  // movz x16, #4
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16
        emit(0xD4001001)  // svc #0x80
    }

    private func isEnumExpr(_ node: ASTNode) -> Bool {
        if let varRef = node as? VarRef {
            return enumVarTypes[varRef.name] != nil || enums[varRef.name] != nil
        }
        if let idx = node as? IndexAccess, let ref = idx.array as? VarRef {
            return enums[ref.name] != nil
        }
        return false
    }

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
                let off = addDouble(dblVal)
                emitAdrpAdd(reg: 8, dataOffset: off)
                emit(0xFD400100)  // ldr d0, [x8]
            } else if let intVal = literal.value as? Int {
                // Int literal in float context — convert via scvtf
                emitMovImm(reg: 0, value: intVal)
                emit(0x1E620000)  // scvtf d0, w0
            }
        } else if let varRef = node as? VarRef {
            if floatVars.contains(varRef.name), let off = variables[varRef.name] {
                emitLoadD(reg: 0, offset: off)
            } else if let off = variables[varRef.name] {
                // Int variable in float context — load and convert
                emitLoad(reg: 0, offset: off)
                emit(0x1E620000)  // scvtf d0, w0
            }
        } else if let binaryOp = node as? BinaryOp {
            genFloatExpr(binaryOp.left)
            emit(0xFC1F0FE0)  // str d0, [sp, #-16]!
            genFloatExpr(binaryOp.right)
            emit(0x1E604001)  // fmov d1, d0
            emit(0xFC4107E0)  // ldr d0, [sp], #16

            let op = binaryOp.op
            if op == "+" { emit(0x1E612800) }       // fadd d0, d0, d1
            else if op == "-" { emit(0x1E613800) }  // fsub d0, d0, d1
            else if op == "*" { emit(0x1E610800) }  // fmul d0, d0, d1
            else if op == "/" { emit(0x1E611800) }  // fdiv d0, d0, d1
            else if op == "%" {
                // Float mod: d0 = d0 - trunc(d0/d1) * d1
                emit(0x1E611802)  // fdiv d2, d0, d1
                emit(0x1E65C042)  // frintz d2, d2
                emit(0x1F418040)  // fmsub d0, d2, d1, d0
            }
        } else if let unaryOp = node as? UnaryOp {
            genFloatExpr(unaryOp.operand)
            if unaryOp.op == "-" || unaryOp.op == "neg" {
                emit(0x1E614000)  // fneg d0, d0
            }
        }
    }

    // MARK: - Instruction Helpers

    private func emit(_ inst: UInt32) {
        code.append(UInt8(inst & 0xFF))
        code.append(UInt8((inst >> 8) & 0xFF))
        code.append(UInt8((inst >> 16) & 0xFF))
        code.append(UInt8((inst >> 24) & 0xFF))
    }

    private func emitMovImm(reg: Int, value: Int) {
        let v = UInt32(bitPattern: Int32(truncatingIfNeeded: value))
        if value >= 0 && value < 65536 {
            emit(0x52800000 | (v << 5) | UInt32(reg))
        } else if value >= -65536 && value < 0 {
            emit(0x12800000 | ((~v & 0xFFFF) << 5) | UInt32(reg))
        } else {
            emit(0x52800000 | ((v & 0xFFFF) << 5) | UInt32(reg))
            emit(0x72A00000 | (((v >> 16) & 0xFFFF) << 5) | UInt32(reg))
        }
    }

    private func emitStore(reg: Int, offset: Int) {
        let off9 = UInt32(bitPattern: Int32(-offset - 16)) & 0x1FF
        emit(0xB8000000 | (off9 << 12) | (29 << 5) | UInt32(reg))
    }

    private func emitLoad(reg: Int, offset: Int) {
        let off9 = UInt32(bitPattern: Int32(-offset - 16)) & 0x1FF
        emit(0xB8400000 | (off9 << 12) | (29 << 5) | UInt32(reg))
    }

    private func emitStoreX(reg: Int, offset: Int) {
        // stur x{reg}, [x29, #-offset-16] (64-bit store for pointers)
        let off9 = UInt32(bitPattern: Int32(-offset - 16)) & 0x1FF
        emit(0xF8000000 | (off9 << 12) | (29 << 5) | UInt32(reg))
    }

    private func emitLoadX(reg: Int, offset: Int) {
        // ldur x{reg}, [x29, #-offset-16] (64-bit load for pointers)
        let off9 = UInt32(bitPattern: Int32(-offset - 16)) & 0x1FF
        emit(0xF8400000 | (off9 << 12) | (29 << 5) | UInt32(reg))
    }

    private func emitStoreD(reg: Int, offset: Int) {
        // stur d{reg}, [x29, #-offset-16] (64-bit float store)
        let off9 = UInt32(bitPattern: Int32(-offset - 16)) & 0x1FF
        emit(0xFC000000 | (off9 << 12) | (29 << 5) | UInt32(reg))
    }

    private func emitLoadD(reg: Int, offset: Int) {
        // ldur d{reg}, [x29, #-offset-16] (64-bit float load)
        let off9 = UInt32(bitPattern: Int32(-offset - 16)) & 0x1FF
        emit(0xFC400000 | (off9 << 12) | (29 << 5) | UInt32(reg))
    }

    private func emitAdrpAdd(reg: Int, dataOffset: Int) {
        emit(0x90000000 | UInt32(reg))
        emit(0x91000000 | (UInt32(reg) << 5) | UInt32(reg) | (UInt32(dataOffset & 0xFFF) << 10))
    }

    private func addBranch(to label: String, type: BranchType) {
        pendingBranches.append((offset: code.count, label: label, type: type))
        emit(0x14000000)
    }

    private func resolveBranches() {
        for b in pendingBranches {
            guard let target = labelOffsets[b.label] else { continue }
            let delta = (target - b.offset) / 4
            let d = UInt32(bitPattern: Int32(delta))

            var inst: UInt32
            switch b.type {
            case .b:   inst = 0x14000000 | (d & 0x3FFFFFF)
            case .bl:  inst = 0x94000000 | (d & 0x3FFFFFF)
            case .beq: inst = 0x54000000 | ((d & 0x7FFFF) << 5) | 0
            case .bne: inst = 0x54000000 | ((d & 0x7FFFF) << 5) | 1
            case .bge: inst = 0x54000000 | ((d & 0x7FFFF) << 5) | 10
            case .ble: inst = 0x54000000 | ((d & 0x7FFFF) << 5) | 13
            case .bgt: inst = 0x54000000 | ((d & 0x7FFFF) << 5) | 12
            case .blt: inst = 0x54000000 | ((d & 0x7FFFF) << 5) | 11
            }

            code[b.offset] = UInt8(inst & 0xFF)
            code[b.offset+1] = UInt8((inst >> 8) & 0xFF)
            code[b.offset+2] = UInt8((inst >> 16) & 0xFF)
            code[b.offset+3] = UInt8((inst >> 24) & 0xFF)
        }
    }

    // MARK: - Data Section

    private func addString(_ s: String) -> Int {
        if let off = stringOffsets[s] { return off }
        let off = data.count
        stringOffsets[s] = off
        data.append(contentsOf: s.utf8)
        data.append(0)
        while data.count % 8 != 0 { data.append(0) }
        return off
    }

    // MARK: - Mach-O Generation (Static binary with __PAGEZERO)

    private func writeMachO(to path: String, mainOffset: Int) throws {
        var binary = [UInt8]()

        while code.count % 16 != 0 { code.append(0x00) }
        while data.count % 16 != 0 { data.append(0x00) }

        let segmentCmdSize = 72
        let sectionSize = 80
        let dylinkerCmdSize = 44  // 12 bytes header + 32 bytes path
        let buildVersionCmdSize = 24  // LC_BUILD_VERSION without tools
        let symtabCmdSize = 24  // LC_SYMTAB
        let chainedFixupsCmdSize = 16  // LC_DYLD_CHAINED_FIXUPS
        let exportTrieCmdSize = 16  // LC_DYLD_EXPORTS_TRIE
        let mainCmdSize = 24  // LC_MAIN

        // Load commands: __PAGEZERO, __TEXT, __LINKEDIT, LC_LOAD_DYLINKER, LC_BUILD_VERSION, LC_SYMTAB, LC_DYLD_CHAINED_FIXUPS, LC_DYLD_EXPORTS_TRIE, LC_MAIN
        let ncmds = 9
        let sizeofcmds = segmentCmdSize + (segmentCmdSize + 2*sectionSize) + segmentCmdSize + dylinkerCmdSize + buildVersionCmdSize + symtabCmdSize + chainedFixupsCmdSize + exportTrieCmdSize + mainCmdSize

        let pageSize: UInt64 = 0x4000
        let textStart: UInt64 = 0x100000000

        // Page-align everything
        let textFileOff: UInt64 = 0
        let codeFileOffset = Int(pageSize)  // Code starts at second page
        let codeVMAddr = textStart + UInt64(codeFileOffset)
        let codeSize = code.count

        let dataFileOffset = codeFileOffset + ((codeSize + 15) / 16) * 16
        let dataVMAddr = textStart + UInt64(dataFileOffset)

        let textEndOffset = dataFileOffset + data.count
        let textFileSize = ((textEndOffset + Int(pageSize) - 1) / Int(pageSize)) * Int(pageSize)
        let textVMSize = UInt64(textFileSize)

        // LINKEDIT segment (minimal, at end - needed for codesign)
        let linkeditFileOff = textFileSize
        let linkeditFileSize = Int(pageSize)  // One page for codesign data
        let linkeditVMAddr = textStart + UInt64(linkeditFileOff)
        let linkeditVMSize: UInt64 = pageSize

        // Fix up ADRP/ADD for data references
        let dataPageOffset = UInt32(dataVMAddr & 0xFFF)
        for i in stride(from: 0, to: code.count - 8, by: 4) {
            let inst = UInt32(code[i]) | (UInt32(code[i+1]) << 8) | (UInt32(code[i+2]) << 16) | (UInt32(code[i+3]) << 24)
            if (inst & 0x9F000000) == 0x90000000 {  // ADRP
                let pc = codeVMAddr + UInt64(i)
                let pcPage = pc & ~0xFFF
                let targetPage = dataVMAddr & ~0xFFF
                let pageDelta = Int64(targetPage) - Int64(pcPage)
                let immhi = UInt32((pageDelta >> 14) & 0x7FFFF)
                let immlo = UInt32((pageDelta >> 12) & 0x3)
                let rd = inst & 0x1F
                let newInst = 0x90000000 | (immlo << 29) | (immhi << 5) | rd
                code[i] = UInt8(newInst & 0xFF)
                code[i+1] = UInt8((newInst >> 8) & 0xFF)
                code[i+2] = UInt8((newInst >> 16) & 0xFF)
                code[i+3] = UInt8((newInst >> 24) & 0xFF)

                // Fix up the following ADD instruction
                let addInst = UInt32(code[i+4]) | (UInt32(code[i+5]) << 8) | (UInt32(code[i+6]) << 16) | (UInt32(code[i+7]) << 24)
                if (addInst & 0xFF800000) == 0x91000000 {  // ADD (immediate)
                    let existingOff = (addInst >> 10) & 0xFFF
                    let newOff = (dataPageOffset + existingOff) & 0xFFF
                    let newAddInst = (addInst & 0xFFC003FF) | (newOff << 10)
                    code[i+4] = UInt8(newAddInst & 0xFF)
                    code[i+5] = UInt8((newAddInst >> 8) & 0xFF)
                    code[i+6] = UInt8((newAddInst >> 16) & 0xFF)
                    code[i+7] = UInt8((newAddInst >> 24) & 0xFF)
                }
            }
        }

        // Mach-O header
        binary.append(contentsOf: u32(0xFEEDFACF))
        binary.append(contentsOf: u32(0x0100000C))
        binary.append(contentsOf: u32(0x00000000))
        binary.append(contentsOf: u32(0x00000002))
        binary.append(contentsOf: u32(UInt32(ncmds)))
        binary.append(contentsOf: u32(UInt32(sizeofcmds)))
        binary.append(contentsOf: u32(0x00200085))  // MH_NOUNDEFS|MH_DYLDLINK|MH_TWOLEVEL|MH_PIE
        binary.append(contentsOf: u32(0x00000000))

        // LC_SEGMENT_64 __PAGEZERO
        binary.append(contentsOf: u32(0x19))
        binary.append(contentsOf: u32(UInt32(segmentCmdSize)))
        binary.append(contentsOf: padString("__PAGEZERO", to: 16))
        binary.append(contentsOf: u64(0))
        binary.append(contentsOf: u64(textStart))  // vmsize = 4GB
        binary.append(contentsOf: u64(0))
        binary.append(contentsOf: u64(0))
        binary.append(contentsOf: u32(0))
        binary.append(contentsOf: u32(0))
        binary.append(contentsOf: u32(0))
        binary.append(contentsOf: u32(0))

        // LC_SEGMENT_64 __TEXT
        binary.append(contentsOf: u32(0x19))
        binary.append(contentsOf: u32(UInt32(segmentCmdSize + 2*sectionSize)))
        binary.append(contentsOf: padString("__TEXT", to: 16))
        binary.append(contentsOf: u64(textStart))
        binary.append(contentsOf: u64(textVMSize))
        binary.append(contentsOf: u64(textFileOff))
        binary.append(contentsOf: u64(UInt64(textFileSize)))
        binary.append(contentsOf: u32(5))  // VM_PROT_READ | VM_PROT_EXECUTE
        binary.append(contentsOf: u32(5))
        binary.append(contentsOf: u32(2))  // 2 sections
        binary.append(contentsOf: u32(0))

        // __text section
        binary.append(contentsOf: padString("__text", to: 16))
        binary.append(contentsOf: padString("__TEXT", to: 16))
        binary.append(contentsOf: u64(codeVMAddr))
        binary.append(contentsOf: u64(UInt64(codeSize)))
        binary.append(contentsOf: u32(UInt32(codeFileOffset)))
        binary.append(contentsOf: u32(4))
        binary.append(contentsOf: u32(0))
        binary.append(contentsOf: u32(0))
        binary.append(contentsOf: u32(0x80000400))
        binary.append(contentsOf: u32(0))
        binary.append(contentsOf: u32(0))
        binary.append(contentsOf: u32(0))

        // __cstring section
        binary.append(contentsOf: padString("__cstring", to: 16))
        binary.append(contentsOf: padString("__TEXT", to: 16))
        binary.append(contentsOf: u64(dataVMAddr))
        binary.append(contentsOf: u64(UInt64(data.count)))
        binary.append(contentsOf: u32(UInt32(dataFileOffset)))
        binary.append(contentsOf: u32(0))
        binary.append(contentsOf: u32(0))
        binary.append(contentsOf: u32(0))
        binary.append(contentsOf: u32(0x00000002))
        binary.append(contentsOf: u32(0))
        binary.append(contentsOf: u32(0))
        binary.append(contentsOf: u32(0))

        // LC_SEGMENT_64 __LINKEDIT
        binary.append(contentsOf: u32(0x19))
        binary.append(contentsOf: u32(UInt32(segmentCmdSize)))
        binary.append(contentsOf: padString("__LINKEDIT", to: 16))
        binary.append(contentsOf: u64(linkeditVMAddr))
        binary.append(contentsOf: u64(linkeditVMSize))
        binary.append(contentsOf: u64(UInt64(linkeditFileOff)))
        binary.append(contentsOf: u64(UInt64(linkeditFileSize)))
        binary.append(contentsOf: u32(1))  // VM_PROT_READ
        binary.append(contentsOf: u32(1))
        binary.append(contentsOf: u32(0))  // no sections
        binary.append(contentsOf: u32(0))

        // LC_LOAD_DYLINKER
        binary.append(contentsOf: u32(0x0E))
        binary.append(contentsOf: u32(UInt32(dylinkerCmdSize)))
        binary.append(contentsOf: u32(12))  // name offset
        binary.append(contentsOf: padString("/usr/lib/dyld", to: 32))

        // LC_BUILD_VERSION (macOS 11.0)
        binary.append(contentsOf: u32(0x32))  // LC_BUILD_VERSION
        binary.append(contentsOf: u32(UInt32(buildVersionCmdSize)))
        binary.append(contentsOf: u32(1))  // platform = MACOS
        binary.append(contentsOf: u32(0x000B0000))  // minos = 11.0.0
        binary.append(contentsOf: u32(0x000E0000))  // sdk = 14.0.0
        binary.append(contentsOf: u32(0))  // ntools = 0

        // LC_SYMTAB (required by dyld, can be empty)
        binary.append(contentsOf: u32(0x02))  // LC_SYMTAB
        binary.append(contentsOf: u32(UInt32(symtabCmdSize)))
        binary.append(contentsOf: u32(0))  // symoff
        binary.append(contentsOf: u32(0))  // nsyms
        binary.append(contentsOf: u32(0))  // stroff
        binary.append(contentsOf: u32(0))  // strsize

        // LC_DYLD_CHAINED_FIXUPS - points to fixup data in LINKEDIT
        let chainedFixupsOffset = linkeditFileOff  // Start of LINKEDIT
        let chainedFixupsSize = 48  // Minimal header
        binary.append(contentsOf: u32(0x80000034))  // LC_DYLD_CHAINED_FIXUPS
        binary.append(contentsOf: u32(UInt32(chainedFixupsCmdSize)))
        binary.append(contentsOf: u32(UInt32(chainedFixupsOffset)))
        binary.append(contentsOf: u32(UInt32(chainedFixupsSize)))

        // LC_DYLD_EXPORTS_TRIE - points to export trie in LINKEDIT
        let exportTrieOffset = chainedFixupsOffset + chainedFixupsSize
        let exportTrieSize = 8  // Minimal empty trie
        binary.append(contentsOf: u32(0x80000033))  // LC_DYLD_EXPORTS_TRIE
        binary.append(contentsOf: u32(UInt32(exportTrieCmdSize)))
        binary.append(contentsOf: u32(UInt32(exportTrieOffset)))
        binary.append(contentsOf: u32(UInt32(exportTrieSize)))

        // LC_MAIN
        binary.append(contentsOf: u32(0x80000028))
        binary.append(contentsOf: u32(UInt32(mainCmdSize)))
        binary.append(contentsOf: u64(UInt64(codeFileOffset + mainOffset)))
        binary.append(contentsOf: u64(0))

        // Pad to code start
        while binary.count < codeFileOffset {
            binary.append(0)
        }

        binary.append(contentsOf: code)

        // Pad between code and data if needed
        while binary.count < dataFileOffset {
            binary.append(0)
        }

        binary.append(contentsOf: data)

        // Pad to page boundary for __TEXT segment
        while binary.count < textFileSize {
            binary.append(0)
        }

        // __LINKEDIT data: chained fixups
        // dyld_chained_fixups_header (28 bytes)
        binary.append(contentsOf: u32(0))   // fixups_version
        binary.append(contentsOf: u32(28))  // starts_offset -> points to starts_in_image
        binary.append(contentsOf: u32(44))  // imports_offset (after starts - 28 + 16)
        binary.append(contentsOf: u32(44))  // symbols_offset (same - empty)
        binary.append(contentsOf: u32(0))   // imports_count = 0
        binary.append(contentsOf: u32(1))   // imports_format (DYLD_CHAINED_IMPORT)
        binary.append(contentsOf: u32(0))   // symbols_format

        // dyld_chained_starts_in_image at offset 28 (16 bytes for 3 segments)
        // We have 3 segments: __PAGEZERO, __TEXT, __LINKEDIT
        binary.append(contentsOf: u32(3))   // seg_count = 3
        binary.append(contentsOf: u32(0))   // seg_info_offset[0] = 0 (__PAGEZERO, no fixups)
        binary.append(contentsOf: u32(0))   // seg_info_offset[1] = 0 (__TEXT, no fixups)
        binary.append(contentsOf: u32(0))   // seg_info_offset[2] = 0 (__LINKEDIT, no fixups)

        // Pad to 48 bytes total for chained fixups section
        while binary.count < textFileSize + 48 {
            binary.append(0)
        }

        // Export trie (minimal valid trie - 8 bytes)
        binary.append(0x00)  // terminal size = 0 (no export info at root)
        binary.append(0x00)  // child count = 0 (no children)
        // Pad to 8 bytes
        while binary.count < textFileSize + 48 + 8 {
            binary.append(0)
        }

        // Pad rest of __LINKEDIT segment (needed for codesign)
        while binary.count < textFileSize + linkeditFileSize {
            binary.append(0)
        }

        let fileData = Data(binary)
        try fileData.write(to: URL(fileURLWithPath: path))
        chmod(path, 0o755)
    }

    private func u32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    private func u64(_ v: UInt64) -> [UInt8] {
        var r = [UInt8]()
        for i in 0..<8 { r.append(UInt8((v >> (i*8)) & 0xFF)) }
        return r
    }

    private func padString(_ s: String, to len: Int) -> [UInt8] {
        var r = Array(s.utf8)
        while r.count < len { r.append(0) }
        return r
    }
}
