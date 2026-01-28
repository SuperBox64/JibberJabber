"""
JibJab Native Compiler - Compiles JJ directly to ARM64 Mach-O binary
Uses direct syscalls for I/O - no external library dependencies
"""

import os
import json
import struct
from pathlib import Path
from enum import Enum
from .ast import (
    Program, PrintStmt, VarDecl, LoopStmt, IfStmt, ReturnStmt,
    FuncDef, FuncCall, BinaryOp, UnaryOp, Literal, VarRef,
    EnumDef, IndexAccess, ArrayLiteral, TupleLiteral, DictLiteral
)


class BranchType(Enum):
    B = 'b'
    BL = 'bl'
    BEQ = 'beq'
    BNE = 'bne'
    BGE = 'bge'
    BLE = 'ble'
    BGT = 'bgt'
    BLT = 'blt'


class NativeCompiler:
    def __init__(self):
        self.code = bytearray()
        self.data = bytearray()
        self.variables = {}
        self.functions = {}
        self.label_offsets = {}
        self.pending_branches = []
        self.string_offsets = {}
        self.stack_offset = 0
        self.current_func = None
        self.print_int_offset = 0
        self.enums = {}  # enum name -> list of case names
        self.enum_var_types = {}  # var name -> "enum" if holds string ptr
        self.arrays = {}  # name -> {offset, count, elem_type}
        self.tuples = {}  # name -> {offset, types: [str]}
        self.dicts = {}   # name -> [{key, type, offset, sub_array}]
        self.print_float_offset = 0
        self.float_vars = set()
        self._load_config()

    def _load_config(self):
        """Load ARM64 instruction config from shared JSON"""
        config_path = Path(__file__).parent.parent.parent / 'common' / 'arm64.json'
        with open(config_path, 'r') as f:
            self.config = json.load(f)
        self.macho = self.config['macho']
        self.syscalls = self.config['syscalls']
        self.inst = self.config['instructions']
        self.print_int_cfg = self.config['printInt']

    def _hex(self, val):
        """Convert hex string or int to int"""
        if isinstance(val, str):
            return int(val, 16)
        return val

    def compile(self, program, output_path):
        """Compile JJ program to ARM64 Mach-O binary"""
        self.code = bytearray()
        self.data = bytearray()
        self.variables = {}
        self.functions = {}
        self.label_offsets = {}
        self.pending_branches = []
        self.string_offsets = {}
        self.stack_offset = 0
        self.enums = {}
        self.enum_var_types = {}
        self.arrays = {}
        self.tuples = {}
        self.dicts = {}
        self.float_vars = set()

        # Generate helper: print_int routine
        self.print_int_offset = len(self.code)
        self._gen_print_int_routine()
        self.print_float_offset = len(self.code)
        self._gen_print_float_routine()

        # Collect function definitions
        for stmt in program.statements:
            if isinstance(stmt, FuncDef):
                self.functions[stmt.name] = {'code_offset': 0, 'def': stmt}

        # Generate user function code
        for stmt in program.statements:
            if isinstance(stmt, FuncDef):
                self.functions[stmt.name]['code_offset'] = len(self.code)
                self._gen_func(stmt)

        # Generate _main
        main_offset = len(self.code)
        main_stmts = [s for s in program.statements if not isinstance(s, FuncDef)]

        # Prologue
        self._emit(self._hex(self.inst['prologue']['stp_fp_lr']))
        self._emit(self._hex(self.inst['prologue']['stp_x19_x20']))
        self._emit(self._hex(self.inst['prologue']['mov_fp_sp']))
        self._emit(0xD10403FF)  # sub sp, sp, #256

        self.stack_offset = 16
        self.variables = {}

        for stmt in main_stmts:
            self._gen_stmt(stmt)

        # Epilogue - exit(0) syscall
        self._emit(self._hex(self.inst['moves']['mov_w0_0']))
        self._emit(self._hex(self.inst['syscall']['movz_x16_1']))
        self._emit(self._hex(self.inst['syscall']['movk_x16_0x200_lsl16']))
        self._emit(self._hex(self.inst['syscall']['svc']))

        # Resolve internal branches
        self._resolve_branches()

        # Write Mach-O
        self._write_macho(output_path, main_offset)

    def _gen_print_int_routine(self):
        """Generate print_int routine (converts integer to string and prints)"""
        self._emit(self._hex(self.inst['prologue']['stp_fp_lr']))
        self._emit(self._hex(self.inst['prologue']['mov_fp_sp']))
        self._emit(self._hex(self.inst['prologue']['sub_sp_48']))

        # Check if negative
        self._emit(self._hex(self.inst['compare']['cmp_w0_0']))
        self._emit(self._hex(self.print_int_cfg['bge_skip_neg_offset']))

        # Negate for processing
        self._emit(self._hex(self.inst['moves']['neg_w8_w0']))
        self._emit(self._hex(self.inst['moves']['mov_w9_minus']))
        self._emit(self._hex(self.inst['memory']['strb_w9_sp']))
        self._emit(self._hex(self.inst['moves']['mov_w9_1']))
        self._emit(self._hex(self.print_int_cfg['b_continue_offset']))

        # skip_neg:
        self._emit(self._hex(self.inst['moves']['mov_w8_w0']))
        self._emit(self._hex(self.inst['moves']['mov_w9_0']))

        # continue: w8 = abs value, w9 = prefix length (0 or 1)
        self._emit(self._hex(self.inst['memory']['add_x10_sp_32']))
        self._emit(self._hex(self.inst['moves']['mov_w11_10']))

        # digit_loop:
        loop_offset = len(self.code)
        self._emit(self._hex(self.inst['arithmetic']['udiv_w12_w8_w11']))
        self._emit(self._hex(self.inst['arithmetic']['msub_w12']))
        self._emit(self._hex(self.inst['arithmetic']['add_w12_48']))
        self._emit(self._hex(self.inst['memory']['strb_w12_predec']))
        self._emit(self._hex(self.inst['arithmetic']['udiv_w8_w8_w11']))
        self._emit(self._hex(self.inst['compare']['cmp_w8_0']))
        branch_back = len(self.code)
        self._emit(0x54000001)  # b.ne digit_loop

        # Patch branch
        delta = (loop_offset - branch_back) // 4
        d = delta & 0xFFFFFFFF
        inst = 0x54000001 | ((d & 0x7FFFF) << 5)
        self.code[branch_back:branch_back+4] = struct.pack('<I', inst)

        # Copy minus sign if needed
        self._emit(self._hex(self.inst['compare']['cmp_w9_0']))
        self._emit(self._hex(self.print_int_cfg['beq_skip_copy_offset']))
        self._emit(self._hex(self.inst['memory']['ldrb_w13_sp']))
        self._emit(self._hex(self.inst['memory']['strb_w13_predec']))

        # Calculate length
        self._emit(self._hex(self.inst['memory']['add_x14_sp_32']))
        self._emit(self._hex(self.inst['memory']['sub_x2_x14_x10']))

        # Write syscall
        self._emit(self._hex(self.inst['memory']['add_x14_sp_32']))
        self._emit(0x0B0201CF)  # add w15, w14, w2

        self._emit(self._hex(self.inst['moves']['mov_x1_x10']))
        self._emit(self._hex(self.inst['moves']['mov_x0_1']))
        self._emit(0x11000042)  # add w2, w2, #0 (just use length)
        self._emit(self._hex(self.inst['syscall']['movz_x16_4']))
        self._emit(self._hex(self.inst['syscall']['movk_x16_0x200_lsl16']))
        self._emit(self._hex(self.inst['syscall']['svc']))

        # Print newline
        self._emit(self._hex(self.inst['moves']['mov_w13_newline']))
        self._emit(self._hex(self.inst['memory']['strb_w13_sp']))
        self._emit(self._hex(self.inst['moves']['mov_x1_sp']))
        self._emit(self._hex(self.inst['moves']['mov_x0_1']))
        self._emit(self._hex(self.inst['moves']['mov_x2_1']))
        self._emit(self._hex(self.inst['syscall']['movz_x16_4']))
        self._emit(self._hex(self.inst['syscall']['movk_x16_0x200_lsl16']))
        self._emit(self._hex(self.inst['syscall']['svc']))

        # Epilogue
        self._emit(self._hex(self.inst['epilogue']['add_sp_48']))
        self._emit(self._hex(self.inst['epilogue']['ldp_fp_lr']))
        self._emit(self._hex(self.inst['epilogue']['ret']))

    def _gen_print_float_routine(self):
        """Generate print_float routine (converts double in d0 to string and prints)"""
        # Stack layout (96 bytes):
        #   [sp+0..7]:   saved d0
        #   [sp+16..47]: integer digit buffer (write backwards from sp+48)
        #   [sp+48..63]: fractional digit buffer (write forwards)
        #   [sp+80]:     single char write area

        self._emit(0xA9BF7BFD)  # stp x29, x30, [sp, #-16]!
        self._emit(0x910003FD)  # mov x29, sp
        self._emit(0xD10183FF)  # sub sp, sp, #96

        # Save d0
        self._emit(0xFD0003E0)  # str d0, [sp]

        # Check if negative
        self._emit(0x1E602008)  # fcmp d0, #0.0
        skip_neg_off = len(self.code)
        self._emit(0x54000000)  # b.ge skip_neg (placeholder)

        # === Negative: print '-' and negate ===
        self._emit(0x528005A8)  # mov w8, #45 ('-')
        self._emit(0x390143E8)  # strb w8, [sp, #80]
        self._emit(0xD2800020)  # mov x0, #1
        self._emit(0x910143E1)  # add x1, sp, #80
        self._emit(0xD2800022)  # mov x2, #1
        self._emit(0xD2800090)  # movz x16, #4
        self._emit(0xF2A04010)  # movk x16, #0x200, lsl #16
        self._emit(0xD4001001)  # svc #0x80

        self._emit(0xFD4003E0)  # ldr d0, [sp]
        self._emit(0x1E614000)  # fneg d0, d0
        self._emit(0xFD0003E0)  # str d0, [sp]

        # skip_neg:
        self._patch_cond_branch(skip_neg_off, len(self.code), 0xA)

        # Load abs value
        self._emit(0xFD4003E0)  # ldr d0, [sp]
        self._emit(0x9E780008)  # fcvtzs x8, d0 (integer part)
        self._emit(0x9E620101)  # scvtf d1, x8
        self._emit(0x1E613802)  # fsub d2, d0, d1 (fractional part)

        # Check if whole number
        self._emit(0x1E602048)  # fcmp d2, #0.0
        has_dec_off = len(self.code)
        self._emit(0x54000001)  # b.ne has_decimal (placeholder)

        # === Whole number path ===
        self._emit(0x9100C3EA)  # add x10, sp, #48
        self._emit(0x5280014B)  # mov w11, #10

        whole_loop_off = len(self.code)
        self._emit(0x9ACB090C)  # udiv x12, x8, x11
        self._emit(0x9B0BA18C)  # msub x12, x12, x11, x8
        self._emit(0x1100C18C)  # add w12, w12, #'0'
        self._emit(0x381FFD4C)  # strb w12, [x10, #-1]!
        self._emit(0x9ACB0908)  # udiv x8, x8, x11
        self._emit(0xF100011F)  # cmp x8, #0
        wh_br_off = len(self.code)
        self._emit(0x54000001)  # b.ne wholeLoop
        self._patch_cond_branch(wh_br_off, whole_loop_off, 0x1)

        # Write integer string
        self._emit(0x9100C3EE)  # add x14, sp, #48
        self._emit(0xCB0A01C2)  # sub x2, x14, x10
        self._emit(0xAA0A03E1)  # mov x1, x10
        self._emit(0xD2800020)  # mov x0, #1
        self._emit(0xD2800090)  # movz x16, #4
        self._emit(0xF2A04010)  # movk x16, #0x200, lsl #16
        self._emit(0xD4001001)  # svc #0x80

        # Print newline
        self._emit(0x5280014D)  # mov w13, #10 ('\n')
        self._emit(0x390143ED)  # strb w13, [sp, #80]
        self._emit(0xD2800020)  # mov x0, #1
        self._emit(0x910143E1)  # add x1, sp, #80
        self._emit(0xD2800022)  # mov x2, #1
        self._emit(0xD2800090)  # movz x16, #4
        self._emit(0xF2A04010)  # movk x16, #0x200, lsl #16
        self._emit(0xD4001001)  # svc #0x80

        # Branch to epilogue
        whole_end_off = len(self.code)
        self._emit(0x14000000)  # b epilogue (placeholder)

        # === Decimal path ===
        self._patch_cond_branch(has_dec_off, len(self.code), 0x1)

        # Print integer part
        self._emit(0x9100C3EA)  # add x10, sp, #48
        self._emit(0x5280014B)  # mov w11, #10

        # Check if integer part is 0
        self._emit(0xF100011F)  # cmp x8, #0
        int_zero_off = len(self.code)
        self._emit(0x54000000)  # b.eq int_is_zero (placeholder)

        dec_int_loop_off = len(self.code)
        self._emit(0x9ACB090C)  # udiv x12, x8, x11
        self._emit(0x9B0BA18C)  # msub x12, x12, x11, x8
        self._emit(0x1100C18C)  # add w12, w12, #'0'
        self._emit(0x381FFD4C)  # strb w12, [x10, #-1]!
        self._emit(0x9ACB0908)  # udiv x8, x8, x11
        self._emit(0xF100011F)  # cmp x8, #0
        di_br_off = len(self.code)
        self._emit(0x54000001)  # b.ne decIntLoop
        self._patch_cond_branch(di_br_off, dec_int_loop_off, 0x1)

        past_zero_off = len(self.code)
        self._emit(0x14000000)  # b past_zero (placeholder)

        # int_is_zero: write '0'
        self._patch_cond_branch(int_zero_off, len(self.code), 0x0)
        self._emit(0x52800608)  # mov w8, #'0'
        self._emit(0x381FFD48)  # strb w8, [x10, #-1]!

        # past_zero: patch branch
        past_zero_target = len(self.code)
        pz_delta = (past_zero_target - past_zero_off) // 4
        pz_d = pz_delta & 0xFFFFFFFF
        pz_inst = 0x14000000 | (pz_d & 0x3FFFFFF)
        self.code[past_zero_off:past_zero_off+4] = struct.pack('<I', pz_inst)

        # Write integer string
        self._emit(0x9100C3EE)  # add x14, sp, #48
        self._emit(0xCB0A01C2)  # sub x2, x14, x10
        self._emit(0xAA0A03E1)  # mov x1, x10
        self._emit(0xD2800020)  # mov x0, #1
        self._emit(0xD2800090)  # movz x16, #4
        self._emit(0xF2A04010)  # movk x16, #0x200, lsl #16
        self._emit(0xD4001001)  # svc #0x80

        # Print '.'
        self._emit(0x528005C8)  # mov w8, #46 ('.')
        self._emit(0x390143E8)  # strb w8, [sp, #80]
        self._emit(0xD2800020)  # mov x0, #1
        self._emit(0x910143E1)  # add x1, sp, #80
        self._emit(0xD2800022)  # mov x2, #1
        self._emit(0xD2800090)  # movz x16, #4
        self._emit(0xF2A04010)  # movk x16, #0x200, lsl #16
        self._emit(0xD4001001)  # svc #0x80

        # Recompute fractional part (registers were clobbered)
        self._emit(0xFD4003E0)  # ldr d0, [sp]
        self._emit(0x9E780008)  # fcvtzs x8, d0
        self._emit(0x9E620101)  # scvtf d1, x8
        self._emit(0x1E613802)  # fsub d2, d0, d1

        # Extract up to 16 fractional digits into sp+48..63
        self._emit(0x52800009)  # mov w9, #0

        # Load 10.0 constant from data section
        ten_off = self._add_double(10.0)
        self._emit_adrp_add(8, ten_off)
        self._emit(0xFD400103)  # ldr d3, [x8]

        frac_loop_off = len(self.code)
        self._emit(0x1E630842)  # fmul d2, d2, d3
        self._emit(0x9E78004A)  # fcvtzs x10, d2
        self._emit(0x1100C14A)  # add w10, w10, #'0'
        self._emit(0x9100C3EB)  # add x11, sp, #48
        self._emit(0x3829496A)  # strb w10, [x11, w9, uxtw]
        # Subtract integer part of d2
        self._emit(0x9E78004A)  # fcvtzs x10, d2
        self._emit(0x9E620144)  # scvtf d4, x10
        self._emit(0x1E643842)  # fsub d2, d2, d4
        self._emit(0x11000529)  # add w9, w9, #1
        self._emit(0x7100413F)  # cmp w9, #16
        frac_br_off = len(self.code)
        self._emit(0x5400000B)  # b.lt fracLoop
        self._patch_cond_branch(frac_br_off, frac_loop_off, 0xB)

        # Trim trailing zeros
        self._emit(0x51000529)  # sub w9, w9, #1
        trim_loop_off = len(self.code)
        self._emit(0x9100C3EB)  # add x11, sp, #48
        self._emit(0x3869496A)  # ldrb w10, [x11, w9, uxtw]
        self._emit(0x7100C15F)  # cmp w10, #'0'
        trim_done_off = len(self.code)
        self._emit(0x54000001)  # b.ne trim_done
        self._emit(0x51000529)  # sub w9, w9, #1
        self._emit(0x7100013F)  # cmp w9, #0
        trim_br_off = len(self.code)
        self._emit(0x5400000A)  # b.ge trimLoop
        self._patch_cond_branch(trim_br_off, trim_loop_off, 0xA)

        # trim_done:
        self._patch_cond_branch(trim_done_off, len(self.code), 0x1)

        # Print w9+1 frac digits from sp+48
        self._emit(0x11000522)  # add w2, w9, #1
        self._emit(0x9100C3E1)  # add x1, sp, #48
        self._emit(0xD2800020)  # mov x0, #1
        self._emit(0xD2800090)  # movz x16, #4
        self._emit(0xF2A04010)  # movk x16, #0x200, lsl #16
        self._emit(0xD4001001)  # svc #0x80

        # Print newline
        self._emit(0x5280014D)  # mov w13, #10
        self._emit(0x390143ED)  # strb w13, [sp, #80]
        self._emit(0xD2800020)  # mov x0, #1
        self._emit(0x910143E1)  # add x1, sp, #80
        self._emit(0xD2800022)  # mov x2, #1
        self._emit(0xD2800090)  # movz x16, #4
        self._emit(0xF2A04010)  # movk x16, #0x200, lsl #16
        self._emit(0xD4001001)  # svc #0x80

        # Epilogue: patch whole-number branch to here
        epilogue_off = len(self.code)
        wh_delta = (epilogue_off - whole_end_off) // 4
        wh_d = wh_delta & 0xFFFFFFFF
        wh_inst = 0x14000000 | (wh_d & 0x3FFFFFF)
        self.code[whole_end_off:whole_end_off+4] = struct.pack('<I', wh_inst)

        self._emit(0x910183FF)  # add sp, sp, #96
        self._emit(0xA8C17BFD)  # ldp x29, x30, [sp], #16
        self._emit(0xD65F03C0)  # ret

    def _patch_cond_branch(self, offset, target, cond):
        """Patch a conditional branch instruction at offset to jump to target"""
        delta = (target - offset) // 4
        d = delta & 0xFFFFFFFF
        inst = 0x54000000 | ((d & 0x7FFFF) << 5) | cond
        self.code[offset:offset+4] = struct.pack('<I', inst)

    def _add_double(self, value):
        """Add a double to the data section, returns offset"""
        while len(self.data) % 8 != 0:
            self.data.append(0)
        off = len(self.data)
        self.data.extend(struct.pack('<d', value))
        return off

    def _gen_func(self, node):
        """Generate function code"""
        self.current_func = node.name
        self.label_offsets[f'_{node.name}'] = len(self.code)

        self._emit(self._hex(self.inst['prologue']['stp_fp_lr']))
        self._emit(self._hex(self.inst['prologue']['stp_x19_x20']))
        self._emit(self._hex(self.inst['prologue']['mov_fp_sp']))
        self._emit(0xD10403FF)  # sub sp, sp, #256

        old_vars = self.variables.copy()
        old_offset = self.stack_offset
        self.variables = {}
        self.stack_offset = 16

        for i, param in enumerate(node.params):
            self.variables[param] = self.stack_offset
            self._emit_store(i, self.stack_offset)
            self.stack_offset += 8

        for stmt in node.body:
            self._gen_stmt(stmt)

        self._emit(self._hex(self.inst['moves']['mov_w0_0']))
        self.label_offsets[f'_{node.name}_ret'] = len(self.code)
        self._emit(0x910403FF)  # add sp, sp, #256
        self._emit(self._hex(self.inst['epilogue']['ldp_x19_x20']))
        self._emit(self._hex(self.inst['epilogue']['ldp_fp_lr']))
        self._emit(self._hex(self.inst['epilogue']['ret']))

        self.variables = old_vars
        self.stack_offset = old_offset
        self.current_func = None

    def _gen_stmt(self, node):
        """Generate statement code"""
        if isinstance(node, PrintStmt):
            self._gen_print(node)
        elif isinstance(node, VarDecl):
            self._gen_var_decl(node)
        elif isinstance(node, LoopStmt):
            self._gen_loop(node)
        elif isinstance(node, IfStmt):
            self._gen_if(node)
        elif isinstance(node, ReturnStmt):
            self._gen_expr(node.value)
            self._add_branch(f'_{self.current_func}_ret', BranchType.B)
        elif isinstance(node, EnumDef):
            self.enums[node.name] = node.cases
            for case_name in node.cases:
                self._add_string(case_name)

    def _gen_print(self, node):
        """Generate print statement"""
        if isinstance(node.expr, Literal) and isinstance(node.expr.value, str):
            # Print string using write syscall
            str_with_newline = node.expr.value + "\n"
            str_off = self._add_string(str_with_newline)
            str_len = len(str_with_newline.encode('utf-8'))
            self._emit_write_syscall(str_off, str_len)
        elif isinstance(node.expr, VarRef) and node.expr.name in self.enum_var_types:
            # Print enum variable (string pointer) + newline
            self._emit_load_x(0, self.variables[node.expr.name])
            self._emit_print_cstring()
        elif isinstance(node.expr, IndexAccess) and isinstance(node.expr.array, VarRef) and node.expr.array.name in self.enums:
            # Print enum access: Color["Red"] -> print "Red"
            if isinstance(node.expr.index, Literal) and isinstance(node.expr.index.value, str):
                s = node.expr.index.value + "\n"
                str_off = self._add_string(s)
                self._emit_write_syscall(str_off, len(s.encode('utf-8')))
        elif isinstance(node.expr, VarRef) and node.expr.name in self.enums:
            # Print full enum
            cases = self.enums[node.expr.name]
            parts = [f'"{c}": {c}' for c in cases]
            s = "{" + ", ".join(parts) + "}\n"
            str_off = self._add_string(s)
            self._emit_write_syscall(str_off, len(s.encode('utf-8')))
        elif isinstance(node.expr, VarRef) and node.expr.name in self.tuples:
            # Print full tuple
            tup = self.tuples[node.expr.name]
            lp = self._add_string("(")
            self._emit_write_syscall(lp, 1)
            for i, t in enumerate(tup['types']):
                if i > 0:
                    cm = self._add_string(", ")
                    self._emit_write_syscall(cm, 2)
                if t == 'string':
                    self._emit_load_x(0, tup['offset'] + i * 8)
                    self._emit_print_cstring_no_newline()
                elif t == 'bool':
                    self._emit_load(0, tup['offset'] + i * 8)
                    self._emit(0x7100001F)  # cmp w0, #0
                    fl = f'_tf{len(self.code)}'
                    dl = f'_td{len(self.code)}'
                    self._add_branch(fl, BranchType.BEQ)
                    ts = self._add_string("true")
                    self._emit_write_syscall(ts, 4)
                    self._add_branch(dl, BranchType.B)
                    self.label_offsets[fl] = len(self.code)
                    fs = self._add_string("false")
                    self._emit_write_syscall(fs, 5)
                    self.label_offsets[dl] = len(self.code)
                else:
                    self._emit_load(0, tup['offset'] + i * 8)
                    self._emit_print_int_no_newline()
            rp = self._add_string(")\n")
            self._emit_write_syscall(rp, 2)
        elif isinstance(node.expr, IndexAccess) and isinstance(node.expr.array, VarRef) and node.expr.array.name in self.tuples:
            # Tuple index access
            tup = self.tuples[node.expr.array.name]
            if isinstance(node.expr.index, Literal) and isinstance(node.expr.index.value, int):
                i = node.expr.index.value
                if i < len(tup['types']):
                    t = tup['types'][i]
                    if t == 'string':
                        self._emit_load_x(0, tup['offset'] + i * 8)
                        self._emit_print_cstring()
                    elif t == 'bool':
                        self._emit_load(0, tup['offset'] + i * 8)
                        self._emit(0x7100001F)
                        fl = f'_tf{len(self.code)}'
                        dl = f'_td{len(self.code)}'
                        self._add_branch(fl, BranchType.BEQ)
                        ts = self._add_string("true\n")
                        self._emit_write_syscall(ts, 5)
                        self._add_branch(dl, BranchType.B)
                        self.label_offsets[fl] = len(self.code)
                        fs = self._add_string("false\n")
                        self._emit_write_syscall(fs, 6)
                        self.label_offsets[dl] = len(self.code)
                    else:
                        self._emit_load(0, tup['offset'] + i * 8)
                        delta = (self.print_int_offset - len(self.code)) // 4
                        d = delta & 0xFFFFFFFF
                        self._emit(0x94000000 | (d & 0x3FFFFFF))
        elif isinstance(node.expr, VarRef) and node.expr.name in self.dicts:
            entries = self.dicts[node.expr.name]
            if not entries:
                s = self._add_string("{}\n")
                self._emit_write_syscall(s, 3)
            else:
                lb = self._add_string("{")
                self._emit_write_syscall(lb, 1)
                for i, e in enumerate(entries):
                    if i > 0:
                        cm = self._add_string(", ")
                        self._emit_write_syscall(cm, 2)
                    ks = self._add_string(f'"{e["key"]}": ')
                    self._emit_write_syscall(ks, len(e['key']) + 4)
                    if e['type'] == 'string':
                        self._emit_load_x(0, e['offset'])
                        self._emit_print_cstring_no_newline()
                    elif e['type'] == 'bool':
                        self._emit_load(0, e['offset'])
                        self._emit(0x7100001F)
                        fl = f'_tf{len(self.code)}'; dl = f'_td{len(self.code)}'
                        self._add_branch(fl, BranchType.BEQ)
                        ts = self._add_string("true"); self._emit_write_syscall(ts, 4)
                        self._add_branch(dl, BranchType.B)
                        self.label_offsets[fl] = len(self.code)
                        fs = self._add_string("false"); self._emit_write_syscall(fs, 5)
                        self.label_offsets[dl] = len(self.code)
                    else:
                        if e['sub_array'] and e['sub_array'] in self.arrays:
                            self._emit_print_full_array_inline(e['sub_array'], self.arrays[e['sub_array']])
                        else:
                            self._emit_load(0, e['offset'])
                            self._emit_print_int_no_newline()
                rb = self._add_string("}\n")
                self._emit_write_syscall(rb, 2)
        elif isinstance(node.expr, IndexAccess) and isinstance(node.expr.array, VarRef) and node.expr.array.name in self.dicts:
            entries = self.dicts[node.expr.array.name]
            if isinstance(node.expr.index, Literal) and isinstance(node.expr.index.value, str):
                key = node.expr.index.value
                entry = next((e for e in entries if e['key'] == key), None)
                if entry:
                    if entry['type'] == 'string':
                        self._emit_load_x(0, entry['offset'])
                        self._emit_print_cstring()
                    elif entry['type'] == 'bool':
                        self._emit_load(0, entry['offset'])
                        self._emit(0x7100001F)
                        fl = f'_tf{len(self.code)}'; dl = f'_td{len(self.code)}'
                        self._add_branch(fl, BranchType.BEQ)
                        ts = self._add_string("true\n"); self._emit_write_syscall(ts, 5)
                        self._add_branch(dl, BranchType.B)
                        self.label_offsets[fl] = len(self.code)
                        fs = self._add_string("false\n"); self._emit_write_syscall(fs, 6)
                        self.label_offsets[dl] = len(self.code)
                    else:
                        if entry['sub_array'] and entry['sub_array'] in self.arrays:
                            self._emit_print_full_array(entry['sub_array'], self.arrays[entry['sub_array']])
                        else:
                            self._emit_load(0, entry['offset'])
                            delta = (self.print_int_offset - len(self.code)) // 4
                            d = delta & 0xFFFFFFFF
                            self._emit(0x94000000 | (d & 0x3FFFFFF))
        elif isinstance(node.expr, IndexAccess) and isinstance(node.expr.array, IndexAccess) and \
             isinstance(node.expr.array.array, VarRef) and node.expr.array.array.name in self.dicts:
            entries = self.dicts[node.expr.array.array.name]
            if isinstance(node.expr.array.index, Literal) and isinstance(node.expr.array.index.value, str):
                key = node.expr.array.index.value
                entry = next((e for e in entries if e['key'] == key), None)
                if entry and entry['sub_array'] and entry['sub_array'] in self.arrays:
                    sub = entry['sub_array']
                    is_str = self.arrays[sub]['elem_type'] == 'string'
                    self._gen_array_index_load(sub, node.expr.index, is_string=is_str)
                    if is_str:
                        self._emit_print_cstring()
                    else:
                        delta = (self.print_int_offset - len(self.code)) // 4
                        d = delta & 0xFFFFFFFF
                        self._emit(0x94000000 | (d & 0x3FFFFFF))
        elif isinstance(node.expr, VarRef) and node.expr.name in self.arrays:
            # Print full array
            self._emit_print_full_array(node.expr.name, self.arrays[node.expr.name])
        elif isinstance(node.expr, IndexAccess) and isinstance(node.expr.array, VarRef) and node.expr.array.name in self.arrays:
            info = self.arrays[node.expr.array.name]
            if info['elem_type'] == 'string':
                self._gen_array_index_load(node.expr.array.name, node.expr.index, is_string=True)
                self._emit_print_cstring()
            elif info['elem_type'] == 'nested':
                if isinstance(node.expr.index, Literal) and isinstance(node.expr.index.value, int):
                    sub_name = f"{node.expr.array.name}_{node.expr.index.value}"
                    if sub_name in self.arrays:
                        self._emit_print_full_array(sub_name, self.arrays[sub_name])
            else:
                self._gen_array_index_load(node.expr.array.name, node.expr.index, is_string=False)
                delta = (self.print_int_offset - len(self.code)) // 4
                d = delta & 0xFFFFFFFF
                self._emit(0x94000000 | (d & 0x3FFFFFF))
        elif isinstance(node.expr, IndexAccess) and isinstance(node.expr.array, IndexAccess) and \
             isinstance(node.expr.array.array, VarRef) and node.expr.array.array.name in self.arrays and \
             self.arrays[node.expr.array.array.name]['elem_type'] == 'nested':
            # Nested: matrix[0][1]
            outer_name = node.expr.array.array.name
            if isinstance(node.expr.array.index, Literal) and isinstance(node.expr.array.index.value, int):
                sub_name = f"{outer_name}_{node.expr.array.index.value}"
                if sub_name in self.arrays:
                    self._gen_array_index_load(sub_name, node.expr.index, is_string=False)
                    delta = (self.print_int_offset - len(self.code)) // 4
                    d = delta & 0xFFFFFFFF
                    self._emit(0x94000000 | (d & 0x3FFFFFF))
        elif self._is_float_expr(node.expr):
            # Print float - call print_float routine
            self._gen_float_expr(node.expr)
            delta = (self.print_float_offset - len(self.code)) // 4
            d = delta & 0xFFFFFFFF
            self._emit(0x94000000 | (d & 0x3FFFFFF))
        else:
            # Print integer - call print_int routine
            self._gen_expr(node.expr)
            delta = (self.print_int_offset - len(self.code)) // 4
            d = delta & 0xFFFFFFFF
            self._emit(0x94000000 | (d & 0x3FFFFFF))

    def _emit_write_syscall(self, data_offset, length):
        """Write a string from data section to stdout"""
        self._emit(self._hex(self.inst['moves']['mov_x0_1']))
        self._emit_adrp_add(1, data_offset)
        self._emit_mov_imm(2, length)
        self._emit(self._hex(self.inst['syscall']['movz_x16_4']))
        self._emit(self._hex(self.inst['syscall']['movk_x16_0x200_lsl16']))
        self._emit(self._hex(self.inst['syscall']['svc']))

    def _emit_print_cstring(self):
        """Print a C string whose pointer is in x0, followed by newline"""
        self._emit(0xAA0003E1)  # mov x1, x0
        self._emit(0xAA0003E2)  # mov x2, x0
        # Scan for null terminator
        scan_loop = len(self.code)
        self._emit(0x39400048)  # ldrb w8, [x2]
        self._emit(0x91000442)  # add x2, x2, #1
        self._emit(0x7100011F)  # cmp w8, #0
        branch_off = len(self.code)
        self._emit(0x54000001)  # b.ne placeholder
        delta = (scan_loop - branch_off) // 4
        d = delta & 0xFFFFFFFF
        inst = 0x54000001 | ((d & 0x7FFFF) << 5)
        self.code[branch_off:branch_off+4] = struct.pack('<I', inst)

        # length = x2 - x1 - 1
        self._emit(0xCB010042)  # sub x2, x2, x1
        self._emit(0xD1000442)  # sub x2, x2, #1

        # write(1, x1, x2)
        self._emit(0xD2800020)  # mov x0, #1
        self._emit(self._hex(self.inst['syscall']['movz_x16_4']))
        self._emit(self._hex(self.inst['syscall']['movk_x16_0x200_lsl16']))
        self._emit(self._hex(self.inst['syscall']['svc']))

        # Print newline
        self._emit(0xD100C3FF)  # sub sp, sp, #48
        self._emit(0x5280014D)  # mov w13, #10
        self._emit(0x390003ED)  # strb w13, [sp]
        self._emit(0x910003E1)  # mov x1, sp
        self._emit(0xD2800020)  # mov x0, #1
        self._emit(0xD2800022)  # mov x2, #1
        self._emit(self._hex(self.inst['syscall']['movz_x16_4']))
        self._emit(self._hex(self.inst['syscall']['movk_x16_0x200_lsl16']))
        self._emit(self._hex(self.inst['syscall']['svc']))
        self._emit(0x9100C3FF)  # add sp, sp, #48

    def _emit_print_cstring_no_newline(self):
        """Print C string in x0 without newline"""
        self._emit(0xAA0003E1)  # mov x1, x0
        self._emit(0xAA0003E2)  # mov x2, x0
        scan_loop = len(self.code)
        self._emit(0x39400048)  # ldrb w8, [x2]
        self._emit(0x91000442)  # add x2, x2, #1
        self._emit(0x7100011F)  # cmp w8, #0
        branch_off = len(self.code)
        self._emit(0x54000001)
        delta = (scan_loop - branch_off) // 4
        d = delta & 0xFFFFFFFF
        inst = 0x54000001 | ((d & 0x7FFFF) << 5)
        self.code[branch_off:branch_off+4] = struct.pack('<I', inst)
        self._emit(0xCB010042)  # sub x2, x2, x1
        self._emit(0xD1000442)  # sub x2, x2, #1
        self._emit(0xD2800020)  # mov x0, #1
        self._emit(self._hex(self.inst['syscall']['movz_x16_4']))
        self._emit(self._hex(self.inst['syscall']['movk_x16_0x200_lsl16']))
        self._emit(self._hex(self.inst['syscall']['svc']))

    def _emit_print_int_no_newline(self):
        """Print int in w0 without newline"""
        self._emit(0xA9BF7BFD)  # stp x29, x30, [sp, #-16]!
        self._emit(0x910003FD)  # mov x29, sp
        self._emit(0xD100C3FF)  # sub sp, sp, #48
        self._emit(0x7100001F)  # cmp w0, #0
        self._emit(0x540000CA)  # b.ge skip_neg
        self._emit(0x4B0003E8)  # neg w8, w0
        self._emit(0x528005A9)  # mov w9, #'-'
        self._emit(0x390003E9)  # strb w9, [sp]
        self._emit(0x52800029)  # mov w9, #1
        self._emit(0x14000003)  # b continue
        self._emit(0x2A0003E8)  # mov w8, w0
        self._emit(0x52800009)  # mov w9, #0
        self._emit(0x910083EA)  # add x10, sp, #32
        self._emit(0x5280014B)  # mov w11, #10
        loop_off = len(self.code)
        self._emit(0x1ACB090C)  # udiv w12, w8, w11
        self._emit(0x1B0BA18C)  # msub w12, w12, w11, w8
        self._emit(0x1100C18C)  # add w12, w12, #'0'
        self._emit(0x381FFD4C)  # strb w12, [x10, #-1]!
        self._emit(0x1ACB0908)  # udiv w8, w8, w11
        self._emit(0x7100011F)  # cmp w8, #0
        br_off = len(self.code)
        self._emit(0x54000001)
        delta = (loop_off - br_off) // 4
        dd = delta & 0xFFFFFFFF
        inst = 0x54000001 | ((dd & 0x7FFFF) << 5)
        self.code[br_off:br_off+4] = struct.pack('<I', inst)
        self._emit(0x7100013F)  # cmp w9, #0
        self._emit(0x54000060)  # b.eq skip_copy
        self._emit(0x394003ED)  # ldrb w13, [sp]
        self._emit(0x381FFD4D)  # strb w13, [x10, #-1]!
        # add x14, sp, #32
        self._emit(0x910083EE)
        self.code[-4:] = struct.pack('<I', 0x910083EE)
        self._emit(0xCB0A01C2)  # sub x2, x14, x10
        self._emit(0xAA0A03E1)  # mov x1, x10
        self._emit(0xD2800020)  # mov x0, #1
        self._emit(self._hex(self.inst['syscall']['movz_x16_4']))
        self._emit(self._hex(self.inst['syscall']['movk_x16_0x200_lsl16']))
        self._emit(self._hex(self.inst['syscall']['svc']))
        self._emit(0x9100C3FF)  # add sp, sp, #48
        self._emit(0xA8C17BFD)  # ldp x29, x30, [sp], #16

    def _emit_print_full_array(self, name, info):
        """Print array in [elem, elem, ...] format"""
        if info['elem_type'] == 'string':
            lb = self._add_string("[")
            self._emit_write_syscall(lb, 1)
            for i in range(info['count']):
                if i > 0:
                    cm = self._add_string(", ")
                    self._emit_write_syscall(cm, 2)
                self._emit_load_x(0, info['offset'] + i * 8)
                self._emit_print_cstring_no_newline()
            rb = self._add_string("]\n")
            self._emit_write_syscall(rb, 2)
        elif info['elem_type'] == 'nested':
            lb = self._add_string("[")
            self._emit_write_syscall(lb, 1)
            for i in range(info['count']):
                if i > 0:
                    cm = self._add_string(", ")
                    self._emit_write_syscall(cm, 2)
                sub_name = f"{name}_{i}"
                if sub_name in self.arrays:
                    self._emit_print_full_array_inline(sub_name, self.arrays[sub_name])
            rb = self._add_string("]\n")
            self._emit_write_syscall(rb, 2)
        else:
            lb = self._add_string("[")
            self._emit_write_syscall(lb, 1)
            for i in range(info['count']):
                if i > 0:
                    cm = self._add_string(", ")
                    self._emit_write_syscall(cm, 2)
                self._emit_load(0, info['offset'] + i * 8)
                self._emit_print_int_no_newline()
            rb = self._add_string("]\n")
            self._emit_write_syscall(rb, 2)

    def _emit_print_full_array_inline(self, name, info):
        """Print array inline without trailing newline"""
        lb = self._add_string("[")
        self._emit_write_syscall(lb, 1)
        for i in range(info['count']):
            if i > 0:
                cm = self._add_string(", ")
                self._emit_write_syscall(cm, 2)
            self._emit_load(0, info['offset'] + i * 8)
            self._emit_print_int_no_newline()
        rb = self._add_string("]")
        self._emit_write_syscall(rb, 1)

    def _gen_array_index_load(self, name, index, is_string=False):
        """Load array element by index"""
        info = self.arrays[name]
        if isinstance(index, Literal) and isinstance(index.value, int):
            if is_string:
                self._emit_load_x(0, info['offset'] + index.value * 8)
            else:
                self._emit_load(0, info['offset'] + index.value * 8)
        else:
            # Dynamic index
            self._gen_expr(index)
            base_addr = info['offset'] + 16
            self._emit_mov_imm(1, 8)
            self._emit(0x1B017C02)  # mul w2, w0, w1
            self._emit_mov_imm(1, base_addr)
            self._emit(0xCB0103A1)  # sub x1, x29, x1
            self._emit(0x93407C42)  # sxtw x2, w2
            self._emit(0xCB020021)  # sub x1, x1, x2
            if is_string:
                self._emit(0xF9400020)  # ldr x0, [x1]
            else:
                self._emit(0xB9400020)  # ldr w0, [x1]

    def _gen_var_decl(self, node):
        """Generate variable declaration"""
        if isinstance(node.value, IndexAccess) and isinstance(node.value.array, VarRef) and node.value.array.name in self.enums:
            self.enum_var_types[node.name] = "enum"
        if isinstance(node.value, ArrayLiteral):
            self._gen_array_decl(node.name, node.value)
            return
        if isinstance(node.value, TupleLiteral):
            self._gen_tuple_decl(node.name, node.value)
            return
        if isinstance(node.value, DictLiteral):
            self._gen_dict_decl(node.name, node.value)
            return
        if self._is_float_expr(node.value):
            self._gen_float_expr(node.value)
            if node.name not in self.variables:
                self.variables[node.name] = self.stack_offset
                self.stack_offset += 8
            self.float_vars.add(node.name)
            self._emit_store_d(0, self.variables[node.name])
            return
        self._gen_expr(node.value)
        if node.name not in self.variables:
            self.variables[node.name] = self.stack_offset
            self.stack_offset += 8
        self._emit_store_x(0, self.variables[node.name])

    def _gen_array_decl(self, name, arr_lit):
        """Generate array literal storage"""
        base_off = self.stack_offset
        elems = arr_lit.elements
        # Determine element type
        elem_type = 'int'
        if elems and isinstance(elems[0], Literal) and isinstance(elems[0].value, str):
            elem_type = 'string'
        elif elems and isinstance(elems[0], ArrayLiteral):
            elem_type = 'nested'

        if elem_type == 'nested':
            sub_names = []
            for i, elem in enumerate(elems):
                if isinstance(elem, ArrayLiteral):
                    sub_name = f'{name}_{i}'
                    self._gen_array_decl(sub_name, elem)
                    sub_names.append(sub_name)
            outer_base = self.stack_offset
            for sub_name in sub_names:
                sub_info = self.arrays[sub_name]
                self._emit_mov_imm(0, sub_info['offset'])
                self._emit_store(0, self.stack_offset)
                self.stack_offset += 8
            self.arrays[name] = {'offset': outer_base, 'count': len(sub_names), 'elem_type': 'nested'}
            self.variables[name] = outer_base
        elif elem_type == 'string':
            for elem in elems:
                if isinstance(elem, Literal) and isinstance(elem.value, str):
                    str_off = self._add_string(elem.value)
                    self._emit_adrp_add(0, str_off)
                    self._emit_store_x(0, self.stack_offset)
                    self.stack_offset += 8
            self.arrays[name] = {'offset': base_off, 'count': len(elems), 'elem_type': 'string'}
            self.variables[name] = base_off
        else:
            for elem in elems:
                self._gen_expr(elem)
                self._emit_store(0, self.stack_offset)
                self.stack_offset += 8
            self.arrays[name] = {'offset': base_off, 'count': len(elems), 'elem_type': 'int'}
            self.variables[name] = base_off

    def _gen_tuple_decl(self, name, tup_lit):
        """Generate tuple literal storage"""
        base_off = self.stack_offset
        types = []
        for elem in tup_lit.elements:
            if isinstance(elem, Literal):
                if isinstance(elem.value, str):
                    types.append('string')
                    str_off = self._add_string(elem.value)
                    self._emit_adrp_add(0, str_off)
                    self._emit_store_x(0, self.stack_offset)
                elif isinstance(elem.value, bool):
                    types.append('bool')
                    self._emit_mov_imm(0, 1 if elem.value else 0)
                    self._emit_store(0, self.stack_offset)
                elif isinstance(elem.value, int):
                    types.append('int')
                    self._emit_mov_imm(0, elem.value)
                    self._emit_store(0, self.stack_offset)
                else:
                    types.append('int')
                    self._emit(self._hex(self.inst['moves']['mov_w0_0']))
                    self._emit_store(0, self.stack_offset)
            else:
                types.append('int')
                self._gen_expr(elem)
                self._emit_store(0, self.stack_offset)
            self.stack_offset += 8
        self.tuples[name] = {'offset': base_off, 'types': types}
        self.variables[name] = base_off

    def _gen_dict_decl(self, name, dict_lit):
        """Generate dictionary literal storage"""
        entries = []
        for pair in dict_lit.pairs:
            if not isinstance(pair[0], Literal) or not isinstance(pair[0].value, str):
                continue
            key = pair[0].value
            val = pair[1]

            if isinstance(val, ArrayLiteral):
                sub_name = f"{name}_{key}"
                self._gen_array_decl(sub_name, val)
                entries.append({'key': key, 'type': 'int', 'offset': 0, 'sub_array': sub_name})
            elif isinstance(val, Literal):
                off = self.stack_offset
                if isinstance(val.value, str):
                    str_off = self._add_string(val.value)
                    self._emit_adrp_add(0, str_off)
                    self._emit_store_x(0, off)
                    entries.append({'key': key, 'type': 'string', 'offset': off, 'sub_array': None})
                elif isinstance(val.value, bool):
                    self._emit_mov_imm(0, 1 if val.value else 0)
                    self._emit_store(0, off)
                    entries.append({'key': key, 'type': 'bool', 'offset': off, 'sub_array': None})
                elif isinstance(val.value, int):
                    self._emit_mov_imm(0, val.value)
                    self._emit_store(0, off)
                    entries.append({'key': key, 'type': 'int', 'offset': off, 'sub_array': None})
                else:
                    entries.append({'key': key, 'type': 'int', 'offset': off, 'sub_array': None})
                self.stack_offset += 8
        self.dicts[name] = entries
        self.variables[name] = self.stack_offset

    def _gen_loop(self, node):
        """Generate loop code"""
        if node.start is None or node.end is None:
            return

        loop_label = f'_L{len(self.code)}'
        end_label = f'_E{len(self.code)}'

        self._gen_expr(node.start)
        if node.var not in self.variables:
            self.variables[node.var] = self.stack_offset
            self.stack_offset += 8
        var_off = self.variables[node.var]
        self._emit_store(0, var_off)

        self._gen_expr(node.end)
        end_off = self.stack_offset
        self.stack_offset += 8
        self._emit_store(0, end_off)

        self.label_offsets[loop_label] = len(self.code)

        self._emit_load(0, var_off)
        self._emit_load(1, end_off)
        self._emit(self._hex(self.inst['compare']['cmp_w0_w1']))
        self._add_branch(end_label, BranchType.BGE)

        for stmt in node.body:
            self._gen_stmt(stmt)

        self._emit_load(0, var_off)
        self._emit(self._hex(self.inst['arithmetic']['add_w0_1']))
        self._emit_store(0, var_off)
        self._add_branch(loop_label, BranchType.B)

        self.label_offsets[end_label] = len(self.code)

    def _gen_if(self, node):
        """Generate if statement"""
        else_label = f'_else{len(self.code)}'
        end_label = f'_end{len(self.code)}'

        if isinstance(node.condition, BinaryOp):
            use_float = self._is_float_expr(node.condition.left) or self._is_float_expr(node.condition.right)

            if use_float:
                # Float comparison using fcmp
                self._gen_float_expr(node.condition.left)
                self._emit(0xFC1F0FE0)  # str d0, [sp, #-16]!
                self._gen_float_expr(node.condition.right)
                self._emit(0x1E604001)  # fmov d1, d0
                self._emit(0xFC4107E0)  # ldr d0, [sp], #16
                self._emit(0x1E612010)  # fcmp d0, d1

                op = node.condition.op
                if op == '==':
                    self._add_branch(else_label, BranchType.BNE)
                elif op == '!=':
                    self._add_branch(else_label, BranchType.BEQ)
                elif op == '<':
                    self._add_branch(else_label, BranchType.BGE)
                elif op == '>':
                    self._add_branch(else_label, BranchType.BLE)
                elif op == '<=':
                    self._add_branch(else_label, BranchType.BGT)
                elif op == '>=':
                    self._add_branch(else_label, BranchType.BLT)
            else:
                is_enum_cmp = self._is_enum_expr(node.condition.left) or self._is_enum_expr(node.condition.right)
                self._gen_expr(node.condition.left)
                if is_enum_cmp:
                    self._emit(0xAA0003E9)  # mov x9, x0 (64-bit)
                else:
                    self._emit(self._hex(self.inst['moves']['mov_w9_w0']))
                self._gen_expr(node.condition.right)
                if is_enum_cmp:
                    self._emit(0xEB00013F)  # cmp x9, x0 (64-bit)
                else:
                    self._emit(self._hex(self.inst['compare']['cmp_w9_w0']))

                op = node.condition.op
                if op == '==':
                    self._add_branch(else_label, BranchType.BNE)
                elif op == '!=':
                    self._add_branch(else_label, BranchType.BEQ)
                elif op == '<':
                    self._add_branch(else_label, BranchType.BGE)
                elif op == '>':
                    self._add_branch(else_label, BranchType.BLE)
                elif op == '<=':
                    self._add_branch(else_label, BranchType.BGT)
                elif op == '>=':
                    self._add_branch(else_label, BranchType.BLT)
        else:
            self._gen_expr(node.condition)
            self._emit(self._hex(self.inst['compare']['cmp_w0_0']))
            self._add_branch(else_label, BranchType.BEQ)

        for stmt in node.then_body:
            self._gen_stmt(stmt)
        if node.else_body:
            self._add_branch(end_label, BranchType.B)

        self.label_offsets[else_label] = len(self.code)
        if node.else_body:
            for stmt in node.else_body:
                self._gen_stmt(stmt)
            self.label_offsets[end_label] = len(self.code)

    def _gen_expr(self, node):
        """Generate expression code"""
        if isinstance(node, Literal):
            if isinstance(node.value, int):
                self._emit_mov_imm(0, node.value)
            elif isinstance(node.value, bool):
                self._emit_mov_imm(0, 1 if node.value else 0)
            else:
                self._emit(self._hex(self.inst['moves']['mov_w0_0']))
        elif isinstance(node, VarRef):
            if node.name in self.variables:
                if node.name in self.enum_var_types:
                    self._emit_load_x(0, self.variables[node.name])
                else:
                    self._emit_load(0, self.variables[node.name])
            else:
                self._emit(self._hex(self.inst['moves']['mov_w0_0']))
        elif isinstance(node, BinaryOp):
            self._gen_expr(node.left)
            self._emit(self._hex(self.inst['memory']['str_x0_push']))
            self._gen_expr(node.right)
            self._emit(self._hex(self.inst['moves']['mov_w1_w0']))
            self._emit(self._hex(self.inst['memory']['ldr_x0_pop']))

            op = node.op
            if op == '+':
                self._emit(self._hex(self.inst['arithmetic']['add']))
            elif op == '-':
                self._emit(self._hex(self.inst['arithmetic']['sub']))
            elif op == '*':
                self._emit(self._hex(self.inst['arithmetic']['mul']))
            elif op == '/':
                self._emit(self._hex(self.inst['arithmetic']['sdiv']))
            elif op == '%':
                self._emit(0x1AC10C02)  # sdiv w2, w0, w1
                self._emit(0x1B018040)  # msub w0, w2, w1, w0
            elif op == '==':
                self._emit(self._hex(self.inst['compare']['cmp_w0_w1']))
                self._emit(self._hex(self.inst['cset']['eq']))
            elif op == '!=':
                self._emit(self._hex(self.inst['compare']['cmp_w0_w1']))
                self._emit(self._hex(self.inst['cset']['ne']))
            elif op == '<':
                self._emit(self._hex(self.inst['compare']['cmp_w0_w1']))
                self._emit(self._hex(self.inst['cset']['lt']))
            elif op == '>':
                self._emit(self._hex(self.inst['compare']['cmp_w0_w1']))
                self._emit(self._hex(self.inst['cset']['gt']))
        elif isinstance(node, IndexAccess) and isinstance(node.array, VarRef) and node.array.name in self.enums:
            # Enum access: Color["Red"] -> load pointer to "Red" string
            if isinstance(node.index, Literal) and isinstance(node.index.value, str):
                str_off = self._add_string(node.index.value)
                self._emit_adrp_add(0, str_off)
        elif isinstance(node, IndexAccess) and isinstance(node.array, VarRef) and node.array.name in self.arrays:
            # Array index access
            is_str = self.arrays[node.array.name]['elem_type'] == 'string'
            self._gen_array_index_load(node.array.name, node.index, is_string=is_str)
        elif isinstance(node, IndexAccess) and isinstance(node.array, IndexAccess) and \
             isinstance(node.array.array, VarRef) and node.array.array.name in self.arrays and \
             self.arrays[node.array.array.name]['elem_type'] == 'nested':
            # Nested: matrix[0][1]
            if isinstance(node.array.index, Literal) and isinstance(node.array.index.value, int):
                sub_name = f"{node.array.array.name}_{node.array.index.value}"
                if sub_name in self.arrays:
                    self._gen_array_index_load(sub_name, node.index, is_string=False)
        elif isinstance(node, FuncCall):
            if node.name in self.functions:
                for i, arg in enumerate(node.args[:8]):
                    self._gen_expr(arg)
                    self._emit(0x2A0003E0 | (19 + i))
                for i in range(min(len(node.args), 8)):
                    self._emit(0x2A0003E0 | i | ((19 + i) << 16))
                self._add_branch(f'_{node.name}', BranchType.BL)

    def _emit_store_d(self, reg, offset):
        """Emit stur d{reg}, [x29, #-offset-16] (64-bit float store)"""
        off9 = (-offset - 16) & 0x1FF
        self._emit(0xFC000000 | (off9 << 12) | (29 << 5) | reg)

    def _emit_load_d(self, reg, offset):
        """Emit ldur d{reg}, [x29, #-offset-16] (64-bit float load)"""
        off9 = (-offset - 16) & 0x1FF
        self._emit(0xFC400000 | (off9 << 12) | (29 << 5) | reg)

    def _is_float_expr(self, node):
        """Determine if an expression evaluates to a float"""
        if isinstance(node, Literal):
            return isinstance(node.value, float)
        elif isinstance(node, VarRef):
            return node.name in self.float_vars
        elif isinstance(node, BinaryOp):
            return self._is_float_expr(node.left) or self._is_float_expr(node.right)
        elif isinstance(node, UnaryOp):
            return self._is_float_expr(node.operand)
        return False

    def _gen_float_expr(self, node):
        """Generate code that leaves a float result in d0"""
        if isinstance(node, Literal):
            if isinstance(node.value, float):
                off = self._add_double(node.value)
                self._emit_adrp_add(8, off)
                self._emit(0xFD400100)  # ldr d0, [x8]
            elif isinstance(node.value, int):
                # Int literal in float context - convert via scvtf
                self._emit_mov_imm(0, node.value)
                self._emit(0x1E620000)  # scvtf d0, w0
        elif isinstance(node, VarRef):
            if node.name in self.float_vars and node.name in self.variables:
                self._emit_load_d(0, self.variables[node.name])
            elif node.name in self.variables:
                # Int variable in float context - load and convert
                self._emit_load(0, self.variables[node.name])
                self._emit(0x1E620000)  # scvtf d0, w0
        elif isinstance(node, BinaryOp):
            self._gen_float_expr(node.left)
            self._emit(0xFC1F0FE0)  # str d0, [sp, #-16]!
            self._gen_float_expr(node.right)
            self._emit(0x1E604001)  # fmov d1, d0
            self._emit(0xFC4107E0)  # ldr d0, [sp], #16

            op = node.op
            if op == '+':
                self._emit(0x1E612800)  # fadd d0, d0, d1
            elif op == '-':
                self._emit(0x1E613800)  # fsub d0, d0, d1
            elif op == '*':
                self._emit(0x1E610800)  # fmul d0, d0, d1
            elif op == '/':
                self._emit(0x1E611800)  # fdiv d0, d0, d1
            elif op == '%':
                # Float mod: d0 = d0 - trunc(d0/d1) * d1
                self._emit(0x1E611802)  # fdiv d2, d0, d1
                self._emit(0x1E65C042)  # frintz d2, d2
                self._emit(0x1F418040)  # fmsub d0, d2, d1, d0
        elif isinstance(node, UnaryOp):
            self._gen_float_expr(node.operand)
            if node.op in ('-', 'neg'):
                self._emit(0x1E614000)  # fneg d0, d0

    def _is_enum_expr(self, node):
        """Check if expression is an enum-related expression"""
        if isinstance(node, VarRef):
            return node.name in self.enum_var_types or node.name in self.enums
        if isinstance(node, IndexAccess) and isinstance(node.array, VarRef):
            return node.array.name in self.enums
        return False

    def _emit(self, inst):
        """Emit 32-bit instruction"""
        self.code.extend(struct.pack('<I', inst & 0xFFFFFFFF))

    def _emit_mov_imm(self, reg, value):
        """Emit mov immediate instruction"""
        v = value & 0xFFFFFFFF
        if 0 <= value < 65536:
            self._emit(0x52800000 | (v << 5) | reg)
        elif -65536 <= value < 0:
            self._emit(0x12800000 | ((~v & 0xFFFF) << 5) | reg)
        else:
            self._emit(0x52800000 | ((v & 0xFFFF) << 5) | reg)
            self._emit(0x72A00000 | (((v >> 16) & 0xFFFF) << 5) | reg)

    def _emit_store(self, reg, offset):
        """Emit store instruction (32-bit)"""
        off9 = (-offset - 16) & 0x1FF
        self._emit(0xB8000000 | (off9 << 12) | (29 << 5) | reg)

    def _emit_load(self, reg, offset):
        """Emit load instruction (32-bit)"""
        off9 = (-offset - 16) & 0x1FF
        self._emit(0xB8400000 | (off9 << 12) | (29 << 5) | reg)

    def _emit_store_x(self, reg, offset):
        """Emit 64-bit store instruction (for pointers)"""
        off9 = (-offset - 16) & 0x1FF
        self._emit(0xF8000000 | (off9 << 12) | (29 << 5) | reg)

    def _emit_load_x(self, reg, offset):
        """Emit 64-bit load instruction (for pointers)"""
        off9 = (-offset - 16) & 0x1FF
        self._emit(0xF8400000 | (off9 << 12) | (29 << 5) | reg)

    def _emit_adrp_add(self, reg, data_offset):
        """Emit adrp/add pair for data reference"""
        self._emit(self._hex(self.inst['adrp']) | reg)
        self._emit(self._hex(self.inst['add_imm_base']) | (reg << 5) | reg | ((data_offset & 0xFFF) << 10))

    def _add_branch(self, label, branch_type):
        """Add pending branch to be resolved"""
        self.pending_branches.append({
            'offset': len(self.code),
            'label': label,
            'type': branch_type
        })
        self._emit(0x14000000)

    def _resolve_branches(self):
        """Resolve all pending branches"""
        cond_map = self.inst['branchCond']
        for b in self.pending_branches:
            if b['label'] not in self.label_offsets:
                continue
            target = self.label_offsets[b['label']]
            delta = (target - b['offset']) // 4
            d = delta & 0xFFFFFFFF

            if b['type'] == BranchType.B:
                inst = 0x14000000 | (d & 0x3FFFFFF)
            elif b['type'] == BranchType.BL:
                inst = 0x94000000 | (d & 0x3FFFFFF)
            elif b['type'] == BranchType.BEQ:
                inst = 0x54000000 | ((d & 0x7FFFF) << 5) | cond_map['eq']
            elif b['type'] == BranchType.BNE:
                inst = 0x54000000 | ((d & 0x7FFFF) << 5) | cond_map['ne']
            elif b['type'] == BranchType.BGE:
                inst = 0x54000000 | ((d & 0x7FFFF) << 5) | cond_map['ge']
            elif b['type'] == BranchType.BLE:
                inst = 0x54000000 | ((d & 0x7FFFF) << 5) | cond_map['le']
            elif b['type'] == BranchType.BGT:
                inst = 0x54000000 | ((d & 0x7FFFF) << 5) | 12
            elif b['type'] == BranchType.BLT:
                inst = 0x54000000 | ((d & 0x7FFFF) << 5) | 11

            self.code[b['offset']:b['offset']+4] = struct.pack('<I', inst)

    def _add_string(self, s):
        """Add string to data section"""
        if s in self.string_offsets:
            return self.string_offsets[s]
        off = len(self.data)
        self.string_offsets[s] = off
        self.data.extend(s.encode('utf-8'))
        self.data.append(0)
        while len(self.data) % 8 != 0:
            self.data.append(0)
        return off

    def _write_macho(self, path, main_offset):
        """Write Mach-O binary file"""
        binary = bytearray()

        # Align code and data
        while len(self.code) % 16 != 0:
            self.code.append(0)
        while len(self.data) % 16 != 0:
            self.data.append(0)

        # Sizes from config
        sizes = self.macho['cmdSizes']
        segment_cmd_size = sizes['segment']
        section_size = sizes['section']
        dylinker_cmd_size = sizes['dylinker']
        build_version_cmd_size = sizes['buildVersion']
        symtab_cmd_size = sizes['symtab']
        chained_fixups_cmd_size = sizes['chainedFixups']
        export_trie_cmd_size = sizes['exportTrie']
        main_cmd_size = sizes['main']

        ncmds = 9
        sizeofcmds = (segment_cmd_size +
                      (segment_cmd_size + 2*section_size) +
                      segment_cmd_size +
                      dylinker_cmd_size +
                      build_version_cmd_size +
                      symtab_cmd_size +
                      chained_fixups_cmd_size +
                      export_trie_cmd_size +
                      main_cmd_size)

        page_size = self.macho['pageSize']
        text_start = self._hex(self.macho['textStart'])

        text_file_off = 0
        code_file_offset = page_size
        code_vm_addr = text_start + code_file_offset
        code_size = len(self.code)

        data_file_offset = code_file_offset + ((code_size + 15) // 16) * 16
        data_vm_addr = text_start + data_file_offset

        text_end_offset = data_file_offset + len(self.data)
        text_file_size = ((text_end_offset + page_size - 1) // page_size) * page_size
        text_vm_size = text_file_size

        linkedit_file_off = text_file_size
        linkedit_file_size = page_size
        linkedit_vm_addr = text_start + linkedit_file_off
        linkedit_vm_size = page_size

        # Fix up ADRP/ADD for data references
        data_page_offset = data_vm_addr & 0xFFF
        i = 0
        while i < len(self.code) - 8:
            inst = struct.unpack('<I', self.code[i:i+4])[0]
            if (inst & 0x9F000000) == 0x90000000:  # ADRP
                pc = code_vm_addr + i
                pc_page = pc & ~0xFFF
                target_page = data_vm_addr & ~0xFFF
                page_delta = target_page - pc_page
                immhi = (page_delta >> 14) & 0x7FFFF
                immlo = (page_delta >> 12) & 0x3
                rd = inst & 0x1F
                new_inst = 0x90000000 | (immlo << 29) | (immhi << 5) | rd
                self.code[i:i+4] = struct.pack('<I', new_inst)

                # Fix up ADD instruction
                add_inst = struct.unpack('<I', self.code[i+4:i+8])[0]
                if (add_inst & 0xFF800000) == 0x91000000:
                    existing_off = (add_inst >> 10) & 0xFFF
                    new_off = (data_page_offset + existing_off) & 0xFFF
                    new_add_inst = (add_inst & 0xFFC003FF) | (new_off << 10)
                    self.code[i+4:i+8] = struct.pack('<I', new_add_inst)
            i += 4

        # Mach-O header
        binary.extend(struct.pack('<I', self._hex(self.macho['magic'])))
        binary.extend(struct.pack('<I', self._hex(self.macho['cputype'])))
        binary.extend(struct.pack('<I', self._hex(self.macho['cpusubtype'])))
        binary.extend(struct.pack('<I', self._hex(self.macho['filetype'])))
        binary.extend(struct.pack('<I', ncmds))
        binary.extend(struct.pack('<I', sizeofcmds))
        binary.extend(struct.pack('<I', self._hex(self.macho['flags'])))
        binary.extend(struct.pack('<I', 0))

        lc = self.macho['loadCommands']

        # LC_SEGMENT_64 __PAGEZERO
        binary.extend(struct.pack('<I', self._hex(lc['LC_SEGMENT_64'])))
        binary.extend(struct.pack('<I', segment_cmd_size))
        binary.extend(self._pad_string('__PAGEZERO', 16))
        binary.extend(struct.pack('<Q', 0))
        binary.extend(struct.pack('<Q', text_start))
        binary.extend(struct.pack('<Q', 0))
        binary.extend(struct.pack('<Q', 0))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', 0))

        # LC_SEGMENT_64 __TEXT
        binary.extend(struct.pack('<I', self._hex(lc['LC_SEGMENT_64'])))
        binary.extend(struct.pack('<I', segment_cmd_size + 2*section_size))
        binary.extend(self._pad_string('__TEXT', 16))
        binary.extend(struct.pack('<Q', text_start))
        binary.extend(struct.pack('<Q', text_vm_size))
        binary.extend(struct.pack('<Q', text_file_off))
        binary.extend(struct.pack('<Q', text_file_size))
        vm_prot = self.macho['vmProt']
        binary.extend(struct.pack('<I', vm_prot['read'] | vm_prot['execute']))
        binary.extend(struct.pack('<I', vm_prot['read'] | vm_prot['execute']))
        binary.extend(struct.pack('<I', 2))
        binary.extend(struct.pack('<I', 0))

        # __text section
        binary.extend(self._pad_string('__text', 16))
        binary.extend(self._pad_string('__TEXT', 16))
        binary.extend(struct.pack('<Q', code_vm_addr))
        binary.extend(struct.pack('<Q', code_size))
        binary.extend(struct.pack('<I', code_file_offset))
        binary.extend(struct.pack('<I', 4))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', self._hex(self.macho['sectionTypes']['code'])))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', 0))

        # __cstring section
        binary.extend(self._pad_string('__cstring', 16))
        binary.extend(self._pad_string('__TEXT', 16))
        binary.extend(struct.pack('<Q', data_vm_addr))
        binary.extend(struct.pack('<Q', len(self.data)))
        binary.extend(struct.pack('<I', data_file_offset))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', self._hex(self.macho['sectionTypes']['cstring'])))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', 0))

        # LC_SEGMENT_64 __LINKEDIT
        binary.extend(struct.pack('<I', self._hex(lc['LC_SEGMENT_64'])))
        binary.extend(struct.pack('<I', segment_cmd_size))
        binary.extend(self._pad_string('__LINKEDIT', 16))
        binary.extend(struct.pack('<Q', linkedit_vm_addr))
        binary.extend(struct.pack('<Q', linkedit_vm_size))
        binary.extend(struct.pack('<Q', linkedit_file_off))
        binary.extend(struct.pack('<Q', linkedit_file_size))
        binary.extend(struct.pack('<I', vm_prot['read']))
        binary.extend(struct.pack('<I', vm_prot['read']))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', 0))

        # LC_LOAD_DYLINKER
        binary.extend(struct.pack('<I', self._hex(lc['LC_LOAD_DYLINKER'])))
        binary.extend(struct.pack('<I', dylinker_cmd_size))
        binary.extend(struct.pack('<I', 12))
        binary.extend(self._pad_string(self.macho['dylinkerPath'], 32))

        # LC_BUILD_VERSION
        binary.extend(struct.pack('<I', self._hex(lc['LC_BUILD_VERSION'])))
        binary.extend(struct.pack('<I', build_version_cmd_size))
        binary.extend(struct.pack('<I', 1))  # platform = MACOS
        binary.extend(struct.pack('<I', self._hex(self.macho['minOS'])))
        binary.extend(struct.pack('<I', self._hex(self.macho['sdk'])))
        binary.extend(struct.pack('<I', 0))

        # LC_SYMTAB
        binary.extend(struct.pack('<I', self._hex(lc['LC_SYMTAB'])))
        binary.extend(struct.pack('<I', symtab_cmd_size))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', 0))
        binary.extend(struct.pack('<I', 0))

        # LC_DYLD_CHAINED_FIXUPS
        chained_fixups_offset = linkedit_file_off
        chained_fixups_size = 48
        binary.extend(struct.pack('<I', self._hex(lc['LC_DYLD_CHAINED_FIXUPS'])))
        binary.extend(struct.pack('<I', chained_fixups_cmd_size))
        binary.extend(struct.pack('<I', chained_fixups_offset))
        binary.extend(struct.pack('<I', chained_fixups_size))

        # LC_DYLD_EXPORTS_TRIE
        export_trie_offset = chained_fixups_offset + chained_fixups_size
        export_trie_size = 8
        binary.extend(struct.pack('<I', self._hex(lc['LC_DYLD_EXPORTS_TRIE'])))
        binary.extend(struct.pack('<I', export_trie_cmd_size))
        binary.extend(struct.pack('<I', export_trie_offset))
        binary.extend(struct.pack('<I', export_trie_size))

        # LC_MAIN
        binary.extend(struct.pack('<I', self._hex(lc['LC_MAIN'])))
        binary.extend(struct.pack('<I', main_cmd_size))
        binary.extend(struct.pack('<Q', code_file_offset + main_offset))
        binary.extend(struct.pack('<Q', 0))

        # Pad to code start
        while len(binary) < code_file_offset:
            binary.append(0)

        binary.extend(self.code)

        # Pad between code and data
        while len(binary) < data_file_offset:
            binary.append(0)

        binary.extend(self.data)

        # Pad to page boundary
        while len(binary) < text_file_size:
            binary.append(0)

        # __LINKEDIT data: chained fixups
        binary.extend(struct.pack('<I', 0))   # fixups_version
        binary.extend(struct.pack('<I', 28))  # starts_offset
        binary.extend(struct.pack('<I', 44))  # imports_offset
        binary.extend(struct.pack('<I', 44))  # symbols_offset
        binary.extend(struct.pack('<I', 0))   # imports_count
        binary.extend(struct.pack('<I', 1))   # imports_format
        binary.extend(struct.pack('<I', 0))   # symbols_format

        # dyld_chained_starts_in_image
        binary.extend(struct.pack('<I', 3))   # seg_count
        binary.extend(struct.pack('<I', 0))   # seg_info_offset[0]
        binary.extend(struct.pack('<I', 0))   # seg_info_offset[1]
        binary.extend(struct.pack('<I', 0))   # seg_info_offset[2]

        # Pad to 48 bytes
        while len(binary) < text_file_size + 48:
            binary.append(0)

        # Export trie
        binary.append(0x00)
        binary.append(0x00)
        while len(binary) < text_file_size + 48 + 8:
            binary.append(0)

        # Pad rest of __LINKEDIT
        while len(binary) < text_file_size + linkedit_file_size:
            binary.append(0)

        # Write file
        with open(path, 'wb') as f:
            f.write(binary)
        os.chmod(path, 0o755)

    def _pad_string(self, s, length):
        """Pad string to fixed length"""
        result = s.encode('utf-8')
        result = result[:length]
        return result + b'\x00' * (length - len(result))
