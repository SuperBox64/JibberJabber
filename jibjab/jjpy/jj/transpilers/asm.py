"""
JibJab ARM64 Assembly Transpiler - Converts JJ to ARM64 Assembly (macOS)
Uses emit values from common/jj.json
"""

from ..lexer import JJ, load_target_config
from ..ast import (
    ASTNode, Program, PrintStmt, LogStmt, VarDecl, VarRef, Literal,
    BinaryOp, LoopStmt, IfStmt, TryStmt, FuncDef, FuncCall, ReturnStmt, ThrowStmt,
    EnumDef, ArrayLiteral, IndexAccess, TupleLiteral, DictLiteral,
    UnaryOp, StringInterpolation
)

T = load_target_config('asm')
OP = JJ['operators']


class AssemblyTranspiler:
    def __init__(self):
        self.asm_lines = []
        self.strings = []
        self.doubles = []
        self.label_counter = 0
        self.variables = {}
        self.float_vars = set()
        self.stack_offset = 0
        self.functions = {}
        self.current_func = None
        self.enums = {}              # enum name -> {case_name: index}
        self.enum_case_strings = {}  # enum name -> [case_names in order]
        self.enum_case_labels = {}   # enum name -> {case_name: string label}
        self.enum_var_labels = {}    # var name -> (enum_name, case_name)
        self.arrays = {}             # var name -> {base_offset, count, is_string}
        self.nested_arrays = {}      # var name -> (outer_count, inner_size)
        self.tuples = {}             # var name -> {base_offset, count, elem_types}
        self.dicts = {}              # var name -> {keys, value_offsets, value_types}
        self.bool_vars = set()       # var names holding booleans

    def transpile(self, program: Program) -> str:
        self.asm_lines = []
        self.strings = []
        self.doubles = []
        self.label_counter = 0
        self.variables = {}
        self.float_vars = set()
        self.stack_offset = 0
        self.functions = {}
        self.enums = {}
        self.enum_case_strings = {}
        self.enum_case_labels = {}
        self.enum_var_labels = {}
        self.arrays = {}
        self.nested_arrays = {}
        self.tuples = {}
        self.dicts = {}

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

        # Allocate stack for variables (larger for arrays/tuples/dicts)
        max_vars = 64
        self.asm_lines.append(f"    sub sp, sp, #{max_vars * 8 + 16}")
        self.stack_offset = 16
        self.variables = {}
        self.float_vars = set()
        self.arrays = {}
        self.nested_arrays = {}
        self.tuples = {}
        self.dicts = {}
        self.enum_var_labels = {}
        self.bool_vars = set()

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
        self.asm_lines.append("_fmt_float:")
        self.asm_lines.append('    .asciz "%g\\n"')

        for item in self.strings:
            label, value, add_newline = item
            escaped = value.replace('\\', '\\\\').replace('"', '\\"')
            if add_newline:
                escaped += '\\n'
            self.asm_lines.append(f"{label}:")
            self.asm_lines.append(f'    .asciz "{escaped}"')

        # Double constants (8-byte aligned)
        if self.doubles:
            self.asm_lines.append(".align 3")
            for label, value in self.doubles:
                self.asm_lines.append(f"{label}:")
                self.asm_lines.append(f"    .double {value}")

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

    def add_double(self, value: float) -> str:
        label = self.new_label("dbl")
        self.doubles.append((label, value))
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

        max_vars = 64
        self.asm_lines.append(f"    sub sp, sp, #{max_vars * 8 + 16}")

        old_vars = self.variables.copy()
        old_offset = self.stack_offset
        old_arrays = self.arrays.copy()
        old_float_vars = self.float_vars.copy()
        self.variables = {}
        self.stack_offset = 16
        self.arrays = {}
        self.float_vars = set()

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
        self.arrays = old_arrays
        self.float_vars = old_float_vars

    def gen_stmt(self, node: ASTNode):
        if isinstance(node, PrintStmt):
            self.gen_print(node)
        elif isinstance(node, LogStmt):
            # ASM: no stderr, use printf (same as print)
            self.gen_print(PrintStmt(expr=node.expr))
        elif isinstance(node, VarDecl):
            self.gen_var_decl(node)
        elif isinstance(node, LoopStmt):
            self.gen_loop(node)
        elif isinstance(node, IfStmt):
            self.gen_if(node)
        elif isinstance(node, ThrowStmt):
            self.gen_expr(node.value)
        elif isinstance(node, ReturnStmt):
            self.gen_expr(node.value)
            self.asm_lines.append(f"    b _{self.current_func}_ret")
        elif isinstance(node, TryStmt):
            end_label = self.new_label("endtry")
            for stmt in node.try_body:
                self.gen_stmt(stmt)
            self.asm_lines.append(f"    b {end_label}")
            if node.oops_body:
                for stmt in node.oops_body:
                    self.gen_stmt(stmt)
            self.asm_lines.append(f"{end_label}:")
        elif isinstance(node, EnumDef):
            case_values = {}
            case_labels = {}
            for i, case_name in enumerate(node.cases):
                case_values[case_name] = i
                label = self.add_string(case_name)
                case_labels[case_name] = label
            self.enums[node.name] = case_values
            self.enum_case_strings[node.name] = node.cases
            self.enum_case_labels[node.name] = case_labels

    def is_enum_access(self, node):
        """Check if node is an enum access like Color['Red']"""
        if isinstance(node, IndexAccess) and isinstance(node.array, VarRef):
            if node.array.name in self.enums:
                if isinstance(node.index, Literal) and isinstance(node.index.value, str):
                    return (node.array.name, node.index.value)
        return None

    def gen_print(self, node: PrintStmt):
        expr = node.expr
        if isinstance(expr, StringInterpolation):
            fmt = ''
            var_names = []
            for kind, text in expr.parts:
                if kind == 'literal':
                    fmt += text.replace('%', '%%')
                else:
                    if text in self.float_vars:
                        fmt += '%g'
                    elif text in self.enum_var_labels:
                        fmt += '%s'
                    elif text in self.bool_vars:
                        fmt += '%s'
                    else:
                        fmt += '%d'
                    var_names.append(text)
            fmt_label = self.add_string_raw(fmt)
            if not var_names:
                self.asm_lines.append(f"    adrp x0, {fmt_label}@PAGE")
                self.asm_lines.append(f"    add x0, x0, {fmt_label}@PAGEOFF")
                self.asm_lines.append("    bl _printf")
            else:
                for i, name in enumerate(var_names):
                    if name in self.variables:
                        offset = self.variables[name]
                        if name in self.float_vars:
                            self.asm_lines.append(f"    ldur d{i}, [x29, #-{offset + 16}]")
                            self.asm_lines.append(f"    str d{i}, [sp, #{i * 8}]")
                        elif name in self.bool_vars or name in self.enum_var_labels:
                            self.asm_lines.append(f"    ldur x0, [x29, #-{offset + 16}]")
                            self.asm_lines.append(f"    str x0, [sp, #{i * 8}]")
                        else:
                            self.asm_lines.append(f"    ldur w0, [x29, #-{offset + 16}]")
                            self.asm_lines.append("    sxtw x0, w0")
                            self.asm_lines.append(f"    str x0, [sp, #{i * 8}]")
                self.asm_lines.append(f"    adrp x0, {fmt_label}@PAGE")
                self.asm_lines.append(f"    add x0, x0, {fmt_label}@PAGEOFF")
                self.asm_lines.append("    bl _printf")
            return
        if isinstance(expr, Literal) and isinstance(expr.value, str):
            str_label = self.add_string_raw(expr.value)
            self.asm_lines.append(f"    adrp x0, {str_label}@PAGE")
            self.asm_lines.append(f"    add x0, x0, {str_label}@PAGEOFF")
            self.asm_lines.append("    bl _printf")
        elif isinstance(expr, VarRef) and expr.name in self.bool_vars:
            # Print bool variable as string "true"/"false"
            if expr.name in self.variables:
                offset = self.variables[expr.name]
                self.asm_lines.append(f"    ldur x0, [x29, #-{offset + 16}]")
                self.asm_lines.append("    str x0, [sp]")
                self.asm_lines.append("    adrp x0, _fmt_str@PAGE")
                self.asm_lines.append("    add x0, x0, _fmt_str@PAGEOFF")
                self.asm_lines.append("    bl _printf")
        elif isinstance(expr, VarRef) and expr.name in self.enum_var_labels:
            # Print enum variable by name (stored as string pointer)
            if expr.name in self.variables:
                offset = self.variables[expr.name]
                self.asm_lines.append(f"    ldur x0, [x29, #-{offset + 16}]")
                self.asm_lines.append("    str x0, [sp]")
                self.asm_lines.append("    adrp x0, _fmt_str@PAGE")
                self.asm_lines.append("    add x0, x0, _fmt_str@PAGEOFF")
                self.asm_lines.append("    bl _printf")
        elif isinstance(expr, IndexAccess) and isinstance(expr.array, VarRef) and expr.array.name in self.enums:
            # Print enum case by name: Color["Red"] -> "Red"
            if isinstance(expr.index, Literal) and isinstance(expr.index.value, str):
                case_labels = self.enum_case_labels.get(expr.array.name, {})
                label = case_labels.get(expr.index.value)
                if label:
                    self.asm_lines.append(f"    adrp x0, {label}@PAGE")
                    self.asm_lines.append(f"    add x0, x0, {label}@PAGEOFF")
                    self.asm_lines.append("    str x0, [sp]")
                    self.asm_lines.append("    adrp x0, _fmt_str@PAGE")
                    self.asm_lines.append("    add x0, x0, _fmt_str@PAGEOFF")
                    self.asm_lines.append("    bl _printf")
        elif isinstance(expr, VarRef) and expr.name in self.enums:
            # Print full enum
            case_names = self.enum_case_strings.get(expr.name, list(self.enums[expr.name].keys()))
            items = ', '.join(f'"{n}": {n}' for n in case_names)
            enum_str = '{' + items + '}'
            str_label = self.add_string_raw(enum_str)
            self.asm_lines.append(f"    adrp x0, {str_label}@PAGE")
            self.asm_lines.append(f"    add x0, x0, {str_label}@PAGEOFF")
            self.asm_lines.append("    bl _printf")
        elif isinstance(expr, VarRef) and expr.name in self.tuples:
            self.gen_print_tuple_full(expr.name, self.tuples[expr.name])
        elif isinstance(expr, IndexAccess) and isinstance(expr.array, VarRef) and expr.array.name in self.tuples:
            # Print single tuple element
            info = self.tuples[expr.array.name]
            if isinstance(expr.index, Literal) and isinstance(expr.index.value, int):
                idx = expr.index.value
                elem_offset = info['base_offset'] + idx * 8
                elem_type = info['elem_types'][idx]
                if elem_type in ('string', 'bool'):
                    self.asm_lines.append(f"    ldur x0, [x29, #-{elem_offset + 16}]")
                    self.asm_lines.append("    str x0, [sp]")
                    self.asm_lines.append("    adrp x0, _fmt_str@PAGE")
                    self.asm_lines.append("    add x0, x0, _fmt_str@PAGEOFF")
                    self.asm_lines.append("    bl _printf")
                else:
                    self.asm_lines.append(f"    ldur w0, [x29, #-{elem_offset + 16}]")
                    self.asm_lines.append("    sxtw x0, w0")
                    self.asm_lines.append("    str x0, [sp]")
                    self.asm_lines.append("    adrp x0, _fmt_int@PAGE")
                    self.asm_lines.append("    add x0, x0, _fmt_int@PAGEOFF")
                    self.asm_lines.append("    bl _printf")
        elif isinstance(expr, VarRef) and expr.name in self.dicts:
            info = self.dicts[expr.name]
            if not info['keys']:
                str_label = self.add_string_raw("{}")
                self.asm_lines.append(f"    adrp x0, {str_label}@PAGE")
                self.asm_lines.append(f"    add x0, x0, {str_label}@PAGEOFF")
                self.asm_lines.append("    bl _printf")
            else:
                str_label = self.add_string_raw("{...}")
                self.asm_lines.append(f"    adrp x0, {str_label}@PAGE")
                self.asm_lines.append(f"    add x0, x0, {str_label}@PAGEOFF")
                self.asm_lines.append("    bl _printf")
        elif isinstance(expr, IndexAccess) and isinstance(expr.array, VarRef) and expr.array.name in self.dicts:
            # Dict key access
            info = self.dicts[expr.array.name]
            if isinstance(expr.index, Literal) and isinstance(expr.index.value, str):
                key_str = expr.index.value
                if key_str in info['keys']:
                    key_idx = info['keys'].index(key_str)
                    val_offset = info['value_offsets'][key_idx]
                    val_type = info['value_types'][key_idx]
                    if val_type in ('string', 'bool'):
                        self.asm_lines.append(f"    ldur x0, [x29, #-{val_offset + 16}]")
                        self.asm_lines.append("    str x0, [sp]")
                        self.asm_lines.append("    adrp x0, _fmt_str@PAGE")
                        self.asm_lines.append("    add x0, x0, _fmt_str@PAGEOFF")
                        self.asm_lines.append("    bl _printf")
                    else:
                        self.asm_lines.append(f"    ldur w0, [x29, #-{val_offset + 16}]")
                        self.asm_lines.append("    sxtw x0, w0")
                        self.asm_lines.append("    str x0, [sp]")
                        self.asm_lines.append("    adrp x0, _fmt_int@PAGE")
                        self.asm_lines.append("    add x0, x0, _fmt_int@PAGEOFF")
                        self.asm_lines.append("    bl _printf")
        elif (isinstance(expr, IndexAccess) and isinstance(expr.array, IndexAccess)
              and isinstance(expr.array.array, VarRef)
              and expr.array.array.name in self.dicts):
            # Nested dict access: data["items"][0]
            var_name = expr.array.array.name
            if isinstance(expr.array.index, Literal) and isinstance(expr.array.index.value, str):
                key_str = expr.array.index.value
                synthetic = f"{var_name}.{key_str}"
                if synthetic in self.arrays:
                    arr_info = self.arrays[synthetic]
                    self.gen_array_load(synthetic, expr.index, arr_info, arr_info['is_string'])
                    if arr_info['is_string']:
                        self.asm_lines.append("    str x0, [sp]")
                        self.asm_lines.append("    adrp x0, _fmt_str@PAGE")
                        self.asm_lines.append("    add x0, x0, _fmt_str@PAGEOFF")
                    else:
                        self.asm_lines.append("    sxtw x0, w0")
                        self.asm_lines.append("    str x0, [sp]")
                        self.asm_lines.append("    adrp x0, _fmt_int@PAGE")
                        self.asm_lines.append("    add x0, x0, _fmt_int@PAGEOFF")
                    self.asm_lines.append("    bl _printf")
        elif isinstance(expr, VarRef) and expr.name in self.arrays:
            # Print entire array with brackets: [elem, elem, ...]
            arr_info = self.arrays[expr.name]
            if expr.name in self.nested_arrays:
                # Nested (2D) array: [[1, 2], [3, 4]]
                nested = self.nested_arrays[expr.name]
                outer_count, inner_size = nested

                open_label = self.add_string("[")
                self.asm_lines.append(f"    adrp x0, {open_label}@PAGE")
                self.asm_lines.append(f"    add x0, x0, {open_label}@PAGEOFF")
                self.asm_lines.append("    bl _printf")

                for outer in range(outer_count):
                    if outer > 0:
                        sep_label = self.add_string(", ")
                        self.asm_lines.append(f"    adrp x0, {sep_label}@PAGE")
                        self.asm_lines.append(f"    add x0, x0, {sep_label}@PAGEOFF")
                        self.asm_lines.append("    bl _printf")
                    inner_open = self.add_string("[")
                    self.asm_lines.append(f"    adrp x0, {inner_open}@PAGE")
                    self.asm_lines.append(f"    add x0, x0, {inner_open}@PAGEOFF")
                    self.asm_lines.append("    bl _printf")

                    for inner in range(inner_size):
                        if inner > 0:
                            sep_label = self.add_string(", ")
                            self.asm_lines.append(f"    adrp x0, {sep_label}@PAGE")
                            self.asm_lines.append(f"    add x0, x0, {sep_label}@PAGEOFF")
                            self.asm_lines.append("    bl _printf")
                        flat_idx = outer * inner_size + inner
                        elem_offset = arr_info['base_offset'] + flat_idx * 8
                        self.asm_lines.append(f"    ldur w1, [x29, #-{elem_offset + 16}]")
                        self.asm_lines.append("    sxtw x1, w1")
                        self.asm_lines.append("    str x1, [sp]")
                        fmt_label = self.add_string("%d")
                        self.asm_lines.append(f"    adrp x0, {fmt_label}@PAGE")
                        self.asm_lines.append(f"    add x0, x0, {fmt_label}@PAGEOFF")
                        self.asm_lines.append("    bl _printf")

                    inner_close = self.add_string("]")
                    self.asm_lines.append(f"    adrp x0, {inner_close}@PAGE")
                    self.asm_lines.append(f"    add x0, x0, {inner_close}@PAGEOFF")
                    self.asm_lines.append("    bl _printf")

                close_label = self.add_string_raw("]")
                self.asm_lines.append(f"    adrp x0, {close_label}@PAGE")
                self.asm_lines.append(f"    add x0, x0, {close_label}@PAGEOFF")
                self.asm_lines.append("    bl _printf")
            else:
                # Flat array: [1, 2, 3]
                open_label = self.add_string("[")
                self.asm_lines.append(f"    adrp x0, {open_label}@PAGE")
                self.asm_lines.append(f"    add x0, x0, {open_label}@PAGEOFF")
                self.asm_lines.append("    bl _printf")

                for i in range(arr_info['count']):
                    if i > 0:
                        sep_label = self.add_string(", ")
                        self.asm_lines.append(f"    adrp x0, {sep_label}@PAGE")
                        self.asm_lines.append(f"    add x0, x0, {sep_label}@PAGEOFF")
                        self.asm_lines.append("    bl _printf")
                    elem_offset = arr_info['base_offset'] + i * 8
                    if arr_info['is_string']:
                        self.asm_lines.append(f"    ldur x0, [x29, #-{elem_offset + 16}]")
                        self.asm_lines.append("    str x0, [sp]")
                        fmt_label = self.add_string("%s")
                        self.asm_lines.append(f"    adrp x0, {fmt_label}@PAGE")
                        self.asm_lines.append(f"    add x0, x0, {fmt_label}@PAGEOFF")
                        self.asm_lines.append("    bl _printf")
                    else:
                        self.asm_lines.append(f"    ldur w1, [x29, #-{elem_offset + 16}]")
                        self.asm_lines.append("    sxtw x1, w1")
                        self.asm_lines.append("    str x1, [sp]")
                        fmt_label = self.add_string("%d")
                        self.asm_lines.append(f"    adrp x0, {fmt_label}@PAGE")
                        self.asm_lines.append(f"    add x0, x0, {fmt_label}@PAGEOFF")
                        self.asm_lines.append("    bl _printf")

                close_label = self.add_string_raw("]")
                self.asm_lines.append(f"    adrp x0, {close_label}@PAGE")
                self.asm_lines.append(f"    add x0, x0, {close_label}@PAGEOFF")
                self.asm_lines.append("    bl _printf")
        elif isinstance(expr, IndexAccess) and isinstance(expr.array, VarRef) and expr.array.name in self.arrays:
            # Print single array element
            arr_info = self.arrays[expr.array.name]
            if arr_info['is_string']:
                self.gen_array_load(expr.array.name, expr.index, arr_info, True)
                self.asm_lines.append("    str x0, [sp]")
                self.asm_lines.append("    adrp x0, _fmt_str@PAGE")
                self.asm_lines.append("    add x0, x0, _fmt_str@PAGEOFF")
                self.asm_lines.append("    bl _printf")
            else:
                self.gen_array_load(expr.array.name, expr.index, arr_info, False)
                self.asm_lines.append("    sxtw x0, w0")
                self.asm_lines.append("    str x0, [sp]")
                self.asm_lines.append("    adrp x0, _fmt_int@PAGE")
                self.asm_lines.append("    add x0, x0, _fmt_int@PAGEOFF")
                self.asm_lines.append("    bl _printf")
        elif self.is_float_expr(expr):
            # Float expression
            self.gen_float_expr(expr)
            self.asm_lines.append("    str d0, [sp]")
            self.asm_lines.append("    adrp x0, _fmt_float@PAGE")
            self.asm_lines.append("    add x0, x0, _fmt_float@PAGEOFF")
            self.asm_lines.append("    bl _printf")
        else:
            self.gen_expr(expr)
            self.asm_lines.append("    sxtw x0, w0")
            self.asm_lines.append("    str x0, [sp]")
            self.asm_lines.append("    adrp x0, _fmt_int@PAGE")
            self.asm_lines.append("    add x0, x0, _fmt_int@PAGEOFF")
            self.asm_lines.append("    bl _printf")

    def gen_print_tuple_full(self, name, info):
        if info['count'] == 0:
            str_label = self.add_string_raw("()")
            self.asm_lines.append(f"    adrp x0, {str_label}@PAGE")
            self.asm_lines.append(f"    add x0, x0, {str_label}@PAGEOFF")
            self.asm_lines.append("    bl _printf")
            return

        # Print opening paren
        open_label = self.add_string("(")
        self.asm_lines.append(f"    adrp x0, {open_label}@PAGE")
        self.asm_lines.append(f"    add x0, x0, {open_label}@PAGEOFF")
        self.asm_lines.append("    bl _printf")

        for i in range(info['count']):
            elem_offset = info['base_offset'] + i * 8
            elem_type = info['elem_types'][i]

            if i > 0:
                sep_label = self.add_string(", ")
                self.asm_lines.append(f"    adrp x0, {sep_label}@PAGE")
                self.asm_lines.append(f"    add x0, x0, {sep_label}@PAGEOFF")
                self.asm_lines.append("    bl _printf")

            if elem_type in ('string', 'bool'):
                self.asm_lines.append(f"    ldur x0, [x29, #-{elem_offset + 16}]")
                self.asm_lines.append("    str x0, [sp]")
                fmt_label = self.add_string("%s")
                self.asm_lines.append(f"    adrp x0, {fmt_label}@PAGE")
                self.asm_lines.append(f"    add x0, x0, {fmt_label}@PAGEOFF")
                self.asm_lines.append("    bl _printf")
            else:
                self.asm_lines.append(f"    ldur w1, [x29, #-{elem_offset + 16}]")
                self.asm_lines.append("    sxtw x1, w1")
                self.asm_lines.append("    str x1, [sp]")
                fmt_label = self.add_string("%d")
                self.asm_lines.append(f"    adrp x0, {fmt_label}@PAGE")
                self.asm_lines.append(f"    add x0, x0, {fmt_label}@PAGEOFF")
                self.asm_lines.append("    bl _printf")

        # Print closing paren + newline
        close_label = self.add_string_raw(")")
        self.asm_lines.append(f"    adrp x0, {close_label}@PAGE")
        self.asm_lines.append(f"    add x0, x0, {close_label}@PAGEOFF")
        self.asm_lines.append("    bl _printf")

    def gen_array_load(self, var_name, index, arr_info, use_x):
        if isinstance(index, Literal) and isinstance(index.value, int):
            elem_offset = arr_info['base_offset'] + index.value * 8
            if use_x:
                self.asm_lines.append(f"    ldur x0, [x29, #-{elem_offset + 16}]")
            else:
                self.asm_lines.append(f"    ldur w0, [x29, #-{elem_offset + 16}]")
        else:
            self.gen_expr(index)
            self.asm_lines.append("    mov w1, w0")
            self.asm_lines.append("    lsl w1, w1, #3")
            self.asm_lines.append(f"    mov w2, #{arr_info['base_offset'] + 16}")
            self.asm_lines.append("    add w1, w1, w2")
            self.asm_lines.append("    sxtw x1, w1")
            self.asm_lines.append("    sub x3, x29, x1")
            if use_x:
                self.asm_lines.append("    ldr x0, [x3]")
            else:
                self.asm_lines.append("    ldr w0, [x3]")

    def gen_var_decl(self, node: VarDecl):
        # Handle enum variable assignment
        enum_access = self.is_enum_access(node.value)
        if enum_access:
            enum_name, case_name = enum_access
            case_labels = self.enum_case_labels.get(enum_name, {})
            label = case_labels.get(case_name)
            if label:
                self.asm_lines.append(f"    adrp x0, {label}@PAGE")
                self.asm_lines.append(f"    add x0, x0, {label}@PAGEOFF")
                if node.name not in self.variables:
                    self.variables[node.name] = self.stack_offset
                    self.stack_offset += 8
                offset = self.variables[node.name]
                self.asm_lines.append(f"    stur x0, [x29, #-{offset + 16}]")
                self.enum_var_labels[node.name] = (enum_name, case_name)
                return

        if isinstance(node.value, TupleLiteral):
            self.gen_tuple_decl(node.name, node.value)
            return

        if isinstance(node.value, DictLiteral):
            self.gen_dict_decl(node.name, node.value)
            return

        if isinstance(node.value, ArrayLiteral):
            arr = node.value
            # Check for nested arrays
            is_nested = arr.elements and isinstance(arr.elements[0], ArrayLiteral)
            if is_nested:
                base_offset = self.stack_offset
                total_count = 0
                inner_sizes = []
                for elem in arr.elements:
                    if isinstance(elem, ArrayLiteral):
                        inner_sizes.append(len(elem.elements))
                        for inner_elem in elem.elements:
                            self.gen_expr(inner_elem)
                            self.asm_lines.append(f"    stur w0, [x29, #-{self.stack_offset + 16}]")
                            self.stack_offset += 8
                            total_count += 1
                self.arrays[node.name] = {
                    'base_offset': base_offset, 'count': total_count, 'is_string': False
                }
                self.nested_arrays[node.name] = (len(arr.elements), inner_sizes[0] if inner_sizes else 0)
                self.variables[node.name] = base_offset
                return

            # Determine if string array
            is_string = (arr.elements and isinstance(arr.elements[0], Literal)
                         and isinstance(arr.elements[0].value, str))
            base_offset = self.stack_offset

            for elem in arr.elements:
                if is_string:
                    if isinstance(elem, Literal) and isinstance(elem.value, str):
                        str_label = self.add_string(elem.value)
                        self.asm_lines.append(f"    adrp x0, {str_label}@PAGE")
                        self.asm_lines.append(f"    add x0, x0, {str_label}@PAGEOFF")
                        self.asm_lines.append(f"    stur x0, [x29, #-{self.stack_offset + 16}]")
                else:
                    self.gen_expr(elem)
                    self.asm_lines.append(f"    stur w0, [x29, #-{self.stack_offset + 16}]")
                self.stack_offset += 8

            self.arrays[node.name] = {
                'base_offset': base_offset, 'count': len(arr.elements), 'is_string': is_string
            }
            self.variables[node.name] = base_offset
            return

        # Scalar variable - check if bool
        if isinstance(node.value, Literal) and isinstance(node.value.value, bool):
            self.bool_vars.add(node.name)
            str_label = self.add_string("true" if node.value.value else "false")
            self.asm_lines.append(f"    adrp x0, {str_label}@PAGE")
            self.asm_lines.append(f"    add x0, x0, {str_label}@PAGEOFF")
            if node.name not in self.variables:
                self.variables[node.name] = self.stack_offset
                self.stack_offset += 8
            offset = self.variables[node.name]
            self.asm_lines.append(f"    stur x0, [x29, #-{offset + 16}]")
            return

        # Scalar variable - check if float
        if self.is_float_expr(node.value):
            self.gen_float_expr(node.value)
            if node.name not in self.variables:
                self.variables[node.name] = self.stack_offset
                self.stack_offset += 8
            offset = self.variables[node.name]
            self.float_vars.add(node.name)
            self.asm_lines.append(f"    stur d0, [x29, #-{offset + 16}]")
        else:
            self.gen_expr(node.value)
            if node.name not in self.variables:
                self.variables[node.name] = self.stack_offset
                self.stack_offset += 8
            offset = self.variables[node.name]
            self.asm_lines.append(f"    stur w0, [x29, #-{offset + 16}]")

    def gen_tuple_decl(self, name, tuple_lit):
        base_offset = self.stack_offset
        elem_types = []

        for elem in tuple_lit.elements:
            if isinstance(elem, Literal):
                if isinstance(elem.value, str):
                    str_label = self.add_string(elem.value)
                    self.asm_lines.append(f"    adrp x0, {str_label}@PAGE")
                    self.asm_lines.append(f"    add x0, x0, {str_label}@PAGEOFF")
                    self.asm_lines.append(f"    stur x0, [x29, #-{self.stack_offset + 16}]")
                    elem_types.append('string')
                elif isinstance(elem.value, bool):
                    str_label = self.add_string("true" if elem.value else "false")
                    self.asm_lines.append(f"    adrp x0, {str_label}@PAGE")
                    self.asm_lines.append(f"    add x0, x0, {str_label}@PAGEOFF")
                    self.asm_lines.append(f"    stur x0, [x29, #-{self.stack_offset + 16}]")
                    elem_types.append('string')
                else:
                    self.gen_expr(elem)
                    self.asm_lines.append(f"    stur w0, [x29, #-{self.stack_offset + 16}]")
                    elem_types.append('int')
            else:
                self.gen_expr(elem)
                self.asm_lines.append(f"    stur w0, [x29, #-{self.stack_offset + 16}]")
                elem_types.append('int')
            self.stack_offset += 8

        self.tuples[name] = {
            'base_offset': base_offset, 'count': len(tuple_lit.elements), 'elem_types': elem_types
        }
        self.variables[name] = base_offset

    def gen_dict_decl(self, name, dict_lit):
        keys = []
        value_offsets = []
        value_types = []

        for key_node, val_node in dict_lit.pairs:
            key_str = key_node.value if isinstance(key_node, Literal) and isinstance(key_node.value, str) else '?'
            keys.append(key_str)

            val_offset = self.stack_offset
            value_offsets.append(val_offset)

            if isinstance(val_node, Literal):
                if isinstance(val_node.value, str):
                    str_label = self.add_string(val_node.value)
                    self.asm_lines.append(f"    adrp x0, {str_label}@PAGE")
                    self.asm_lines.append(f"    add x0, x0, {str_label}@PAGEOFF")
                    self.asm_lines.append(f"    stur x0, [x29, #-{val_offset + 16}]")
                    value_types.append('string')
                elif isinstance(val_node.value, bool):
                    str_label = self.add_string("true" if val_node.value else "false")
                    self.asm_lines.append(f"    adrp x0, {str_label}@PAGE")
                    self.asm_lines.append(f"    add x0, x0, {str_label}@PAGEOFF")
                    self.asm_lines.append(f"    stur x0, [x29, #-{val_offset + 16}]")
                    value_types.append('bool')
                else:
                    self.gen_expr(val_node)
                    self.asm_lines.append(f"    stur w0, [x29, #-{val_offset + 16}]")
                    value_types.append('int')
            elif isinstance(val_node, ArrayLiteral):
                arr_base = self.stack_offset
                is_str = (val_node.elements and isinstance(val_node.elements[0], Literal)
                          and isinstance(val_node.elements[0].value, str))
                for arr_elem in val_node.elements:
                    if is_str:
                        if isinstance(arr_elem, Literal) and isinstance(arr_elem.value, str):
                            sl = self.add_string(arr_elem.value)
                            self.asm_lines.append(f"    adrp x0, {sl}@PAGE")
                            self.asm_lines.append(f"    add x0, x0, {sl}@PAGEOFF")
                            self.asm_lines.append(f"    stur x0, [x29, #-{self.stack_offset + 16}]")
                    else:
                        self.gen_expr(arr_elem)
                        self.asm_lines.append(f"    stur w0, [x29, #-{self.stack_offset + 16}]")
                    self.stack_offset += 8
                self.arrays[f"{name}.{key_str}"] = {
                    'base_offset': arr_base, 'count': len(val_node.elements), 'is_string': is_str
                }
                value_types.append('int')  # placeholder
                continue
            else:
                self.gen_expr(val_node)
                self.asm_lines.append(f"    stur w0, [x29, #-{val_offset + 16}]")
                value_types.append('int')
            self.stack_offset += 8

        self.dicts[name] = {'keys': keys, 'value_offsets': value_offsets, 'value_types': value_types}
        self.variables[name] = value_offsets[0] if value_offsets else self.stack_offset

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
            use_float = self.is_float_expr(node.left) or self.is_float_expr(node.right)

            if use_float:
                self.gen_float_expr(node.left)
                self.asm_lines.append("    str d0, [sp, #-16]!")
                self.gen_float_expr(node.right)
                self.asm_lines.append("    fmov d1, d0")
                self.asm_lines.append("    ldr d0, [sp], #16")
                self.asm_lines.append("    fcmp d0, d1")

                float_branches = {
                    OP['eq']['emit']: 'b.ne',
                    OP['neq']['emit']: 'b.eq',
                    OP['lt']['emit']: 'b.ge',
                    OP['gt']['emit']: 'b.le',
                    OP['lte']['emit']: 'b.gt',
                    OP['gte']['emit']: 'b.lt',
                }
                if node.op in float_branches:
                    self.asm_lines.append(f"    {float_branches[node.op]} {false_label}")
            else:
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
            if isinstance(node.value, bool):
                self.asm_lines.append(f"    mov w0, #{1 if node.value else 0}")
            elif isinstance(node.value, int):
                if -65536 <= node.value <= 65535:
                    self.asm_lines.append(f"    mov w0, #{node.value}")
                else:
                    self.asm_lines.append(f"    movz w0, #{node.value & 0xFFFF}")
                    if node.value > 65535:
                        self.asm_lines.append(f"    movk w0, #{(node.value >> 16) & 0xFFFF}, lsl #16")
            else:
                self.asm_lines.append("    mov w0, #0")

        elif isinstance(node, VarRef):
            if node.name in self.enum_var_labels and node.name in self.variables:
                # Enum var stored as string pointer
                offset = self.variables[node.name]
                self.asm_lines.append(f"    ldur x0, [x29, #-{offset + 16}]")
                self.asm_lines.append("    mov w0, w0")  # truncate for int comparison
            elif node.name in self.variables:
                offset = self.variables[node.name]
                self.asm_lines.append(f"    ldur w0, [x29, #-{offset + 16}]")
            elif node.name in self.enums:
                self.asm_lines.append("    mov w0, #0")
            else:
                self.asm_lines.append("    mov w0, #0")

        elif isinstance(node, IndexAccess):
            # Check enum access
            if isinstance(node.array, VarRef) and node.array.name in self.enums:
                if isinstance(node.index, Literal) and isinstance(node.index.value, str):
                    case_labels = self.enum_case_labels.get(node.array.name, {})
                    label = case_labels.get(node.index.value)
                    if label:
                        self.asm_lines.append(f"    adrp x0, {label}@PAGE")
                        self.asm_lines.append(f"    add x0, x0, {label}@PAGEOFF")
                        self.asm_lines.append("    mov w0, w0")
                        return
                    value = self.enums[node.array.name].get(node.index.value, 0)
                    self.asm_lines.append(f"    mov w0, #{value}")
                    return

            # Check array access
            if isinstance(node.array, VarRef) and node.array.name in self.arrays:
                arr_info = self.arrays[node.array.name]
                self.gen_array_load(node.array.name, node.index, arr_info, arr_info['is_string'])
                return

            # Check nested array access: matrix[0][1]
            if (isinstance(node.array, IndexAccess) and isinstance(node.array.array, VarRef)
                    and node.array.array.name in self.arrays
                    and node.array.array.name in self.nested_arrays):
                arr_info = self.arrays[node.array.array.name]
                nested = self.nested_arrays[node.array.array.name]
                if (isinstance(node.array.index, Literal) and isinstance(node.array.index.value, int)
                        and isinstance(node.index, Literal) and isinstance(node.index.value, int)):
                    flat_index = node.array.index.value * nested[1] + node.index.value
                    elem_offset = arr_info['base_offset'] + flat_index * 8
                    self.asm_lines.append(f"    ldur w0, [x29, #-{elem_offset + 16}]")
                    return

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

    # --- Float Support ---

    def is_float_expr(self, node):
        if isinstance(node, Literal):
            return isinstance(node.value, float)
        elif isinstance(node, VarRef):
            return node.name in self.float_vars
        elif isinstance(node, BinaryOp):
            return self.is_float_expr(node.left) or self.is_float_expr(node.right)
        elif isinstance(node, UnaryOp):
            return self.is_float_expr(node.operand)
        return False

    def gen_float_expr(self, node):
        if isinstance(node, Literal):
            if isinstance(node.value, float):
                label = self.add_double(node.value)
                self.asm_lines.append(f"    adrp x8, {label}@PAGE")
                self.asm_lines.append(f"    ldr d0, [x8, {label}@PAGEOFF]")
            elif isinstance(node.value, int):
                if -65536 <= node.value <= 65535:
                    self.asm_lines.append(f"    mov w0, #{node.value}")
                else:
                    self.asm_lines.append(f"    movz w0, #{node.value & 0xFFFF}")
                    if node.value > 65535:
                        self.asm_lines.append(f"    movk w0, #{(node.value >> 16) & 0xFFFF}, lsl #16")
                self.asm_lines.append("    scvtf d0, w0")
        elif isinstance(node, VarRef):
            if node.name in self.float_vars and node.name in self.variables:
                offset = self.variables[node.name]
                self.asm_lines.append(f"    ldur d0, [x29, #-{offset + 16}]")
            elif node.name in self.variables:
                offset = self.variables[node.name]
                self.asm_lines.append(f"    ldur w0, [x29, #-{offset + 16}]")
                self.asm_lines.append("    scvtf d0, w0")
        elif isinstance(node, BinaryOp):
            self.gen_float_expr(node.left)
            self.asm_lines.append("    str d0, [sp, #-16]!")
            self.gen_float_expr(node.right)
            self.asm_lines.append("    fmov d1, d0")
            self.asm_lines.append("    ldr d0, [sp], #16")

            if node.op == OP['add']['emit']:
                self.asm_lines.append("    fadd d0, d0, d1")
            elif node.op == OP['sub']['emit']:
                self.asm_lines.append("    fsub d0, d0, d1")
            elif node.op == OP['mul']['emit']:
                self.asm_lines.append("    fmul d0, d0, d1")
            elif node.op == OP['div']['emit']:
                self.asm_lines.append("    fdiv d0, d0, d1")
            elif node.op == OP['mod']['emit']:
                # Float mod: d0 = d0 - (trunc(d0/d1) * d1)
                self.asm_lines.append("    fdiv d2, d0, d1")
                self.asm_lines.append("    frintz d2, d2")
                self.asm_lines.append("    fmsub d0, d2, d1, d0")
        elif isinstance(node, UnaryOp):
            self.gen_float_expr(node.operand)
            if node.op == '-' or node.op == OP['sub']['emit']:
                self.asm_lines.append("    fneg d0, d0")
