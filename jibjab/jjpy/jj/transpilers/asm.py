"""
JibJab ARM64 Assembly Transpiler - Converts JJ to ARM64 Assembly (macOS)
Uses emit values from common/jj.json
"""

from ..lexer import JJ, load_target_config
from ..ast import (
    ASTNode, Program, PrintStmt, VarDecl, VarRef, Literal,
    BinaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt
)

T = load_target_config('asm')
OP = JJ['operators']


class AssemblyTranspiler:
    def __init__(self):
        self.asm_lines = []
        self.strings = []
        self.label_counter = 0
        self.variables = {}
        self.stack_offset = 0
        self.functions = {}
        self.current_func = None

    def transpile(self, program: Program) -> str:
        self.asm_lines = []
        self.strings = []
        self.label_counter = 0
        self.variables = {}
        self.stack_offset = 0
        self.functions = {}

        # Collect functions first
        for stmt in program.statements:
            if isinstance(stmt, FuncDef):
                self.functions[stmt.name] = stmt

        # Header
        self.asm_lines.append("// JibJab -> ARM64 Assembly (macOS)")
        self.asm_lines.append(".global _main")
        self.asm_lines.append(".align 4")
        self.asm_lines.append("")

        # Generate function code
        for stmt in program.statements:
            if isinstance(stmt, FuncDef):
                self.gen_func(stmt)

        # Generate main
        main_stmts = [s for s in program.statements if not isinstance(s, FuncDef)]
        self.asm_lines.append("_main:")
        self.asm_lines.append("    stp x29, x30, [sp, #-16]!")
        self.asm_lines.append("    stp x19, x20, [sp, #-16]!")
        self.asm_lines.append("    stp x21, x22, [sp, #-16]!")
        self.asm_lines.append("    stp x23, x24, [sp, #-16]!")
        self.asm_lines.append("    stp x25, x26, [sp, #-16]!")
        self.asm_lines.append("    stp x27, x28, [sp, #-16]!")
        self.asm_lines.append("    mov x29, sp")

        # Allocate stack for variables
        max_vars = 16
        self.asm_lines.append(f"    sub sp, sp, #{max_vars * 8 + 16}")
        self.stack_offset = 16
        self.variables = {}

        for stmt in main_stmts:
            self.gen_stmt(stmt)

        # Return 0
        self.asm_lines.append("    mov w0, #0")
        self.asm_lines.append(f"    add sp, sp, #{max_vars * 8 + 16}")
        self.asm_lines.append("    ldp x27, x28, [sp], #16")
        self.asm_lines.append("    ldp x25, x26, [sp], #16")
        self.asm_lines.append("    ldp x23, x24, [sp], #16")
        self.asm_lines.append("    ldp x21, x22, [sp], #16")
        self.asm_lines.append("    ldp x19, x20, [sp], #16")
        self.asm_lines.append("    ldp x29, x30, [sp], #16")
        self.asm_lines.append("    ret")
        self.asm_lines.append("")

        # Data section
        self.asm_lines.append(".data")
        self.asm_lines.append("_fmt_int:")
        self.asm_lines.append('    .asciz "%d\\n"')
        self.asm_lines.append("_fmt_str:")
        self.asm_lines.append('    .asciz "%s\\n"')

        for item in self.strings:
            label, value, add_newline = item
            escaped = value.replace('\\', '\\\\').replace('"', '\\"')
            if add_newline:
                escaped += '\\n'
            self.asm_lines.append(f"{label}:")
            self.asm_lines.append(f'    .asciz "{escaped}"')

        return '\n'.join(self.asm_lines)

    def new_label(self, prefix: str = "L") -> str:
        self.label_counter += 1
        return f"_{prefix}{self.label_counter}"

    def add_string(self, value: str) -> str:
        label = self.new_label("str")
        self.strings.append((label, value, False))
        return label

    def add_string_raw(self, value: str) -> str:
        label = self.new_label("str")
        self.strings.append((label, value, True))
        return label

    def gen_func(self, node: FuncDef):
        self.current_func = node.name
        self.asm_lines.append(f"_{node.name}:")
        self.asm_lines.append("    stp x29, x30, [sp, #-16]!")
        self.asm_lines.append("    stp x19, x20, [sp, #-16]!")
        self.asm_lines.append("    stp x21, x22, [sp, #-16]!")
        self.asm_lines.append("    stp x23, x24, [sp, #-16]!")
        self.asm_lines.append("    stp x25, x26, [sp, #-16]!")
        self.asm_lines.append("    stp x27, x28, [sp, #-16]!")
        self.asm_lines.append("    mov x29, sp")

        max_vars = 16
        self.asm_lines.append(f"    sub sp, sp, #{max_vars * 8 + 16}")

        old_vars = self.variables.copy()
        old_offset = self.stack_offset
        self.variables = {}
        self.stack_offset = 16

        # Store parameters
        param_regs = ['w0', 'w1', 'w2', 'w3', 'w4', 'w5', 'w6', 'w7']
        for i, param in enumerate(node.params):
            self.variables[param] = self.stack_offset
            self.asm_lines.append(f"    stur {param_regs[i]}, [x29, #-{self.stack_offset + 16}]")
            self.stack_offset += 8

        for stmt in node.body:
            self.gen_stmt(stmt)

        # Default return
        self.asm_lines.append("    mov w0, #0")
        self.asm_lines.append(f"_{node.name}_ret:")
        self.asm_lines.append(f"    add sp, sp, #{max_vars * 8 + 16}")
        self.asm_lines.append("    ldp x27, x28, [sp], #16")
        self.asm_lines.append("    ldp x25, x26, [sp], #16")
        self.asm_lines.append("    ldp x23, x24, [sp], #16")
        self.asm_lines.append("    ldp x21, x22, [sp], #16")
        self.asm_lines.append("    ldp x19, x20, [sp], #16")
        self.asm_lines.append("    ldp x29, x30, [sp], #16")
        self.asm_lines.append("    ret")
        self.asm_lines.append("")

        self.variables = old_vars
        self.stack_offset = old_offset

    def gen_stmt(self, node: ASTNode):
        if isinstance(node, PrintStmt):
            self.gen_print(node)
        elif isinstance(node, VarDecl):
            self.gen_var_decl(node)
        elif isinstance(node, LoopStmt):
            self.gen_loop(node)
        elif isinstance(node, IfStmt):
            self.gen_if(node)
        elif isinstance(node, ReturnStmt):
            self.gen_expr(node.value)
            self.asm_lines.append(f"    b _{self.current_func}_ret")

    def gen_print(self, node: PrintStmt):
        expr = node.expr
        if isinstance(expr, Literal) and isinstance(expr.value, str):
            str_label = self.add_string_raw(expr.value)
            self.asm_lines.append(f"    adrp x0, {str_label}@PAGE")
            self.asm_lines.append(f"    add x0, x0, {str_label}@PAGEOFF")
            self.asm_lines.append("    bl _printf")
        else:
            self.gen_expr(expr)
            self.asm_lines.append("    sxtw x0, w0")
            self.asm_lines.append("    str x0, [sp]")
            self.asm_lines.append("    adrp x0, _fmt_int@PAGE")
            self.asm_lines.append("    add x0, x0, _fmt_int@PAGEOFF")
            self.asm_lines.append("    bl _printf")

    def gen_var_decl(self, node: VarDecl):
        self.gen_expr(node.value)
        if node.name not in self.variables:
            self.variables[node.name] = self.stack_offset
            self.stack_offset += 8
        offset = self.variables[node.name]
        self.asm_lines.append(f"    stur w0, [x29, #-{offset + 16}]")

    def gen_loop(self, node: LoopStmt):
        if node.start is not None and node.end is not None:
            loop_start = self.new_label("loop")
            loop_end = self.new_label("endloop")

            self.gen_expr(node.start)
            if node.var not in self.variables:
                self.variables[node.var] = self.stack_offset
                self.stack_offset += 8
            var_offset = self.variables[node.var]
            self.asm_lines.append(f"    stur w0, [x29, #-{var_offset + 16}]")

            self.gen_expr(node.end)
            end_offset = self.stack_offset
            self.stack_offset += 8
            self.asm_lines.append(f"    stur w0, [x29, #-{end_offset + 16}]")

            self.asm_lines.append(f"{loop_start}:")
            self.asm_lines.append(f"    ldur w0, [x29, #-{var_offset + 16}]")
            self.asm_lines.append(f"    ldur w1, [x29, #-{end_offset + 16}]")
            self.asm_lines.append("    cmp w0, w1")
            self.asm_lines.append(f"    b.ge {loop_end}")

            for stmt in node.body:
                self.gen_stmt(stmt)

            self.asm_lines.append(f"    ldur w0, [x29, #-{var_offset + 16}]")
            self.asm_lines.append("    add w0, w0, #1")
            self.asm_lines.append(f"    stur w0, [x29, #-{var_offset + 16}]")
            self.asm_lines.append(f"    b {loop_start}")
            self.asm_lines.append(f"{loop_end}:")

    def gen_if(self, node: IfStmt):
        else_label = self.new_label("else")
        end_label = self.new_label("endif")

        self.gen_condition(node.condition, else_label)

        for stmt in node.then_body:
            self.gen_stmt(stmt)
        if node.else_body:
            self.asm_lines.append(f"    b {end_label}")

        self.asm_lines.append(f"{else_label}:")

        if node.else_body:
            for stmt in node.else_body:
                self.gen_stmt(stmt)
            self.asm_lines.append(f"{end_label}:")

    def gen_condition(self, node: ASTNode, false_label: str):
        if isinstance(node, BinaryOp):
            self.gen_expr(node.left)
            self.asm_lines.append("    mov w9, w0")
            self.gen_expr(node.right)
            self.asm_lines.append("    cmp w9, w0")

            branches = {
                OP['eq']['emit']: 'b.ne',
                OP['neq']['emit']: 'b.eq',
                OP['lt']['emit']: 'b.ge',
                OP['gt']['emit']: 'b.le',
                OP['lte']['emit']: 'b.gt',
                OP['gte']['emit']: 'b.lt',
            }
            if node.op in branches:
                self.asm_lines.append(f"    {branches[node.op]} {false_label}")
            else:
                self.gen_expr(node)
                self.asm_lines.append("    cmp w0, #0")
                self.asm_lines.append(f"    b.eq {false_label}")
        else:
            self.gen_expr(node)
            self.asm_lines.append("    cmp w0, #0")
            self.asm_lines.append(f"    b.eq {false_label}")

    def gen_expr(self, node: ASTNode):
        if isinstance(node, Literal):
            if isinstance(node.value, int):
                if -65536 <= node.value <= 65535:
                    self.asm_lines.append(f"    mov w0, #{node.value}")
                else:
                    self.asm_lines.append(f"    movz w0, #{node.value & 0xFFFF}")
                    if node.value > 65535:
                        self.asm_lines.append(f"    movk w0, #{(node.value >> 16) & 0xFFFF}, lsl #16")
            elif isinstance(node.value, bool):
                self.asm_lines.append(f"    mov w0, #{1 if node.value else 0}")
            else:
                self.asm_lines.append("    mov w0, #0")

        elif isinstance(node, VarRef):
            if node.name in self.variables:
                offset = self.variables[node.name]
                self.asm_lines.append(f"    ldur w0, [x29, #-{offset + 16}]")
            else:
                self.asm_lines.append("    mov w0, #0")

        elif isinstance(node, BinaryOp):
            self.gen_expr(node.left)
            self.asm_lines.append("    str w0, [sp, #-16]!")
            self.gen_expr(node.right)
            self.asm_lines.append("    mov w1, w0")
            self.asm_lines.append("    ldr w0, [sp], #16")

            if node.op == OP['add']['emit']:
                self.asm_lines.append("    add w0, w0, w1")
            elif node.op == OP['sub']['emit']:
                self.asm_lines.append("    sub w0, w0, w1")
            elif node.op == OP['mul']['emit']:
                self.asm_lines.append("    mul w0, w0, w1")
            elif node.op == OP['div']['emit']:
                self.asm_lines.append("    sdiv w0, w0, w1")
            elif node.op == OP['mod']['emit']:
                self.asm_lines.append("    sdiv w2, w0, w1")
                self.asm_lines.append("    msub w0, w2, w1, w0")
            elif node.op == OP['eq']['emit']:
                self.asm_lines.append("    cmp w0, w1")
                self.asm_lines.append("    cset w0, eq")
            elif node.op == OP['neq']['emit']:
                self.asm_lines.append("    cmp w0, w1")
                self.asm_lines.append("    cset w0, ne")
            elif node.op == OP['lt']['emit']:
                self.asm_lines.append("    cmp w0, w1")
                self.asm_lines.append("    cset w0, lt")
            elif node.op == OP['gt']['emit']:
                self.asm_lines.append("    cmp w0, w1")
                self.asm_lines.append("    cset w0, gt")
            elif node.op == OP['lte']['emit']:
                self.asm_lines.append("    cmp w0, w1")
                self.asm_lines.append("    cset w0, le")
            elif node.op == OP['gte']['emit']:
                self.asm_lines.append("    cmp w0, w1")
                self.asm_lines.append("    cset w0, ge")
            elif node.op == OP['and']['emit']:
                self.asm_lines.append("    and w0, w0, w1")
            elif node.op == OP['or']['emit']:
                self.asm_lines.append("    orr w0, w0, w1")

        elif isinstance(node, FuncCall):
            func = self.functions.get(node.name)
            if func:
                arg_regs = ['w20', 'w21', 'w22', 'w23', 'w24', 'w25', 'w26', 'w27']
                for i, arg in enumerate(node.args[:8]):
                    self.gen_expr(arg)
                    self.asm_lines.append(f"    mov {arg_regs[i]}, w0")
                for i in range(len(node.args[:8])):
                    self.asm_lines.append(f"    mov w{i}, {arg_regs[i]}")
                self.asm_lines.append(f"    bl _{node.name}")
