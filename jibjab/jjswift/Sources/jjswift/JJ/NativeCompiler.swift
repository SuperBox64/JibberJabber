/// JibJab Native Compiler - Compiles JJ directly to ARM64 Mach-O binary
/// Uses direct syscalls for I/O - no external library dependencies

import Foundation

class NativeCompiler {
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

    enum BranchType { case b, beq, bne, bge, ble, bl }

    func compile(_ program: Program, outputPath: String) throws {
        code = []
        data = []
        variables = [:]
        functions = [:]
        labelOffsets = [:]
        pendingBranches = []
        stringOffsets = [:]
        stackOffset = 0

        // Generate helper: print_int routine (converts integer to string and prints)
        printIntOffset = code.count
        genPrintIntRoutine()

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
        emit(0xD10103FF)  // sub sp, sp, #64

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
        emit(0xD1008FFF)  // sub sp, sp, #35 (buffer space)

        // Check if negative
        emit(0x7100001F)  // cmp w0, #0
        emit(0x5400014A)  // b.ge skip_neg (if >= 0, skip)

        // Negate for processing
        emit(0x4B0003E8)  // neg w8, w0
        emit(0x52800569)  // mov w9, #'-' (45)
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

        emit(0x1B0B8D8C)  // msub w12, w12, w11, w3 -> msub w12, w12, w11, w8
        code[code.count-4] = 0x0C
        code[code.count-3] = 0x21
        code[code.count-2] = 0x0B
        code[code.count-1] = 0x1B

        emit(0x1100C18C)  // add w12, w12, #'0' (48)
        emit(0x381FF14C)  // strb w12, [x10, #-1]!
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
        emit(0x540000A0)  // b.eq skip_copy
        emit(0x390003ED)  // ldrb w13, [sp] (minus sign)
        emit(0x381FF14D)  // strb w13, [x10, #-1]!
        // skip_copy:

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
        emit(0x91008FFF)  // add sp, sp, #35
        emit(0xA8C17BFD)  // ldp x29, x30, [sp], #16
        emit(0xD65F03C0)  // ret
    }

    // MARK: - Code Generation

    private func genFunc(_ node: FuncDef) {
        currentFunc = node.name
        labelOffsets["_\(node.name)"] = code.count

        emit(0xA9BF7BFD)  // stp x29, x30, [sp, #-16]!
        emit(0xA9BF53F3)  // stp x19, x20, [sp, #-16]!
        emit(0x910003FD)  // mov x29, sp
        emit(0xD10103FF)  // sub sp, sp, #64

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
        emit(0x910103FF)  // add sp, sp, #64
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
        }
    }

    private func genPrint(_ node: PrintStmt) {
        if let lit = node.expr as? Literal, let str = lit.value as? String {
            // Print string using write syscall
            let strWithNewline = str + "\n"
            let strOff = addString(strWithNewline)
            let strLen = strWithNewline.utf8.count

            // x0 = fd (1), x1 = buf, x2 = count, x16 = 4 (SYS_write)
            emit(0xD2800020)  // mov x0, #1 (stdout)
            emitAdrpAdd(reg: 1, dataOffset: strOff)
            emitMovImm(reg: 2, value: strLen)
            emit(0xD2800090)  // mov x16, #0x2000004 (SYS_write with UNIX class)
        emit(0xF2A04010)  // movk x16, #0x200, lsl #16
            emit(0xD4001001)  // svc #0x80
        } else {
            // Print integer - call print_int routine
            genExpr(node.expr)
            // bl print_int
            let delta = (printIntOffset - code.count) / 4
            let d = UInt32(bitPattern: Int32(delta))
            emit(0x94000000 | (d & 0x3FFFFFF))
        }
    }

    private func genVarDecl(_ node: VarDecl) {
        genExpr(node.value)
        if variables[node.name] == nil {
            variables[node.name] = stackOffset
            stackOffset += 8
        }
        emitStore(reg: 0, offset: variables[node.name]!)
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
            genExpr(bin.left)
            emit(0x2A0003E9)  // mov w9, w0
            genExpr(bin.right)
            emit(0x6B00013F)  // cmp w9, w0

            let op = bin.op
            if op == "==" { addBranch(to: elseLabel, type: .bne) }
            else if op == "!=" { addBranch(to: elseLabel, type: .beq) }
            else if op == "<" { addBranch(to: elseLabel, type: .bge) }
            else if op == ">" { addBranch(to: elseLabel, type: .ble) }
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
                emitLoad(reg: 0, offset: off)
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

        // Load commands: __PAGEZERO, __TEXT, __LINKEDIT, LC_LOAD_DYLINKER, LC_MAIN
        let ncmds = 5
        let sizeofcmds = segmentCmdSize + (segmentCmdSize + 2*sectionSize) + segmentCmdSize + dylinkerCmdSize + 24

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

        // LINKEDIT segment (empty, at end)
        let linkeditFileOff = textFileSize
        let linkeditFileSize = 0
        let linkeditVMAddr = textStart + UInt64(linkeditFileOff)
        let linkeditVMSize: UInt64 = 0

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
        binary.append(contentsOf: u32(0x00000085))  // MH_NOUNDEFS|MH_DYLDLINK|MH_TWOLEVEL (no PIE)
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

        // LC_MAIN
        binary.append(contentsOf: u32(0x80000028))
        binary.append(contentsOf: u32(24))
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
