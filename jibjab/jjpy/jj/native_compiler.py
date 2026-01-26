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
    FuncDef, FuncCall, BinaryOp, Literal, VarRef
)


class BranchType(Enum):
    B = 'b'
    BL = 'bl'
    BEQ = 'beq'
    BNE = 'bne'
    BGE = 'bge'
    BLE = 'ble'


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

        # Generate helper: print_int routine
        self.print_int_offset = len(self.code)
        self._gen_print_int_routine()

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
        self._emit(self._hex(self.inst['prologue']['sub_sp_64']))

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

    def _gen_func(self, node):
        """Generate function code"""
        self.current_func = node.name
        self.label_offsets[f'_{node.name}'] = len(self.code)

        self._emit(self._hex(self.inst['prologue']['stp_fp_lr']))
        self._emit(self._hex(self.inst['prologue']['stp_x19_x20']))
        self._emit(self._hex(self.inst['prologue']['mov_fp_sp']))
        self._emit(self._hex(self.inst['prologue']['sub_sp_64']))

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
        self._emit(self._hex(self.inst['epilogue']['add_sp_64']))
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

    def _gen_print(self, node):
        """Generate print statement"""
        if isinstance(node.expr, Literal) and isinstance(node.expr.value, str):
            # Print string using write syscall
            str_with_newline = node.expr.value + "\n"
            str_off = self._add_string(str_with_newline)
            str_len = len(str_with_newline.encode('utf-8'))

            self._emit(self._hex(self.inst['moves']['mov_x0_1']))
            self._emit_adrp_add(1, str_off)
            self._emit_mov_imm(2, str_len)
            self._emit(self._hex(self.inst['syscall']['movz_x16_4']))
            self._emit(self._hex(self.inst['syscall']['movk_x16_0x200_lsl16']))
            self._emit(self._hex(self.inst['syscall']['svc']))
        else:
            # Print integer - call print_int routine
            self._gen_expr(node.expr)
            delta = (self.print_int_offset - len(self.code)) // 4
            d = delta & 0xFFFFFFFF
            self._emit(0x94000000 | (d & 0x3FFFFFF))

    def _gen_var_decl(self, node):
        """Generate variable declaration"""
        self._gen_expr(node.value)
        if node.name not in self.variables:
            self.variables[node.name] = self.stack_offset
            self.stack_offset += 8
        self._emit_store(0, self.variables[node.name])

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
            self._gen_expr(node.condition.left)
            self._emit(self._hex(self.inst['moves']['mov_w9_w0']))
            self._gen_expr(node.condition.right)
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
        elif isinstance(node, FuncCall):
            if node.name in self.functions:
                for i, arg in enumerate(node.args[:8]):
                    self._gen_expr(arg)
                    self._emit(0x2A0003E0 | (19 + i))
                for i in range(min(len(node.args), 8)):
                    self._emit(0x2A0003E0 | i | ((19 + i) << 16))
                self._add_branch(f'_{node.name}', BranchType.BL)

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
        """Emit store instruction"""
        off9 = (-offset - 16) & 0x1FF
        self._emit(0xB8000000 | (off9 << 12) | (29 << 5) | reg)

    def _emit_load(self, reg, offset):
        """Emit load instruction"""
        off9 = (-offset - 16) & 0x1FF
        self._emit(0xB8400000 | (off9 << 12) | (29 << 5) | reg)

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
