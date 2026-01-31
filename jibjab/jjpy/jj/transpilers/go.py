"""
JibJab Go Transpiler - Converts JJ to Go
Uses shared C-family base from cfamily.py

Dictionaries: expanded to individual variables (person_name, person_age, etc.)
Tuples: stored as numbered variables (_0, _1, _2)
"""

from ..ast import (
    Literal, VarRef, VarDecl, ArrayLiteral, DictLiteral, TupleLiteral,
    IndexAccess, PrintStmt, FuncDef, EnumDef, Program, StringInterpolation
)
from .cfamily import CFamilyTranspiler, infer_type


class GoTranspiler(CFamilyTranspiler):
    target_name = 'go'

    def __init__(self):
        super().__init__()
        self.dict_fields = {}   # dict_name -> {key: (go_var_name, type)}
        self.tuple_fields = {}  # tuple_name -> [(go_var_name, type)]
        self.needs_math = False

    def transpile(self, program: Program) -> str:
        lines = []

        # Collect function definitions
        funcs = [s for s in program.statements if isinstance(s, FuncDef)]
        main_stmts = [s for s in program.statements if not isinstance(s, FuncDef)]

        # First pass: generate function bodies and main to detect math import need
        func_lines = []
        for f in funcs:
            func_lines.append(self._func_def(f))
            func_lines.append('')

        main_lines = []
        if main_stmts:
            main_lines.append('func main() {')
            self.indent = 1
            for s in main_stmts:
                main_lines.append(self.stmt(s))
            main_lines.append('}')

        # Build header with correct imports
        lines.append('// Transpiled from JibJab')
        lines.append('package main')
        lines.append('')
        if self.needs_math:
            lines.append('import (')
            lines.append('    "fmt"')
            lines.append('    "math"')
            lines.append(')')
        else:
            lines.append('import "fmt"')
        lines.append('')

        # Emit functions
        for fl in func_lines:
            lines.append(fl)

        # Emit main
        for ml in main_lines:
            lines.append(ml)

        return '\n'.join(lines)

    def _func_def(self, node: FuncDef) -> str:
        params = ', '.join(f'{p} int' for p in node.params)
        header = f'func {node.name}({params}) int {{'
        self.indent = 1
        body = '\n'.join(self.stmt(s) for s in node.body)
        self.indent = 0
        return f"{header}\n{body}\n}}"

    def _emit_main(self, lines, program):
        # Not used - transpile() handles everything
        pass

    def _var_decl(self, node: VarDecl) -> str:
        if isinstance(node.value, ArrayLiteral):
            return self._var_array(node)
        if isinstance(node.value, TupleLiteral):
            self.tuple_vars.add(node.name)
            return self._var_tuple(node)
        if isinstance(node.value, DictLiteral):
            self.dict_vars.add(node.name)
            return self._var_dict(node)
        inferred = infer_type(node.value)
        if inferred == 'Int':
            self.int_vars.add(node.name)
        elif inferred == 'Bool':
            self.bool_vars.add(node.name)
        elif inferred == 'Double':
            self.double_vars.add(node.name)
        elif inferred == 'String':
            self.string_vars.add(node.name)
        return self.ind() + f'{node.name} := {self.expr(node.value)}'

    def _var_array(self, node: VarDecl) -> str:
        if node.value.elements:
            first = node.value.elements[0]
            if isinstance(first, ArrayLiteral):
                inner_type = self.get_target_type(infer_type(first.elements[0])) if first.elements else 'int'
                inner_size = len(first.elements)
                outer_size = len(node.value.elements)
                elements = ', '.join(self.expr(e) for e in node.value.elements)
                return self.ind() + f'{node.name} := [{outer_size}][{inner_size}]{inner_type}{{{elements}}}'
            if isinstance(first, Literal) and isinstance(first.value, str):
                elem_type = 'string'
            else:
                elem_type = self.get_target_type(infer_type(first))
            elements = ', '.join(self.expr(e) for e in node.value.elements)
            return self.ind() + f'{node.name} := []{elem_type}{{{elements}}}'
        return self.ind() + f'{node.name} := []int{{}}'

    def _var_dict(self, node: VarDecl) -> str:
        lines = []
        self.dict_fields[node.name] = {}
        if not node.value.pairs:
            lines.append(self.ind() + f'// empty dict {node.name}')
            return '\n'.join(lines)
        for k, v in node.value.pairs:
            if isinstance(k, Literal) and isinstance(k.value, str):
                key = k.value
                go_var = f'{node.name}_{key}'
                if isinstance(v, Literal):
                    if isinstance(v.value, str):
                        lines.append(self.ind() + f'{go_var} := "{v.value}"')
                        self.dict_fields[node.name][key] = (go_var, 'str')
                    elif isinstance(v.value, bool):
                        val = 'true' if v.value else 'false'
                        lines.append(self.ind() + f'{go_var} := {val}')
                        self.dict_fields[node.name][key] = (go_var, 'bool')
                    elif isinstance(v.value, int):
                        lines.append(self.ind() + f'{go_var} := {v.value}')
                        self.dict_fields[node.name][key] = (go_var, 'int')
                    elif isinstance(v.value, float):
                        lines.append(self.ind() + f'{go_var} := {v.value}')
                        self.dict_fields[node.name][key] = (go_var, 'double')
                elif isinstance(v, ArrayLiteral):
                    if v.elements:
                        first = v.elements[0]
                        if isinstance(first, Literal) and isinstance(first.value, str):
                            elem_type = 'string'
                        else:
                            elem_type = self.get_target_type(infer_type(first))
                        elements = ', '.join(self.expr(e) for e in v.elements)
                        lines.append(self.ind() + f'{go_var} := []{elem_type}{{{elements}}}')
                        self.dict_fields[node.name][key] = (go_var, 'array')
                    else:
                        lines.append(self.ind() + f'{go_var} := []int{{}}')
                        self.dict_fields[node.name][key] = (go_var, 'array')
        return '\n'.join(lines)

    def _var_tuple(self, node: VarDecl) -> str:
        lines = []
        self.tuple_fields[node.name] = []
        if not node.value.elements:
            lines.append(self.ind() + f'// empty tuple {node.name}')
            return '\n'.join(lines)
        for i, e in enumerate(node.value.elements):
            go_var = f'{node.name}_{i}'
            if isinstance(e, Literal):
                if isinstance(e.value, str):
                    lines.append(self.ind() + f'{go_var} := "{e.value}"')
                    self.tuple_fields[node.name].append((go_var, 'str'))
                elif isinstance(e.value, bool):
                    val = 'true' if e.value else 'false'
                    lines.append(self.ind() + f'{go_var} := {val}')
                    self.tuple_fields[node.name].append((go_var, 'bool'))
                elif isinstance(e.value, int):
                    lines.append(self.ind() + f'{go_var} := {e.value}')
                    self.tuple_fields[node.name].append((go_var, 'int'))
                elif isinstance(e.value, float):
                    lines.append(self.ind() + f'{go_var} := {e.value}')
                    self.tuple_fields[node.name].append((go_var, 'double'))
            else:
                lines.append(self.ind() + f'{go_var} := {self.expr(e)}')
                self.tuple_fields[node.name].append((go_var, 'int'))
        return '\n'.join(lines)

    def _print_stmt(self, node: PrintStmt) -> str:
        expr_node = node.expr
        if isinstance(expr_node, StringInterpolation):
            fmt = ''
            args = []
            for kind, text in expr_node.parts:
                if kind == 'literal':
                    fmt += text
                else:
                    fmt += '%v'
                    args.append(self._interp_var_expr(text))
            arg_str = '' if not args else ', ' + ', '.join(args)
            return self.ind() + f'fmt.Printf("{fmt}\\n"{arg_str})'
        if isinstance(expr_node, Literal) and isinstance(expr_node.value, str):
            return self.ind() + f'fmt.Println({self.expr(expr_node)})'
        if isinstance(expr_node, VarRef):
            if expr_node.name in self.enums:
                return self.ind() + f'fmt.Println("enum {expr_node.name}")'
            if expr_node.name in self.double_vars:
                return self.ind() + f'fmt.Println({self.expr(expr_node)})'
            if expr_node.name in self.string_vars:
                return self.ind() + f'fmt.Println({self.expr(expr_node)})'
            if expr_node.name in self.bool_vars:
                return self.ind() + self.T.get('printBool', 'fmt.Println({expr})').replace('{expr}', self.expr(expr_node))
            # Print whole dict
            if expr_node.name in self.dict_vars:
                if expr_node.name in self.dict_fields and not self.dict_fields[expr_node.name]:
                    return self.ind() + 'fmt.Println("{}")'
                return self.ind() + f'fmt.Println("{expr_node.name}")'
            # Print whole tuple
            if expr_node.name in self.tuple_vars:
                return self._print_whole_tuple(expr_node.name)
        if isinstance(expr_node, IndexAccess):
            if isinstance(expr_node.array, VarRef) and expr_node.array.name in self.enums:
                return self._print_enum_value(expr_node)
            # Dict or tuple access
            resolved = self._resolve_access(expr_node)
            if resolved:
                go_var, typ = resolved
                return self.ind() + f'fmt.Println({go_var})'
        if self.is_float_expr(expr_node):
            return self.ind() + f'fmt.Println({self.expr(expr_node)})'
        return self.ind() + f'fmt.Println({self.expr(expr_node)})'

    def _print_enum_type(self, name: str) -> str:
        return self.ind() + f'fmt.Println("enum {name}")'

    def _print_enum_value(self, expr_node) -> str:
        return self.ind() + f'fmt.Println({self.expr(expr_node)})'

    def _print_whole_tuple(self, name):
        if name not in self.tuple_fields or not self.tuple_fields[name]:
            return self.ind() + 'fmt.Println("()")'
        fields = self.tuple_fields[name]
        # Build output like fmt.Printf("(%v, %v)\n", point_0, point_1)
        fmts = ', '.join('%v' for _ in fields)
        args = ', '.join(go_var for go_var, _ in fields)
        return self.ind() + f'fmt.Printf("({fmts})\\n", {args})'

    def _enum_def(self, node: EnumDef) -> str:
        self.enums.add(node.name)
        lines = [self.ind() + 'const (']
        self.indent += 1
        for i, case in enumerate(node.cases):
            if i == 0:
                lines.append(self.ind() + f'{node.name}_{case} = iota')
            else:
                lines.append(self.ind() + f'{node.name}_{case}')
        self.indent -= 1
        lines.append(self.ind() + ')')
        return '\n'.join(lines)

    def _resolve_access(self, node):
        """Resolve dict/tuple access to (go_var_name, type) or None."""
        if isinstance(node, IndexAccess):
            # Direct dict access: person["name"]
            if isinstance(node.array, VarRef) and node.array.name in self.dict_fields:
                if isinstance(node.index, Literal) and isinstance(node.index.value, str):
                    fields = self.dict_fields[node.array.name]
                    if node.index.value in fields:
                        return fields[node.index.value]
            # Direct tuple access: point[0]
            if isinstance(node.array, VarRef) and node.array.name in self.tuple_fields:
                if isinstance(node.index, Literal) and isinstance(node.index.value, int):
                    fields = self.tuple_fields[node.array.name]
                    idx = node.index.value
                    if idx < len(fields):
                        return fields[idx]
            # Nested: data["items"][0]
            if isinstance(node.array, IndexAccess):
                parent = self._resolve_access(node.array)
                if parent:
                    go_var, typ = parent
                    if typ == 'array' and isinstance(node.index, Literal) and isinstance(node.index.value, int):
                        return (f'{go_var}[{node.index.value}]', 'int')
        return None

    def expr(self, node) -> str:
        if isinstance(node, IndexAccess):
            # Handle enum access
            if isinstance(node.array, VarRef) and node.array.name in self.enums:
                if isinstance(node.index, Literal) and isinstance(node.index.value, str):
                    return f'{node.array.name}_{node.index.value}'
            resolved = self._resolve_access(node)
            if resolved:
                return resolved[0]
        from ..ast import BinaryOp
        if isinstance(node, BinaryOp):
            if node.op == '%' and (self.is_float_expr(node.left) or self.is_float_expr(node.right)):
                self.needs_math = True
                return f"math.Mod({self.expr(node.left)}, {self.expr(node.right)})"
        return super().expr(node)
