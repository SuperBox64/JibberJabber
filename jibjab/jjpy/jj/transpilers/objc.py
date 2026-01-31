"""
JibJab Objective-C Transpiler - Converts JJ to Objective-C
Uses shared C-family base from cfamily.py
"""

from ..ast import (
    Literal, VarRef, VarDecl, ArrayLiteral, DictLiteral, TupleLiteral,
    IndexAccess, EnumDef, PrintStmt, FuncDef, StringInterpolation
)
from .cfamily import CFamilyTranspiler, infer_type


class ObjCTranspiler(CFamilyTranspiler):
    target_name = 'objc'

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
            if expr_node.name in self.enums:
                return self.ind() + self.T['printStr'].replace('{expr}', f'"enum {expr_node.name}"')
            if expr_node.name in self.double_vars:
                return self.ind() + self.T['printFloat'].replace('{expr}', self.expr(expr_node))
            if expr_node.name in self.string_vars:
                return self.ind() + self.T['printStr'].replace('{expr}', self.expr(expr_node))
            if expr_node.name in self.bool_vars:
                return self.ind() + self.T.get('printBool', self.T['printInt']).replace('{expr}', self.expr(expr_node))
            if expr_node.name in self.int_vars:
                return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))
            return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))
        if isinstance(expr_node, ArrayLiteral):
            return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))
        if isinstance(expr_node, IndexAccess):
            if isinstance(expr_node.array, VarRef) and expr_node.array.name in self.enums:
                return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))
            return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))
        if self.is_float_expr(expr_node):
            return self.ind() + self.T['printFloat'].replace('{expr}', self.expr(expr_node))
        return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))

    def _var_dict(self, node: VarDecl) -> str:
        dict_type = self.T.get('dictType', 'NSDictionary *')
        if not node.value.pairs:
            return self.ind() + f"{dict_type}{node.name} = {self.T.get('dictLitOpen', '@{{')}{self.T.get('dictLitClose', '}')};"
        return self.ind() + f"{dict_type}{node.name} = {self.expr(node.value)};"

    def _var_tuple(self, node: VarDecl) -> str:
        arr_type = self.T.get('arrayType', 'NSArray *')
        return self.ind() + f"{arr_type}{node.name} = {self.expr(node.value)};"

    def _var_array(self, node: VarDecl) -> str:
        arr_type = self.T.get('arrayType', 'NSArray *')
        return self.ind() + f"{arr_type}{node.name} = {self.expr(node.value)};"

    def _enum_def(self, node: EnumDef) -> str:
        self.enums.add(node.name)
        cases = ', '.join(node.cases)
        return self.ind() + f"typedef NS_ENUM(NSInteger, {node.name}) {{ {cases} }};"

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
