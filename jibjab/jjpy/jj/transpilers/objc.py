"""
JibJab Objective-C Transpiler - Converts JJ to Objective-C
Uses shared C-family base from cfamily.py

Dict/Tuple string fields: NSString * with @"..." values
Arrays: NSArray with Foundation boxing
Enums: NS_ENUM (typedef)
"""

from ..ast import (
    Literal, VarRef, VarDecl, ArrayLiteral, DictLiteral, TupleLiteral,
    IndexAccess, EnumDef, PrintStmt, LogStmt, FuncDef, StringInterpolation
)
from .cfamily import CFamilyTranspiler, infer_type


class ObjCTranspiler(CFamilyTranspiler):
    target_name = 'objc'

    def __init__(self):
        super().__init__()
        self.dict_fields = {}   # dict_name -> {key: (var_name, type)}
        self.tuple_fields = {}  # tuple_name -> [(var_name, type)]
        self.array_meta = {}    # array_name -> {elemType, count, isNested, ...}
        self.array_vars = set()

    def _emit_main(self, lines, program):
        main_stmts = [s for s in program.statements if not isinstance(s, FuncDef)]
        if main_stmts:
            main_tmpl = self.T.get('main')
            if main_tmpl:
                self.indent = 2
                body_lines = [self.stmt(s) for s in main_stmts]
                body = '\n'.join(body_lines) + '\n'
                expanded = main_tmpl.replace('\\n', '\n').replace('{body}', body)
                lines.append(expanded)
            else:
                lines.append('int main(int argc, const char * argv[]) {')
                lines.append('    @autoreleasepool {')
                self.indent = 2
                for s in main_stmts:
                    lines.append(self.stmt(s))
                lines.append('    }')
                lines.append('    return 0;')
                lines.append('}')

    # MARK: - Selector helpers

    def _selector_expr(self, expr_str, typ):
        """Apply selector access for a given type (e.g. [expr UTF8String])"""
        sel_map = {
            'str': self.T.get('strSelector'),
            'double': self.T.get('doubleSelector'),
        }
        selector = sel_map.get(typ, self.T.get('intSelector'))
        tmpl = self.T.get('selectorAccess')
        if selector and tmpl:
            return tmpl.replace('{expr}', expr_str).replace('{selector}', selector)
        return expr_str

    def _fmt_specifier(self, typ):
        """Format specifier for printf-style output"""
        m = {
            'str': self.T.get('strFmt', '%s'),
            'double': self.T.get('doubleFmt', '%g'),
            'bool': self.T.get('boolFmt', '%s'),
        }
        return m.get(typ, self.T.get('intFmt', '%d'))

    def _printf_inline(self, text):
        return self.T.get('printfInline', 'printf("{fmt}"{args});').replace('{fmt}', text).replace('{args}', '')

    def _printf_inline_args(self, fmt, args):
        return self.T.get('printfInline', 'printf("{fmt}"{args});').replace('{fmt}', fmt).replace('{args}', f', {args}')

    def _printf_interp_str(self, text):
        return self.T.get('printfInterp', 'printf("{fmt}\\n"{args});').replace('{fmt}', text).replace('{args}', '')

    def _print_template_for_type(self, typ):
        m = {
            'str': self.T.get('printStr', ''),
            'double': self.T.get('printFloat', ''),
            'bool': self.T.get('printBool', self.T.get('printInt', '')),
        }
        return m.get(typ, self.T.get('printInt', ''))

    # MARK: - Log statement (NSLog)

    def _log_stmt(self, node: LogStmt) -> str:
        expr_node = node.expr
        tmpl = self.T.get('logfInterp', 'NSLog(@"{fmt}"{args});')
        if isinstance(expr_node, StringInterpolation):
            fmt = ''
            args = []
            for kind, text in expr_node.parts:
                if kind == 'literal':
                    fmt += text
                else:
                    fmt += self._interp_format_specifier(text)
                    args.append(self._interp_var_expr(text))
            arg_str = '' if not args else ', ' + ', '.join(args)
            return self.ind() + tmpl.replace('{fmt}', fmt).replace('{args}', arg_str)
        if isinstance(expr_node, Literal) and isinstance(expr_node.value, str):
            return self.ind() + self.T.get('logStr', 'NSLog(@"%@", {expr});').replace('{expr}', f'@{self.expr(expr_node)}')
        if isinstance(expr_node, VarRef):
            if expr_node.name in self.enum_var_types:
                enum_name = self.enum_var_types[expr_node.name]
                return self.ind() + self.T.get('logStr', 'NSLog(@"%@", {expr});').replace('{expr}', f'{enum_name}_names[{expr_node.name}]')
            if expr_node.name in self.double_vars:
                return self.ind() + self.T.get('logFloat', self.T.get('logDouble', 'NSLog(@"%f", {expr});')).replace('{expr}', self.expr(expr_node))
            if expr_node.name in self.string_vars:
                # const char* needs @() boxing for NSLog %@
                return self.ind() + self.T.get('logStr', 'NSLog(@"%@", {expr});').replace('{expr}', f'@({self.expr(expr_node)})')
            if expr_node.name in self.bool_vars:
                return self.ind() + self.T.get('logBool', 'NSLog(@"%@", {expr} ? @"true" : @"false");').replace('{expr}', self.expr(expr_node))
            if expr_node.name in self.int_vars:
                return self.ind() + self.T.get('logInt', 'NSLog(@"%ld", (long){expr});').replace('{expr}', self.expr(expr_node))
            # Default: unknown var type, use %@ with @() boxing
            return self.ind() + self.T.get('logStr', 'NSLog(@"%@", {expr});').replace('{expr}', f'@({self.expr(expr_node)})')
        return super()._log_stmt(node)

    # MARK: - Print statement

    def _print_stmt(self, node: PrintStmt) -> str:
        expr_node = node.expr
        tmpl = self.T.get('printfInterp', 'printf("{fmt}\\n"{args});')
        if isinstance(expr_node, StringInterpolation):
            fmt = ''
            args = []
            for kind, text in expr_node.parts:
                if kind == 'literal':
                    fmt += text
                else:
                    fmt += self._interp_format_specifier(text)
                    args.append(self._interp_var_expr(text))
            arg_str = '' if not args else ', ' + ', '.join(args)
            return self.ind() + tmpl.replace('{fmt}', fmt).replace('{args}', arg_str)
        if isinstance(expr_node, Literal) and isinstance(expr_node.value, str):
            return self.ind() + self.T['printStr'].replace('{expr}', self.expr(expr_node))
        if isinstance(expr_node, VarRef):
            if expr_node.name in self.enum_var_types:
                enum_name = self.enum_var_types[expr_node.name]
                return self.ind() + self.T['printStr'].replace('{expr}', f'{enum_name}_names[{expr_node.name}]')
            if expr_node.name in self.enums:
                return self.ind() + self.T['printStr'].replace('{expr}', f'"enum {expr_node.name}"')
            if expr_node.name in self.array_vars:
                return self._print_whole_array(expr_node.name)
            if expr_node.name in self.double_vars:
                return self.ind() + self.T['printFloat'].replace('{expr}', self.expr(expr_node))
            if expr_node.name in self.string_vars:
                sel = self._selector_expr(self.expr(expr_node), 'str')
                return self.ind() + self.T['printStr'].replace('{expr}', sel)
            if expr_node.name in self.bool_vars:
                return self.ind() + self.T.get('printBool', self.T['printInt']).replace('{expr}', self.expr(expr_node))
            if expr_node.name in self.int_vars:
                return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))
            if expr_node.name in self.dict_vars:
                if expr_node.name in self.dict_fields and not self.dict_fields[expr_node.name]:
                    return self.ind() + self.T['printStr'].replace('{expr}', '"{}"')
                if expr_node.name in self.foundation_dicts:
                    return self.ind() + self.T['printStr'].replace('{expr}', f'[[{expr_node.name} description] UTF8String]')
                return self.ind() + self.T['printStr'].replace('{expr}', f'"{expr_node.name}"')
            if expr_node.name in self.tuple_vars:
                return self._print_whole_tuple(expr_node.name)
            return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))
        if isinstance(expr_node, ArrayLiteral):
            return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))
        if isinstance(expr_node, IndexAccess):
            if isinstance(expr_node.array, VarRef) and expr_node.array.name in self.enums:
                if isinstance(expr_node.index, Literal) and isinstance(expr_node.index.value, str):
                    return self.ind() + self.T['printStr'].replace('{expr}', f'"{expr_node.index.value}"')
            # Array element access
            if isinstance(expr_node.array, VarRef) and expr_node.array.name in self.array_meta:
                meta = self.array_meta[expr_node.array.name]
                if not meta.get('isNested'):
                    elem_expr = self._selector_expr(f'{expr_node.array.name}[{self.expr(expr_node.index)}]', meta['elemType'])
                    return self.ind() + self._print_template_for_type(meta['elemType']).replace('{expr}', elem_expr)
            # Nested array element
            if isinstance(expr_node.array, IndexAccess):
                inner = expr_node.array
                if isinstance(inner.array, VarRef) and inner.array.name in self.array_meta:
                    meta = self.array_meta[inner.array.name]
                    if meta.get('isNested'):
                        elem_expr = self._selector_expr(f'{inner.array.name}[{self.expr(inner.index)}][{self.expr(expr_node.index)}]', meta['innerElemType'])
                        return self.ind() + self._print_template_for_type(meta['innerElemType']).replace('{expr}', elem_expr)
            # Dict or tuple access — foundation collections need selector for ALL types
            resolved = self._resolve_access(expr_node)
            if resolved:
                c_var, typ = resolved
                needs_selector = typ == 'str' or self._is_foundation_collection_access(expr_node)
                print_expr = self._selector_expr(c_var, typ) if needs_selector else c_var
                return self.ind() + self._print_template_for_type(typ).replace('{expr}', print_expr)
            return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))
        if self.is_float_expr(expr_node):
            return self.ind() + self.T['printFloat'].replace('{expr}', self.expr(expr_node))
        return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))

    def _print_whole_array(self, name):
        if name not in self.array_meta:
            return self.ind() + self.T['printStr'].replace('{expr}', name)
        meta = self.array_meta[name]
        idx_type = self.T.get('loopIndexType', 'NSUInteger')
        if meta.get('isNested'):
            lines = []
            lines.append(self.ind() + self._printf_inline('['))
            lines.append(self.ind() + f'for ({idx_type} _i = 0; _i < [{name} count]; _i++) {{')
            lines.append(self.ind() + '    if (_i > 0) ' + self._printf_inline(', '))
            arr_type = self.T.get('arrayType', 'NSArray *')
            lines.append(self.ind() + f'    {arr_type}_row = {name}[_i];')
            lines.append(self.ind() + '    ' + self._printf_inline('['))
            lines.append(self.ind() + f'    for ({idx_type} _j = 0; _j < [_row count]; _j++) {{')
            lines.append(self.ind() + '        if (_j > 0) ' + self._printf_inline(', '))
            fmt = self._fmt_specifier(meta['innerElemType'])
            sel = self._selector_expr('_row[_j]', meta['innerElemType'])
            lines.append(self.ind() + '        ' + self._printf_inline_args(fmt, sel))
            lines.append(self.ind() + '    }')
            lines.append(self.ind() + '    ' + self._printf_inline(']'))
            lines.append(self.ind() + '}')
            lines.append(self.ind() + self._printf_interp_str(']'))
            return '\n'.join(lines)
        lines = []
        lines.append(self.ind() + self._printf_inline('['))
        lines.append(self.ind() + f'for ({idx_type} _i = 0; _i < [{name} count]; _i++) {{')
        lines.append(self.ind() + '    if (_i > 0) ' + self._printf_inline(', '))
        fmt = self._fmt_specifier(meta['elemType'])
        sel = self._selector_expr(f'{name}[_i]', meta['elemType'])
        lines.append(self.ind() + '    ' + self._printf_inline_args(fmt, sel))
        lines.append(self.ind() + '}')
        lines.append(self.ind() + self._printf_interp_str(']'))
        return '\n'.join(lines)

    def _print_whole_tuple(self, name):
        if name not in self.tuple_fields or not self.tuple_fields[name]:
            return self.ind() + self.T['printStr'].replace('{expr}', '"()"')
        # Foundation mode: print NSArray description
        if name in self.foundation_tuples:
            return self.ind() + self.T['printStr'].replace('{expr}', f'[[{name} description] UTF8String]')
        # Expand mode: printf with format specifiers
        fields = self.tuple_fields[name]
        fmt_parts = []
        arg_parts = []
        for c_var, typ in fields:
            fmt_parts.append(self._fmt_specifier(typ))
            arg_parts.append(self._selector_expr(c_var, typ) if typ == 'str' else c_var)
        fmt_str = '(' + ', '.join(fmt_parts) + ')'
        args = ', '.join(arg_parts)
        tmpl = self.T.get('printfInterp', 'printf("{fmt}\\n"{args});')
        return self.ind() + tmpl.replace('{fmt}', fmt_str).replace('{args}', f', {args}')

    # MARK: - ObjC idiomatic bool: BOOL with YES/NO

    def _expand_bool_type(self):
        return 'BOOL'

    def _expand_bool_value(self, val):
        return 'YES' if val else 'NO'

    # MARK: - Dict/Tuple expansion with NSString *

    def _var_dict(self, node: VarDecl) -> str:
        lines = []
        self.dict_fields[node.name] = {}
        if not node.value.pairs:
            if self.T.get('collectionStyle') == 'foundation':
                self.foundation_dicts.add(node.name)
                return self.ind() + f'NSDictionary *{node.name} = @{{}};'
            lines.append(self.ind() + f'{self.T.get("comment", "//")} empty dict {node.name}')
            return '\n'.join(lines)
        # Foundation mode: NSDictionary literal
        if self.T.get('collectionStyle') == 'foundation':
            self.foundation_dicts.add(node.name)
            for k, v in node.value.pairs:
                if isinstance(k, Literal) and isinstance(k.value, str):
                    key = k.value
                    access = f'{node.name}[@"{key}"]'
                    if isinstance(v, Literal):
                        if isinstance(v.value, str):
                            self.dict_fields[node.name][key] = (access, 'str')
                        elif isinstance(v.value, bool):
                            self.dict_fields[node.name][key] = (access, 'int')
                        elif isinstance(v.value, int):
                            self.dict_fields[node.name][key] = (access, 'int')
                        elif isinstance(v.value, float):
                            self.dict_fields[node.name][key] = (access, 'double')
                    elif isinstance(v, ArrayLiteral):
                        self.dict_fields[node.name][key] = (access, 'array')
            return self.ind() + f'NSDictionary *{node.name} = {self._expr_dict(node.value)};'
        # Expand mode: individual variables with NSString */NSInteger/BOOL
        for k, v in node.value.pairs:
            if isinstance(k, Literal) and isinstance(k.value, str):
                key = k.value
                var_name = f'{node.name}_{key}'
                if isinstance(v, Literal):
                    if isinstance(v.value, str):
                        lines.append(self.ind() + f'NSString *{var_name} = @"{v.value}";')
                        self.dict_fields[node.name][key] = (var_name, 'str')
                    elif isinstance(v.value, bool):
                        val = self._expand_bool_value(v.value)
                        lines.append(self.ind() + f'{self._expand_bool_type()} {var_name} = {val};')
                        self.dict_fields[node.name][key] = (var_name, 'int')
                    elif isinstance(v.value, int):
                        target_type = self.get_target_type('Int')
                        lines.append(self.ind() + f'{target_type} {var_name} = {v.value};')
                        self.dict_fields[node.name][key] = (var_name, 'int')
                    elif isinstance(v.value, float):
                        lines.append(self.ind() + f'double {var_name} = {v.value};')
                        self.dict_fields[node.name][key] = (var_name, 'double')
                elif isinstance(v, ArrayLiteral):
                    if v.elements:
                        first = v.elements[0]
                        if isinstance(first, Literal) and isinstance(first.value, str):
                            elem_type = self.T.get('expandStringType', 'const char*')
                        else:
                            elem_type = self.get_target_type(infer_type(first))
                        elements = ', '.join(self.expr(e) for e in v.elements)
                        lines.append(self.ind() + f'{elem_type} {var_name}[] = {{{elements}}};')
                        self.dict_fields[node.name][key] = (var_name, 'array')
                    else:
                        lines.append(self.ind() + f'int {var_name}[] = {{}};')
                        self.dict_fields[node.name][key] = (var_name, 'array')
        return '\n'.join(lines)

    def _var_tuple(self, node: VarDecl) -> str:
        lines = []
        self.tuple_fields[node.name] = []
        if not node.value.elements:
            if self.T.get('collectionStyle') == 'foundation':
                self.foundation_tuples.add(node.name)
                return self.ind() + f'NSArray *{node.name} = @[];'
            lines.append(self.ind() + f'{self.T.get("comment", "//")} empty tuple {node.name}')
            return '\n'.join(lines)
        # Foundation mode: NSArray literal
        if self.T.get('collectionStyle') == 'foundation':
            self.foundation_tuples.add(node.name)
            for i, e in enumerate(node.value.elements):
                access = f'{node.name}[{i}]'
                if isinstance(e, Literal):
                    if isinstance(e.value, str):
                        self.tuple_fields[node.name].append((access, 'str'))
                    elif isinstance(e.value, bool):
                        self.tuple_fields[node.name].append((access, 'int'))
                    elif isinstance(e.value, int):
                        self.tuple_fields[node.name].append((access, 'int'))
                    elif isinstance(e.value, float):
                        self.tuple_fields[node.name].append((access, 'double'))
                else:
                    self.tuple_fields[node.name].append((access, 'int'))
            return self.ind() + f'NSArray *{node.name} = {self._expr_tuple(node.value)};'
        # Expand mode: individual variables
        for i, e in enumerate(node.value.elements):
            var_name = f'{node.name}_{i}'
            if isinstance(e, Literal):
                if isinstance(e.value, str):
                    lines.append(self.ind() + f'NSString *{var_name} = @"{e.value}";')
                    self.tuple_fields[node.name].append((var_name, 'str'))
                elif isinstance(e.value, bool):
                    val = self._expand_bool_value(e.value)
                    lines.append(self.ind() + f'{self._expand_bool_type()} {var_name} = {val};')
                    self.tuple_fields[node.name].append((var_name, 'int'))
                elif isinstance(e.value, int):
                    target_type = self.get_target_type('Int')
                    lines.append(self.ind() + f'{target_type} {var_name} = {e.value};')
                    self.tuple_fields[node.name].append((var_name, 'int'))
                elif isinstance(e.value, float):
                    lines.append(self.ind() + f'double {var_name} = {e.value};')
                    self.tuple_fields[node.name].append((var_name, 'double'))
            else:
                target_type = self.get_target_type('Int')
                lines.append(self.ind() + f'{target_type} {var_name} = {self.expr(e)};')
                self.tuple_fields[node.name].append((var_name, 'int'))
        return '\n'.join(lines)

    def _var_array(self, node: VarDecl) -> str:
        self.array_vars.add(node.name)
        arr_type = self.T.get('arrayType', 'NSArray *')
        # Track array metadata
        if node.value.elements:
            first = node.value.elements[0]
            if isinstance(first, ArrayLiteral):
                inner_type = 'str' if (first.elements and isinstance(first.elements[0], Literal) and isinstance(first.elements[0].value, str)) else ('double' if (first.elements and isinstance(first.elements[0], Literal) and isinstance(first.elements[0].value, float)) else 'int')
                self.array_meta[node.name] = {
                    'elemType': 'nested', 'count': len(node.value.elements),
                    'isNested': True, 'innerCount': len(first.elements), 'innerElemType': inner_type
                }
            else:
                jj_type = infer_type(first)
                e_type = 'str' if jj_type == 'String' else ('double' if jj_type == 'Double' else 'int')
                self.array_meta[node.name] = {
                    'elemType': e_type, 'count': len(node.value.elements),
                    'isNested': False, 'innerCount': 0, 'innerElemType': ''
                }
        return self.ind() + f"{arr_type}{node.name} = {self.expr(node.value)};"

    def _resolve_access(self, node):
        """Resolve dict/tuple access to (var_name, type) or None."""
        if isinstance(node, IndexAccess):
            if isinstance(node.array, VarRef) and node.array.name in self.dict_fields:
                if isinstance(node.index, Literal) and isinstance(node.index.value, str):
                    fields = self.dict_fields[node.array.name]
                    if node.index.value in fields:
                        return fields[node.index.value]
            if isinstance(node.array, VarRef) and node.array.name in self.tuple_fields:
                if isinstance(node.index, Literal) and isinstance(node.index.value, int):
                    fields = self.tuple_fields[node.array.name]
                    idx = node.index.value
                    if idx < len(fields):
                        return fields[idx]
            if isinstance(node.array, IndexAccess):
                parent = self._resolve_access(node.array)
                if parent:
                    c_var, typ = parent
                    if typ == 'array' and isinstance(node.index, Literal) and isinstance(node.index.value, int):
                        return (f'{c_var}[{node.index.value}]', 'int')
        return None

    def _enum_def(self, node: EnumDef) -> str:
        self.enums.add(node.name)
        cases = ', '.join(node.cases)
        tmpl = self.T.get('enum', 'typedef NS_ENUM(NSInteger, {name}) { {cases} };')
        return self.ind() + tmpl.replace('{name}', node.name).replace('{cases}', cases)

    def expr(self, node) -> str:
        if isinstance(node, IndexAccess):
            # Dict access: use @"key" syntax
            if isinstance(node.array, VarRef) and node.array.name in self.dict_vars:
                if isinstance(node.index, Literal) and isinstance(node.index.value, str):
                    return f'{node.array.name}[@"{node.index.value}"]'
                return f'{self.expr(node.array)}[@({self.expr(node.index)})]'
            # Nested: data[@"items"][0]
            if isinstance(node.array, IndexAccess):
                if isinstance(node.array.array, VarRef) and node.array.array.name in self.dict_vars:
                    inner = self.expr(node.array)
                    return f'{inner}[{self.expr(node.index)}]'
            # Dict/tuple field resolution
            resolved = self._resolve_access(node)
            if resolved:
                return resolved[0]
        return super().expr(node)

    def _box_str(self, e: str) -> str:
        tmpl = self.T.get('boxString', '@{expr}')
        return tmpl.replace('{expr}', e)

    def _box_val(self, e: str) -> str:
        tmpl = self.T.get('boxValue', '@({expr})')
        return tmpl.replace('{expr}', e)

    def _expr_array(self, node: ArrayLiteral) -> str:
        arr_open = self.T.get('arrayLitOpen', '@[')
        arr_close = self.T.get('arrayLitClose', ']')
        def box_element(e):
            if isinstance(e, Literal):
                if isinstance(e.value, str):
                    return self._box_str(self.expr(e))
                else:
                    return self._box_val(self.expr(e))
            elif isinstance(e, ArrayLiteral):
                return self.expr(e)
            else:
                return self._box_val(self.expr(e))
        elements = ', '.join(box_element(e) for e in node.elements)
        return f"{arr_open}{elements}{arr_close}"

    def _expr_dict(self, node: DictLiteral) -> str:
        dict_open = self.T.get('dictLitOpen', '@{')
        dict_close = self.T.get('dictLitClose', '}')
        def box_value(v):
            if isinstance(v, Literal) and isinstance(v.value, str):
                return self._box_str(self.expr(v))
            elif isinstance(v, ArrayLiteral):
                return self.expr(v)
            else:
                return self._box_val(self.expr(v))
        pairs = ', '.join(f"{self._box_str(self.expr(k))}: {box_value(v)}" for k, v in node.pairs)
        return f"{dict_open}{pairs}{dict_close}"

    def _expr_tuple(self, node: TupleLiteral) -> str:
        arr_open = self.T.get('arrayLitOpen', '@[')
        arr_close = self.T.get('arrayLitClose', ']')
        def box_element(e):
            if isinstance(e, Literal) and isinstance(e.value, str):
                return self._box_str(self.expr(e))
            else:
                return self._box_val(self.expr(e))
        elements = ', '.join(box_element(e) for e in node.elements)
        return f"{arr_open}{elements}{arr_close}"
