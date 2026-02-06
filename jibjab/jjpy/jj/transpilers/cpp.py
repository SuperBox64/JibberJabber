"""
JibJab C++ Transpiler - Converts JJ to C++
Uses shared C-family base from cfamily.py

Arrays: std::vector<T> instead of C-style arrays
Enums: enum class with static_cast for indexing
Dictionaries: expanded to individual variables (person_name, person_age, etc.)
Tuples: stored as numbered variables (_0, _1, _2) with cout for printing
"""

from ..ast import (
    Literal, VarRef, VarDecl, ArrayLiteral, DictLiteral, TupleLiteral,
    IndexAccess, PrintStmt, LogStmt, EnumDef, StringInterpolation, MethodCallExpr
)
from .cfamily import CFamilyTranspiler, infer_type


class CppTranspiler(CFamilyTranspiler):
    target_name = 'cpp'

    def __init__(self):
        super().__init__()
        self.dict_fields = {}   # dict_name -> {key: (cpp_var_name, type)}
        self.tuple_fields = {}  # tuple_name -> [(cpp_var_name, type)]
        self.array_vars = set()
        self.array_meta = {}    # array_name -> {elemType, count, isNested, innerCount, innerElemType}

    def transpile(self, program):
        code = super().transpile(program)
        needs_string = False
        needs_vector = len(self.array_vars) > 0
        for fields in self.dict_fields.values():
            for _, (_, typ) in fields.items():
                if typ == 'str':
                    needs_string = True
        for fields in self.tuple_fields.values():
            for _, typ in fields:
                if typ == 'str':
                    needs_string = True
        if needs_string or needs_vector:
            lines = code.split('\n')
            insert_idx = 0
            for i, line in enumerate(lines):
                if line.startswith('#include'):
                    insert_idx = i + 1
            if needs_vector:
                vec_inc = '#include <vector>'
                if vec_inc not in lines:
                    lines.insert(insert_idx, vec_inc)
                    insert_idx += 1
            if needs_string:
                str_inc = self.T.get('stringInclude', '#include <string>')
                if str_inc not in lines:
                    lines.insert(insert_idx, str_inc)
            code = '\n'.join(lines)
        return code

    # MARK: - Vector arrays

    def _var_array(self, node: VarDecl) -> str:
        self.array_vars.add(node.name)
        if node.value.elements:
            first = node.value.elements[0]
            if isinstance(first, ArrayLiteral):
                inner_type = self.get_target_type(infer_type(first.elements[0])) if first.elements else 'int'
                inner_elem = 'str' if (first.elements and isinstance(first.elements[0], Literal) and isinstance(first.elements[0].value, str)) else 'int'
                self.array_meta[node.name] = {
                    'elemType': 'nested', 'count': len(node.value.elements),
                    'isNested': True, 'innerCount': len(first.elements), 'innerElemType': inner_elem
                }
                elements = ', '.join(self.expr(e) for e in node.value.elements)
                return self.ind() + f'std::vector<std::vector<{inner_type}>> {node.name} = {{{elements}}};'
            if isinstance(first, Literal) and isinstance(first.value, str):
                elem_type = self.T.get('stringType', 'std::string')
                self.array_meta[node.name] = {
                    'elemType': 'str', 'count': len(node.value.elements),
                    'isNested': False
                }
            else:
                elem_type = self.get_target_type(infer_type(first))
                self.array_meta[node.name] = {
                    'elemType': 'int', 'count': len(node.value.elements),
                    'isNested': False
                }
            elements = ', '.join(self.expr(e) for e in node.value.elements)
            return self.ind() + f'std::vector<{elem_type}> {node.name} = {{{elements}}};'
        return self.ind() + f'std::vector<{self.get_target_type("Int")}> {node.name} = {{}};'

    # MARK: - Enum class

    def _enum_def(self, node: EnumDef) -> str:
        self.enums.add(node.name)
        cases = ', '.join(node.cases)
        tmpl = self.T.get('enum', 'enum class {name} { {cases} };')
        result = self.ind() + tmpl.replace('{name}', node.name).replace('{cases}', cases)
        names_list = ', '.join(f'"{c}"' for c in node.cases)
        result += '\n' + self.ind() + f'const char* {node.name}_names[] = {{{names_list}}};'
        return result

    def _interp_var_expr(self, name: str) -> str:
        if name in self.enum_var_types:
            enum_name = self.enum_var_types[name]
            return f'{enum_name}_names[static_cast<int>({name})]'
        return super()._interp_var_expr(name)

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
                        lines.append(self.ind() + f'{self.T.get("stringType", "std::string")} {cpp_var} = "{v.value}";')
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
                            elem_type = self.T.get('stringType', 'std::string')
                        else:
                            elem_type = self.get_target_type(infer_type(first))
                        elements = ', '.join(self.expr(e) for e in v.elements)
                        lines.append(self.ind() + f'std::vector<{elem_type}> {cpp_var} = {{{elements}}};')
                        self.dict_fields[node.name][key] = (cpp_var, 'array')
                    else:
                        lines.append(self.ind() + f'std::vector<int> {cpp_var} = {{}};')
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
                    lines.append(self.ind() + f'{self.T.get("stringType", "std::string")} {cpp_var} = "{e.value}";')
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

    def _cout_line(self, e: str) -> str:
        return self.T.get('coutNewline', 'std::cout << {expr} << std::endl;').replace('{expr}', e)

    def _cout_inline(self, e: str) -> str:
        return self.T.get('coutInline', 'std::cout << {expr};').replace('{expr}', e)

    def _cerr_line(self, e: str) -> str:
        return self.T.get('cerrNewline', 'std::cerr << {expr} << std::endl;').replace('{expr}', e)

    def _log_stmt(self, node: LogStmt) -> str:
        expr_node = node.expr
        if isinstance(expr_node, StringInterpolation):
            parts = []
            for kind, text in expr_node.parts:
                if kind == 'literal':
                    parts.append(f'"{text}"')
                else:
                    if text in self.enum_var_types:
                        enum_name = self.enum_var_types[text]
                        parts.append(f'{enum_name}_names[static_cast<int>({text})]')
                    elif text in self.bool_vars:
                        parts.append(f'({text} ? "true" : "false")')
                    else:
                        parts.append(text)
            sep = self.T.get('cerrSep', ' << ')
            cerr_expr = self.T.get('cerrExpr', 'std::cerr << {expr}').replace('{expr}', sep.join(parts))
            endl = self.T.get('cerrEndl', ' << std::endl;')
            return self.ind() + cerr_expr + endl
        return super()._log_stmt(node)

    def _print_stmt(self, node: PrintStmt) -> str:
        expr_node = node.expr
        if isinstance(expr_node, Literal) and isinstance(expr_node.value, str):
            return self.ind() + self._cout_line(self.expr(expr_node))
        if isinstance(expr_node, VarRef):
            if expr_node.name in self.enums:
                return self.ind() + self._cout_line(f'"enum {expr_node.name}"')
            if expr_node.name in self.array_meta:
                return self._print_whole_array(expr_node.name)
            if expr_node.name in self.double_vars:
                return self.ind() + self.T['printFloat'].replace('{expr}', self.expr(expr_node))
            # Print whole dict
            if expr_node.name in self.dict_vars:
                if expr_node.name in self.dict_fields and not self.dict_fields[expr_node.name]:
                    return self.ind() + self._cout_line('"{}"')
                return self.ind() + self._cout_line(f'"{expr_node.name}"')
            # Print whole tuple
            if expr_node.name in self.tuple_vars:
                return self._print_whole_tuple(expr_node.name)
        if isinstance(expr_node, IndexAccess):
            if isinstance(expr_node.array, VarRef) and expr_node.array.name in self.enums:
                return self.ind() + self._cout_line(self.expr(expr_node))
            # Dict or tuple access
            resolved = self._resolve_access(expr_node)
            if resolved:
                cpp_var, typ = resolved
                return self.ind() + self._cout_line(cpp_var)
        if self.is_float_expr(expr_node):
            return self.ind() + self.T['printFloat'].replace('{expr}', self.expr(expr_node))
        return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))

    def _print_whole_tuple(self, name):
        if name not in self.tuple_fields or not self.tuple_fields[name]:
            return self.ind() + self._cout_line('"()"')
        fields = self.tuple_fields[name]
        sep = self.T.get('coutSep', ' << ')
        endl = self.T.get('coutEndl', ' << std::endl;')
        cout_expr = self.T.get('coutExpr', 'std::cout << {expr}')
        parts = []
        for i, (cpp_var, typ) in enumerate(fields):
            if i == 0:
                parts.append('"("')
            parts.append(cpp_var)
            if i < len(fields) - 1:
                parts.append('", "')
        parts.append('")"')
        return self.ind() + cout_expr.replace('{expr}', sep.join(parts)) + endl

    def _print_whole_array(self, name):
        meta = self.array_meta.get(name)
        if not meta:
            return self.ind() + self._cout_line(name)
        if meta['isNested']:
            lines = []
            lines.append(self.ind() + self._cout_inline('"["'))
            for i in range(meta['count']):
                if i > 0:
                    lines.append(self.ind() + self._cout_inline('", "'))
                lines.append(self.ind() + self._cout_inline('"["'))
                for j in range(meta['innerCount']):
                    if j > 0:
                        lines.append(self.ind() + self._cout_inline('", "'))
                    lines.append(self.ind() + self._cout_inline(f'{name}[{i}][{j}]'))
                lines.append(self.ind() + self._cout_inline('"]"'))
            lines.append(self.ind() + self._cout_line('"]"'))
            return '\n'.join(lines)
        count = meta['count']
        lines = []
        lines.append(self.ind() + self._cout_inline('"["'))
        lines.append(self.ind() + f'for (int _i = 0; _i < {count}; _i++) {{')
        self.indent += 1
        lines.append(self.ind() + 'if (_i > 0) ' + self._cout_inline('", "'))
        lines.append(self.ind() + self._cout_inline(f'{name}[_i]'))
        self.indent -= 1
        lines.append(self.ind() + '}')
        lines.append(self.ind() + self._cout_line('"]"'))
        return '\n'.join(lines)

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
        if isinstance(node, MethodCallExpr):
            s = self.expr(node.args[0]) if node.args else '""'
            if node.method == 'upper': return f'_jj_upper({s})'
            if node.method == 'lower': return f'_jj_lower({s})'
            if node.method == 'length': return f'(int){s}.length()'
            if node.method == 'trim': return f'_jj_trim({s})'
            if node.method == 'contains' and len(node.args) >= 2: return f'({s}.find({self.expr(node.args[1])}) != std::string::npos)'
            if node.method == 'replace' and len(node.args) >= 3: return f'_jj_replace({s}, {self.expr(node.args[1])}, {self.expr(node.args[2])})'
            if node.method == 'split': return f'/* split not supported in C++ */'
            if node.method == 'substring' and len(node.args) >= 3: return f'{s}.substr({self.expr(node.args[1])}, {self.expr(node.args[2])} - {self.expr(node.args[1])})'
        return super().expr(node)
