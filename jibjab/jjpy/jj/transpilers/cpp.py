"""
JibJab C++ Transpiler - Converts JJ to C++
Uses shared C-family base from cfamily.py

Dictionaries: expanded to individual variables (person_name, person_age, etc.)
Tuples: stored as numbered variables (_0, _1, _2) with cout for printing
"""

from ..ast import (
    Literal, VarRef, VarDecl, ArrayLiteral, DictLiteral, TupleLiteral,
    IndexAccess, PrintStmt
)
from .cfamily import CFamilyTranspiler, infer_type


class CppTranspiler(CFamilyTranspiler):
    target_name = 'cpp'

    def __init__(self):
        super().__init__()
        self.dict_fields = {}   # dict_name -> {key: (cpp_var_name, type)}
        self.tuple_fields = {}  # tuple_name -> [(cpp_var_name, type)]

    def transpile(self, program):
        code = super().transpile(program)
        # Add <string> include if any string dict/tuple fields are used
        needs_string = False
        for fields in self.dict_fields.values():
            for _, (_, typ) in fields.items():
                if typ == 'str':
                    needs_string = True
        for fields in self.tuple_fields.values():
            for _, typ in fields:
                if typ == 'str':
                    needs_string = True
        if needs_string:
            lines = code.split('\n')
            insert_idx = 0
            for i, line in enumerate(lines):
                if line.startswith('#include'):
                    insert_idx = i + 1
            inc = '#include <string>'
            if inc not in lines:
                lines.insert(insert_idx, inc)
            code = '\n'.join(lines)
        return code

    def _var_dict(self, node: VarDecl) -> str:
        lines = []
        self.dict_fields[node.name] = {}
        if not node.value.pairs:
            lines.append(self.ind() + f'// empty dict {node.name}')
            return '\n'.join(lines)
        for k, v in node.value.pairs:
            if isinstance(k, Literal) and isinstance(k.value, str):
                key = k.value
                cpp_var = f'{node.name}_{key}'
                if isinstance(v, Literal):
                    if isinstance(v.value, str):
                        lines.append(self.ind() + f'std::string {cpp_var} = "{v.value}";')
                        self.dict_fields[node.name][key] = (cpp_var, 'str')
                    elif isinstance(v.value, bool):
                        val = 'true' if v.value else 'false'
                        lines.append(self.ind() + f'bool {cpp_var} = {val};')
                        self.dict_fields[node.name][key] = (cpp_var, 'bool')
                    elif isinstance(v.value, int):
                        lines.append(self.ind() + f'int {cpp_var} = {v.value};')
                        self.dict_fields[node.name][key] = (cpp_var, 'int')
                    elif isinstance(v.value, float):
                        lines.append(self.ind() + f'double {cpp_var} = {v.value};')
                        self.dict_fields[node.name][key] = (cpp_var, 'double')
                elif isinstance(v, ArrayLiteral):
                    if v.elements:
                        first = v.elements[0]
                        if isinstance(first, Literal) and isinstance(first.value, str):
                            elem_type = 'std::string'
                        else:
                            elem_type = self.get_target_type(infer_type(first))
                        elements = ', '.join(self.expr(e) for e in v.elements)
                        lines.append(self.ind() + f'{elem_type} {cpp_var}[] = {{{elements}}};')
                        self.dict_fields[node.name][key] = (cpp_var, 'array')
                    else:
                        lines.append(self.ind() + f'int {cpp_var}[] = {{}};')
                        self.dict_fields[node.name][key] = (cpp_var, 'array')
        return '\n'.join(lines)

    def _var_tuple(self, node: VarDecl) -> str:
        lines = []
        self.tuple_fields[node.name] = []
        if not node.value.elements:
            lines.append(self.ind() + f'// empty tuple {node.name}')
            return '\n'.join(lines)
        for i, e in enumerate(node.value.elements):
            cpp_var = f'{node.name}_{i}'
            if isinstance(e, Literal):
                if isinstance(e.value, str):
                    lines.append(self.ind() + f'std::string {cpp_var} = "{e.value}";')
                    self.tuple_fields[node.name].append((cpp_var, 'str'))
                elif isinstance(e.value, bool):
                    val = 'true' if e.value else 'false'
                    lines.append(self.ind() + f'bool {cpp_var} = {val};')
                    self.tuple_fields[node.name].append((cpp_var, 'bool'))
                elif isinstance(e.value, int):
                    lines.append(self.ind() + f'int {cpp_var} = {e.value};')
                    self.tuple_fields[node.name].append((cpp_var, 'int'))
                elif isinstance(e.value, float):
                    lines.append(self.ind() + f'double {cpp_var} = {e.value};')
                    self.tuple_fields[node.name].append((cpp_var, 'double'))
            else:
                lines.append(self.ind() + f'int {cpp_var} = {self.expr(e)};')
                self.tuple_fields[node.name].append((cpp_var, 'int'))
        return '\n'.join(lines)

    def _print_stmt(self, node: PrintStmt) -> str:
        expr_node = node.expr
        if isinstance(expr_node, Literal) and isinstance(expr_node.value, str):
            return self.ind() + f'std::cout << {self.expr(expr_node)} << std::endl;'
        if isinstance(expr_node, VarRef):
            if expr_node.name in self.enums:
                return self.ind() + f'std::cout << "enum {expr_node.name}" << std::endl;'
            if expr_node.name in self.double_vars:
                return self.ind() + self.T['printFloat'].replace('{expr}', self.expr(expr_node))
            # Print whole dict
            if expr_node.name in self.dict_vars:
                if expr_node.name in self.dict_fields and not self.dict_fields[expr_node.name]:
                    return self.ind() + 'std::cout << "{}" << std::endl;'
                return self.ind() + f'std::cout << "{expr_node.name}" << std::endl;'
            # Print whole tuple
            if expr_node.name in self.tuple_vars:
                return self._print_whole_tuple(expr_node.name)
        if isinstance(expr_node, IndexAccess):
            if isinstance(expr_node.array, VarRef) and expr_node.array.name in self.enums:
                return self.ind() + f'std::cout << {self.expr(expr_node)} << std::endl;'
            # Dict or tuple access
            resolved = self._resolve_access(expr_node)
            if resolved:
                cpp_var, typ = resolved
                return self.ind() + f'std::cout << {cpp_var} << std::endl;'
        if self.is_float_expr(expr_node):
            return self.ind() + self.T['printFloat'].replace('{expr}', self.expr(expr_node))
        return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))

    def _print_whole_tuple(self, name):
        if name not in self.tuple_fields or not self.tuple_fields[name]:
            return self.ind() + 'std::cout << "()" << std::endl;'
        fields = self.tuple_fields[name]
        # Build output like (10, 20)
        parts = []
        for i, (cpp_var, typ) in enumerate(fields):
            if i == 0:
                parts.append('"("')
            parts.append(cpp_var)
            if i < len(fields) - 1:
                parts.append('", "')
        parts.append('")"')
        return self.ind() + f'std::cout << {" << ".join(parts)} << std::endl;'

    def _resolve_access(self, node):
        """Resolve dict/tuple access to (cpp_var_name, type) or None."""
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
                    cpp_var, typ = parent
                    if typ == 'array' and isinstance(node.index, Literal) and isinstance(node.index.value, int):
                        return (f'{cpp_var}[{node.index.value}]', 'int')
        return None

    def expr(self, node) -> str:
        if isinstance(node, IndexAccess):
            resolved = self._resolve_access(node)
            if resolved:
                return resolved[0]
        return super().expr(node)
