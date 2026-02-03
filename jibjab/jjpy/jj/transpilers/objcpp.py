"""
JibJab Objective-C++ Transpiler - Converts JJ to Objective-C++
Uses shared C-family base from cfamily.py

Blends: C++ output (cout), ObjC collections (Foundation), C++ enums (enum class)
Dict/Tuple string fields: NSString * with @"..." values
"""

from ..ast import (
    Literal, VarRef, VarDecl, ArrayLiteral, DictLiteral, TupleLiteral,
    IndexAccess, EnumDef, PrintStmt, FuncDef, StringInterpolation
)
from .objc import ObjCTranspiler
from .cfamily import infer_type


class ObjCppTranspiler(ObjCTranspiler):
    target_name = 'objcpp'

    # MARK: - C++ style bools (override ObjC's BOOL/YES/NO)

    def _expand_bool_type(self):
        return 'bool'

    def _expand_bool_value(self, val):
        return 'true' if val else 'false'

    # MARK: - Cout helpers

    def _cout_line(self, e: str) -> str:
        return self.T.get('coutNewline', 'std::cout << {expr} << std::endl;').replace('{expr}', e)

    def _cout_inline(self, e: str) -> str:
        return self.T.get('coutInline', 'std::cout << {expr};').replace('{expr}', e)

    def _cout_str(self, text: str, quoted: bool = True) -> str:
        val = f'"{text}"' if quoted else text
        return self.T.get('coutInline', 'std::cout << {expr};').replace('{expr}', val)

    def _cout_line_str(self, text: str) -> str:
        return self._cout_line(f'"{text}"')

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

    # MARK: - Print using cout

    def _print_stmt(self, node: PrintStmt) -> str:
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
            sep = self.T.get('coutSep', ' << ')
            cout_expr = self.T.get('coutExpr', 'std::cout << {expr}').replace('{expr}', sep.join(parts))
            endl = self.T.get('coutEndl', ' << std::endl;')
            return self.ind() + cout_expr + endl
        if isinstance(expr_node, Literal) and isinstance(expr_node.value, str):
            return self.ind() + self._cout_line(self.expr(expr_node))
        if isinstance(expr_node, VarRef):
            if expr_node.name in self.enum_var_types:
                enum_name = self.enum_var_types[expr_node.name]
                return self.ind() + self._cout_line(f'{enum_name}_names[static_cast<int>({expr_node.name})]')
            if expr_node.name in self.enums:
                return self.ind() + self._cout_line(f'"enum {expr_node.name}"')
            if expr_node.name in self.array_vars:
                return self._print_whole_array(expr_node.name)
            if expr_node.name in self.dict_vars:
                if expr_node.name in self.dict_fields and not self.dict_fields[expr_node.name]:
                    return self.ind() + self._cout_line('"{}"')
                return self.ind() + self._cout_line(f'"{expr_node.name}"')
            if expr_node.name in self.tuple_vars:
                return self._print_whole_tuple(expr_node.name)
            if expr_node.name in self.double_vars:
                return self.ind() + self._cout_line(self.expr(expr_node))
            if expr_node.name in self.string_vars:
                sel = self._selector_expr(self.expr(expr_node), 'str')
                return self.ind() + self._cout_line(sel)
            if expr_node.name in self.bool_vars:
                return self.ind() + self._cout_line(f'({expr_node.name} ? "true" : "false")')
            if expr_node.name in self.int_vars:
                return self.ind() + self._cout_line(self.expr(expr_node))
            return self.ind() + self._cout_line(self.expr(expr_node))
        if isinstance(expr_node, ArrayLiteral):
            return self.ind() + self._cout_line(self.expr(expr_node))
        if isinstance(expr_node, IndexAccess):
            if isinstance(expr_node.array, VarRef) and expr_node.array.name in self.enums:
                if isinstance(expr_node.index, Literal) and isinstance(expr_node.index.value, str):
                    return self.ind() + self._cout_line(f'"{expr_node.index.value}"')
            # Array element access
            if isinstance(expr_node.array, VarRef) and expr_node.array.name in self.array_meta:
                meta = self.array_meta[expr_node.array.name]
                if not meta.get('isNested'):
                    elem_expr = self._selector_expr(f'{expr_node.array.name}[{self.expr(expr_node.index)}]', meta['elemType'])
                    return self.ind() + self._cout_line(elem_expr)
            # Nested array element
            if isinstance(expr_node.array, IndexAccess):
                inner = expr_node.array
                if isinstance(inner.array, VarRef) and inner.array.name in self.array_meta:
                    meta = self.array_meta[inner.array.name]
                    if meta.get('isNested'):
                        elem_expr = self._selector_expr(f'{inner.array.name}[{self.expr(inner.index)}][{self.expr(expr_node.index)}]', meta['innerElemType'])
                        return self.ind() + self._cout_line(elem_expr)
            # Dict or tuple access (only apply selector for str - NSString* fields)
            resolved = self._resolve_access(expr_node)
            if resolved:
                c_var, typ = resolved
                print_expr = self._selector_expr(c_var, typ) if typ == 'str' else c_var
                return self.ind() + self._cout_line(print_expr)
            return self.ind() + self._cout_line(self.expr(expr_node))
        if self.is_float_expr(expr_node):
            return self.ind() + self._cout_line(self.expr(expr_node))
        return self.ind() + self._cout_line(self.expr(expr_node))

    def _print_whole_array(self, name):
        if name not in self.array_meta:
            return self.ind() + self._cout_line(name)
        meta = self.array_meta[name]
        idx_type = self.T.get('loopIndexType', 'NSUInteger')
        if meta.get('isNested'):
            lines = []
            lines.append(self.ind() + self._cout_str('['))
            lines.append(self.ind() + f'for ({idx_type} _i = 0; _i < [{name} count]; _i++) {{')
            lines.append(self.ind() + '    if (_i > 0) ' + self._cout_str(', '))
            arr_type = self.T.get('arrayType', 'NSArray *')
            lines.append(self.ind() + f'    {arr_type}_row = {name}[_i];')
            lines.append(self.ind() + '    ' + self._cout_str('['))
            lines.append(self.ind() + f'    for ({idx_type} _j = 0; _j < [_row count]; _j++) {{')
            lines.append(self.ind() + '        if (_j > 0) ' + self._cout_str(', '))
            sel = self._selector_expr('_row[_j]', meta['innerElemType'])
            lines.append(self.ind() + '        ' + self._cout_str(sel, quoted=False))
            lines.append(self.ind() + '    }')
            lines.append(self.ind() + '    ' + self._cout_str(']'))
            lines.append(self.ind() + '}')
            lines.append(self.ind() + self._cout_line_str(']'))
            return '\n'.join(lines)
        lines = []
        lines.append(self.ind() + self._cout_str('['))
        lines.append(self.ind() + f'for ({idx_type} _i = 0; _i < [{name} count]; _i++) {{')
        lines.append(self.ind() + '    if (_i > 0) ' + self._cout_str(', '))
        sel = self._selector_expr(f'{name}[_i]', meta['elemType'])
        lines.append(self.ind() + '    ' + self._cout_str(sel, quoted=False))
        lines.append(self.ind() + '}')
        lines.append(self.ind() + self._cout_line_str(']'))
        return '\n'.join(lines)

    def _print_whole_tuple(self, name):
        if name not in self.tuple_fields or not self.tuple_fields[name]:
            return self.ind() + self._cout_line('"()"')
        fields = self.tuple_fields[name]
        sep = self.T.get('coutSep', ' << ')
        endl = self.T.get('coutEndl', ' << std::endl;')
        cout_expr_tmpl = self.T.get('coutExpr', 'std::cout << {expr}')
        parts = []
        for i, (cpp_var, typ) in enumerate(fields):
            if i == 0:
                parts.append('"("')
            parts.append(self._selector_expr(cpp_var, typ) if typ == 'str' else cpp_var)
            if i < len(fields) - 1:
                parts.append('", "')
        parts.append('")"')
        return self.ind() + cout_expr_tmpl.replace('{expr}', sep.join(parts)) + endl
