"""
JibJab C Transpiler - Converts JJ to C
Uses shared C-family base from cfamily.py

Dictionaries: expanded to individual variables (person_name, person_age, etc.)
Tuples: stored as structs with numbered fields (_0, _1, _2)
"""

from ..ast import (
    Literal, VarRef, VarDecl, ArrayLiteral, DictLiteral, TupleLiteral,
    IndexAccess, PrintStmt, MethodCallExpr
)
from .cfamily import CFamilyTranspiler, infer_type


class CTranspiler(CFamilyTranspiler):
    target_name = 'c'

    def __init__(self):
        super().__init__()
        # Track dict key->value mappings for access resolution
        self.dict_fields = {}  # dict_name -> {key: (c_var_name, type)}
        self.tuple_fields = {}  # tuple_name -> [(c_var_name, type)]

    def _var_dict(self, node: VarDecl) -> str:
        lines = []
        self.dict_fields[node.name] = {}
        if not node.value.pairs:
            lines.append(self.ind() + f'// empty dict {node.name}')
            return '\n'.join(lines)
        for k, v in node.value.pairs:
            if isinstance(k, Literal) and isinstance(k.value, str):
                key = k.value
                c_var = f'{node.name}_{key}'
                if isinstance(v, Literal):
                    if isinstance(v.value, str):
                        lines.append(self.ind() + f'const char* {c_var} = "{v.value}";')
                        self.dict_fields[node.name][key] = (c_var, 'str')
                    elif isinstance(v.value, bool):
                        val = 1 if v.value else 0
                        lines.append(self.ind() + f'int {c_var} = {val};')
                        self.dict_fields[node.name][key] = (c_var, 'int')
                    elif isinstance(v.value, int):
                        lines.append(self.ind() + f'int {c_var} = {v.value};')
                        self.dict_fields[node.name][key] = (c_var, 'int')
                    elif isinstance(v.value, float):
                        lines.append(self.ind() + f'double {c_var} = {v.value};')
                        self.dict_fields[node.name][key] = (c_var, 'double')
                elif isinstance(v, ArrayLiteral):
                    if v.elements:
                        first = v.elements[0]
                        if isinstance(first, Literal) and isinstance(first.value, str):
                            elem_type = 'const char*'
                        else:
                            elem_type = self.get_target_type(infer_type(first))
                        elements = ', '.join(self.expr(e) for e in v.elements)
                        lines.append(self.ind() + f'{elem_type} {c_var}[] = {{{elements}}};')
                        self.dict_fields[node.name][key] = (c_var, 'array')
                    else:
                        lines.append(self.ind() + f'int {c_var}[] = {{}};')
                        self.dict_fields[node.name][key] = (c_var, 'array')
        return '\n'.join(lines)

    def _var_tuple(self, node: VarDecl) -> str:
        lines = []
        self.tuple_fields[node.name] = []
        if not node.value.elements:
            lines.append(self.ind() + f'// empty tuple {node.name}')
            return '\n'.join(lines)
        for i, e in enumerate(node.value.elements):
            c_var = f'{node.name}_{i}'
            if isinstance(e, Literal):
                if isinstance(e.value, str):
                    lines.append(self.ind() + f'const char* {c_var} = "{e.value}";')
                    self.tuple_fields[node.name].append((c_var, 'str'))
                elif isinstance(e.value, bool):
                    val = 1 if e.value else 0
                    lines.append(self.ind() + f'int {c_var} = {val};')
                    self.tuple_fields[node.name].append((c_var, 'int'))
                elif isinstance(e.value, int):
                    lines.append(self.ind() + f'int {c_var} = {e.value};')
                    self.tuple_fields[node.name].append((c_var, 'int'))
                elif isinstance(e.value, float):
                    lines.append(self.ind() + f'double {c_var} = {e.value};')
                    self.tuple_fields[node.name].append((c_var, 'double'))
            else:
                lines.append(self.ind() + f'int {c_var} = {self.expr(e)};')
                self.tuple_fields[node.name].append((c_var, 'int'))
        return '\n'.join(lines)

    def _print_stmt(self, node: PrintStmt) -> str:
        expr_node = node.expr
        if isinstance(expr_node, Literal) and isinstance(expr_node.value, str):
            return self.ind() + self.T['printStr'].replace('{expr}', self.expr(expr_node))
        if isinstance(expr_node, VarRef):
            if expr_node.name in self.enums:
                return self._print_enum_type(expr_node.name)
            if expr_node.name in self.double_vars:
                return self.ind() + self.T['printFloat'].replace('{expr}', self.expr(expr_node))
            # Print whole dict
            if expr_node.name in self.dict_vars:
                if expr_node.name in self.dict_fields and not self.dict_fields[expr_node.name]:
                    return self.ind() + 'printf("{}\\n");'
                return self.ind() + f'printf("%s\\n", "{expr_node.name}");'
            # Print whole tuple
            if expr_node.name in self.tuple_vars:
                return self._print_whole_tuple(expr_node.name)
        if isinstance(expr_node, IndexAccess):
            if isinstance(expr_node.array, VarRef) and expr_node.array.name in self.enums:
                return self._print_enum_value(expr_node)
            # Dict or tuple access
            resolved = self._resolve_access(expr_node)
            if resolved:
                c_var, typ = resolved
                if typ == 'str':
                    return self.ind() + f'printf("%s\\n", {c_var});'
                elif typ == 'double':
                    return self.ind() + f'printf("%g\\n", {c_var});'
                else:
                    return self.ind() + f'printf("%d\\n", {c_var});'
        if self.is_float_expr(expr_node):
            return self.ind() + self.T['printFloat'].replace('{expr}', self.expr(expr_node))
        return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))

    def _print_whole_tuple(self, name):
        if name not in self.tuple_fields or not self.tuple_fields[name]:
            return self.ind() + 'printf("()\\n");'
        fields = self.tuple_fields[name]
        # Build format like (10, 20)
        parts_fmt = []
        parts_args = []
        for c_var, typ in fields:
            if typ == 'str':
                parts_fmt.append('%s')
            elif typ == 'double':
                parts_fmt.append('%g')
            else:
                parts_fmt.append('%d')
            parts_args.append(c_var)
        fmt = '(' + ', '.join(parts_fmt) + ')\\n'
        args = ', '.join(parts_args)
        return self.ind() + f'printf("{fmt}", {args});'

    def _resolve_access(self, node):
        """Resolve dict/tuple access to (c_var_name, type) or None."""
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
                    c_var, typ = parent
                    if typ == 'array' and isinstance(node.index, Literal) and isinstance(node.index.value, int):
                        return (f'{c_var}[{node.index.value}]', 'int')
        return None

    def expr(self, node) -> str:
        if isinstance(node, IndexAccess):
            resolved = self._resolve_access(node)
            if resolved:
                return resolved[0]
        if isinstance(node, MethodCallExpr):
            s = self.expr(node.args[0]) if node.args else '""'
            if node.method == 'upper': return f'_jj_upper({s})'
            if node.method == 'lower': return f'_jj_lower({s})'
            if node.method == 'length': return f'(int)strlen({s})'
            if node.method == 'trim': return f'_jj_trim({s})'
            if node.method == 'contains' and len(node.args) >= 2: return f'(strstr({s}, {self.expr(node.args[1])}) != NULL)'
            if node.method == 'replace' and len(node.args) >= 3: return f'_jj_replace({s}, {self.expr(node.args[1])}, {self.expr(node.args[2])})'
            if node.method == 'split': return f'/* split not supported in C */'
            if node.method == 'substring' and len(node.args) >= 3: return f'_jj_substr({s}, {self.expr(node.args[1])}, {self.expr(node.args[2])})'
        return super().expr(node)
