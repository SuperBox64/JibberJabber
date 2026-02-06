"""
JibJab C-Family Base Transpiler
Shared logic for C, C++, Objective-C, and Objective-C++ transpilers.
Subclasses override specific methods for target-specific behavior.
"""

from ..lexer import load_target_config
from ..ast import (
    ASTNode, Program, PrintStmt, LogStmt, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, TryStmt, FuncDef, FuncCall,
    ReturnStmt, ThrowStmt, ArrayLiteral, DictLiteral, TupleLiteral, IndexAccess,
    EnumDef, StringInterpolation, MethodCallExpr
)


def infer_type(node) -> str:
    """Infer JJ type from AST node"""
    if isinstance(node, Literal):
        if isinstance(node.value, bool):
            return 'Bool'
        elif isinstance(node.value, int):
            return 'Int'
        elif isinstance(node.value, float):
            return 'Double'
        elif isinstance(node.value, str):
            return 'String'
    elif isinstance(node, ArrayLiteral):
        if node.elements:
            return infer_type(node.elements[0])
        return 'Int'
    return 'Int'


class CFamilyTranspiler:
    """Base transpiler for C-family languages (C, C++, ObjC, ObjC++)."""

    target_name = 'c'  # Override in subclasses

    def __init__(self):
        self.indent = 0
        self.enums = set()
        self.double_vars = set()
        self.int_vars = set()
        self.dict_vars = set()
        self.tuple_vars = set()
        self.string_vars = set()
        self.bool_vars = set()
        self.enum_var_types = {}
        self.foundation_dicts = set()
        self.foundation_tuples = set()
        self.T = load_target_config(self.target_name)

    def _is_foundation_collection_access(self, node) -> bool:
        """Check if an IndexAccess is rooted in a Foundation collection."""
        if isinstance(node, IndexAccess):
            if isinstance(node.array, VarRef):
                return node.array.name in self.foundation_dicts or node.array.name in self.foundation_tuples
            if isinstance(node.array, IndexAccess):
                return self._is_foundation_collection_access(node.array)
        return False

    def get_target_type(self, jj_type: str) -> str:
        if jj_type == 'String':
            return self.T.get('expandStringType', self.T.get('stringType', 'const char*'))
        types = self.T.get('types', {})
        return types.get(jj_type, 'int')

    def is_float_expr(self, node) -> bool:
        if isinstance(node, Literal):
            return isinstance(node.value, float)
        if isinstance(node, VarRef):
            return node.name in self.double_vars
        if isinstance(node, BinaryOp):
            return self.is_float_expr(node.left) or self.is_float_expr(node.right)
        if isinstance(node, UnaryOp):
            return self.is_float_expr(node.operand)
        return False

    def transpile(self, program: Program) -> str:
        lines = [self.T['header'].rstrip(), '']

        # Forward declarations
        funcs = [s for s in program.statements if isinstance(s, FuncDef)]
        for f in funcs:
            param_type = self.get_target_type('Int')
            params = ', '.join(f'{param_type} {p}' for p in f.params)
            return_type = self.get_target_type('Int')
            lines.append(self.T['funcDecl'].replace('{type}', return_type).replace('{name}', f.name).replace('{params}', params))
        if funcs:
            lines.append('')

        # Function definitions
        for f in funcs:
            lines.append(self.stmt(f))
            lines.append('')

        # Main
        self._emit_main(lines, program)
        return '\n'.join(lines)

    def _emit_main(self, lines, program):
        """Emit main function. Override for ObjC @autoreleasepool."""
        main_stmts = [s for s in program.statements if not isinstance(s, FuncDef)]
        if main_stmts:
            main_tmpl = self.T.get('main')
            if main_tmpl:
                self.indent = 1
                body_lines = [self.stmt(s) for s in main_stmts]
                body = '\n'.join(body_lines) + '\n'
                expanded = main_tmpl.replace('\\n', '\n').replace('{body}', body)
                lines.append(expanded)
            else:
                lines.append('int main() {')
                self.indent = 1
                for s in main_stmts:
                    lines.append(self.stmt(s))
                lines.append(f"{self.T['indent']}return 0;")
                lines.append('}')

    def ind(self) -> str:
        return self.T['indent'] * self.indent

    def stmt(self, node: ASTNode) -> str:
        if isinstance(node, PrintStmt):
            return self._print_stmt(node)
        elif isinstance(node, LogStmt):
            return self._log_stmt(node)
        elif isinstance(node, VarDecl):
            return self._var_decl(node)
        elif isinstance(node, LoopStmt):
            if node.start is not None:
                header = self.ind() + self.T['forRange'].replace('{var}', node.var).replace('{start}', self.expr(node.start)).replace('{end}', self.expr(node.end))
            else:
                header = self.ind() + self.T['while'].replace('{condition}', self.expr(node.condition))
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body)
            self.indent -= 1
            return f"{header}\n{body}\n{self.ind()}{self.T['blockEnd']}"
        elif isinstance(node, IfStmt):
            header = self.ind() + self.T['if'].replace('{condition}', self.expr(node.condition))
            self.indent += 1
            then = '\n'.join(self.stmt(s) for s in node.then_body)
            self.indent -= 1
            result = f"{header}\n{then}\n{self.ind()}{self.T['blockEnd']}"
            if node.else_body:
                result = result[:-len(self.T['blockEnd'])] + self.T['else']
                self.indent += 1
                result += '\n' + '\n'.join(self.stmt(s) for s in node.else_body)
                self.indent -= 1
                result += f"\n{self.ind()}{self.T['blockEnd']}"
            return result
        elif isinstance(node, TryStmt):
            header = self.ind() + self.T['try']
            self.indent += 1
            try_body = '\n'.join(self.stmt(s) for s in node.try_body)
            self.indent -= 1
            result = f"{header}\n{try_body}\n{self.ind()}{self.T['blockEnd']}"
            if node.oops_body:
                catch_tmpl = self.T['catch']
                if node.oops_var and 'catchVar' in self.T:
                    catch_tmpl = self.T['catchVar'].replace('{var}', node.oops_var)
                # Handle multi-line catch templates (e.g. Go's "}()\ndefer func() {")
                catch_lines = catch_tmpl.split('\n')
                indented_catch = '\n'.join(
                    line if i == 0 else self.ind() + line
                    for i, line in enumerate(catch_lines)
                )
                result = result[:-len(self.T['blockEnd'])] + indented_catch
                self.indent += 1
                if node.oops_var and 'catchVarBind' in self.T:
                    result += '\n' + self.ind() + self.T['catchVarBind'].replace('{var}', node.oops_var)
                result += '\n' + '\n'.join(self.stmt(s) for s in node.oops_body)
                self.indent -= 1
                end_block = self.T.get('blockEndTry', self.T['blockEnd'])
                result += f"\n{self.ind()}{end_block}"
            return result
        elif isinstance(node, FuncDef):
            param_type = self.get_target_type('Int')
            params = ', '.join(f'{param_type} {p}' for p in node.params)
            return_type = self.get_target_type('Int')
            header = self.T['func'].replace('{type}', return_type).replace('{name}', node.name).replace('{params}', params)
            self.indent = 1
            body = '\n'.join(self.stmt(s) for s in node.body)
            self.indent = 0
            return f"{header}\n{body}\n{self.T['blockEnd']}"
        elif isinstance(node, ReturnStmt):
            return self.ind() + self.T['return'].replace('{value}', self.expr(node.value))
        elif isinstance(node, ThrowStmt):
            tmpl = self.T.get('throw')
            if tmpl:
                return self.ind() + tmpl.replace('{value}', self.expr(node.value))
            return self.ind() + self.T.get('comment', '//') + ' throw ' + self.expr(node.value)
        elif isinstance(node, EnumDef):
            return self._enum_def(node)
        return ""

    def _interp_format_specifier(self, name: str) -> str:
        if name in self.double_vars: return self.T.get('doubleFmt', '%g')
        if name in self.string_vars: return self.T.get('strFmt', '%s')
        if name in self.bool_vars: return self.T.get('boolFmt', '%s')
        if name in self.enum_var_types: return self.T.get('strFmt', '%s')
        return self.T.get('intFmt', '%d')

    def _interp_var_expr(self, name: str) -> str:
        if name in self.enum_var_types:
            return f'{self.enum_var_types[name]}_names[{name}]'
        if name in self.bool_vars:
            return f'{name} ? "true" : "false"'
        return name

    def _print_stmt(self, node: PrintStmt) -> str:
        """Print statement. Override for different print mechanisms."""
        expr_node = node.expr
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
            tmpl = self.T.get('printfInterp', 'printf("{fmt}\\n"{args});')
            return self.ind() + tmpl.replace('{fmt}', fmt).replace('{args}', arg_str)
        if isinstance(expr_node, Literal) and isinstance(expr_node.value, str):
            return self.ind() + self.T['printStr'].replace('{expr}', self.expr(expr_node))
        if isinstance(expr_node, VarRef):
            if expr_node.name in self.enums:
                return self._print_enum_type(expr_node.name)
            if expr_node.name in self.double_vars:
                return self.ind() + self.T['printFloat'].replace('{expr}', self.expr(expr_node))
            if expr_node.name in self.string_vars:
                return self.ind() + self.T['printStr'].replace('{expr}', self.expr(expr_node))
            if expr_node.name in self.bool_vars:
                return self.ind() + self.T.get('printBool', self.T.get('printInt', '')).replace('{expr}', self.expr(expr_node))
        if isinstance(expr_node, IndexAccess):
            if isinstance(expr_node.array, VarRef) and expr_node.array.name in self.enums:
                return self._print_enum_value(expr_node)
        if self.is_float_expr(expr_node):
            return self.ind() + self.T['printFloat'].replace('{expr}', self.expr(expr_node))
        return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))

    def _log_stmt(self, node: LogStmt) -> str:
        """Log statement. Override for different log mechanisms."""
        expr_node = node.expr
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
            tmpl = self.T.get('logfInterp', '')
            if tmpl:
                return self.ind() + tmpl.replace('{fmt}', fmt).replace('{args}', arg_str)
            return self.ind() + self.T.get('logInt', '').replace('{expr}', self.expr(expr_node))
        if isinstance(expr_node, Literal) and isinstance(expr_node.value, str):
            return self.ind() + self.T.get('logStr', '').replace('{expr}', self.expr(expr_node))
        if isinstance(expr_node, VarRef):
            if expr_node.name in self.double_vars:
                return self.ind() + self.T.get('logFloat', '').replace('{expr}', self.expr(expr_node))
            if expr_node.name in self.string_vars:
                return self.ind() + self.T.get('logStr', '').replace('{expr}', self.expr(expr_node))
            if expr_node.name in self.bool_vars:
                return self.ind() + self.T.get('logBool', self.T.get('logInt', '')).replace('{expr}', self.expr(expr_node))
        if self.is_float_expr(expr_node):
            return self.ind() + self.T.get('logFloat', '').replace('{expr}', self.expr(expr_node))
        return self.ind() + self.T.get('logInt', '').replace('{expr}', self.expr(expr_node))

    def _print_enum_type(self, name: str) -> str:
        """Print an enum type name. Override per target."""
        sfmt = self.T.get('strFmt', '%s')
        tmpl = self.T.get('printfInterp', 'printf("{fmt}\\n"{args});')
        return self.ind() + tmpl.replace('{fmt}', sfmt).replace('{args}', f', "enum {name}"')

    def _print_enum_value(self, expr_node) -> str:
        """Print an enum value. Override per target."""
        return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))

    def _var_decl(self, node: VarDecl) -> str:
        """Variable declaration. Override for different array/dict handling."""
        if isinstance(node.value, ArrayLiteral):
            return self._var_array(node)
        if isinstance(node.value, TupleLiteral):
            self.tuple_vars.add(node.name)
            return self._var_tuple(node)
        if isinstance(node.value, DictLiteral):
            self.dict_vars.add(node.name)
            return self._var_dict(node)
        inferred = infer_type(node.value)
        if inferred == 'Bool':
            self.bool_vars.add(node.name)
        elif inferred == 'Int':
            self.int_vars.add(node.name)
        elif inferred == 'Double':
            self.double_vars.add(node.name)
        elif inferred == 'String':
            self.string_vars.add(node.name)
        var_type = self.get_target_type(inferred)
        return self.ind() + self.T['var'].replace('{type}', var_type).replace('{name}', node.name).replace('{value}', self.expr(node.value))

    def _var_array(self, node: VarDecl) -> str:
        """Array variable declaration. Override per target."""
        if node.value.elements:
            first = node.value.elements[0]
            if isinstance(first, ArrayLiteral):
                inner_type = self.get_target_type(infer_type(first.elements[0])) if first.elements else 'int'
                inner_size = len(first.elements)
                outer_size = len(node.value.elements)
                elements = ', '.join(self.expr(e) for e in node.value.elements)
                return self.ind() + f"{inner_type} {node.name}[{outer_size}][{inner_size}] = {{{elements}}};"
            if isinstance(first, Literal) and isinstance(first.value, str):
                elem_type = 'const char*'
            else:
                elem_type = self.get_target_type(infer_type(first))
            elements = ', '.join(self.expr(e) for e in node.value.elements)
            return self.ind() + f"{elem_type} {node.name}[] = {{{elements}}};"
        return self.ind() + f"int {node.name}[] = {{}};"

    def _var_tuple(self, node: VarDecl) -> str:
        """Tuple variable declaration. Override per target."""
        if node.value.elements:
            first = node.value.elements[0]
            if isinstance(first, Literal) and isinstance(first.value, str):
                elem_type = 'const char*'
            else:
                elem_type = self.get_target_type(infer_type(first))
            elements = ', '.join(self.expr(e) for e in node.value.elements)
            return self.ind() + f"{elem_type} {node.name}[] = {{{elements}}};"
        return self.ind() + f"int {node.name}[] = {{}};"

    def _var_dict(self, node: VarDecl) -> str:
        """Dict variable declaration. Override per target."""
        return self.ind() + f"// dict {node.name} not supported in C"

    def _enum_def(self, node: EnumDef) -> str:
        """Enum definition. Override per target."""
        self.enums.add(node.name)
        cases = ', '.join(node.cases)
        tmpl = self.T.get('enum', 'enum {name} { {cases} };')
        return self.ind() + tmpl.replace('{name}', node.name).replace('{cases}', cases)

    def expr(self, node: ASTNode) -> str:
        if isinstance(node, StringInterpolation):
            fmt = ''
            args = []
            for kind, text in node.parts:
                if kind == 'literal':
                    fmt += text
                else:
                    fmt += self._interp_format_specifier(text)
                    args.append(self._interp_var_expr(text))
            if not args:
                return f'"{fmt}"'
            return f'/* sprintf: */ "{fmt}"'
        if isinstance(node, Literal):
            if isinstance(node.value, str):
                return f'"{node.value}"'
            elif node.value is None:
                return self.T['nil']
            elif isinstance(node.value, bool):
                return self.T['true'] if node.value else self.T['false']
            elif isinstance(node.value, float):
                return str(node.value)
            return str(int(node.value))
        elif isinstance(node, VarRef):
            return node.name
        elif isinstance(node, ArrayLiteral):
            return self._expr_array(node)
        elif isinstance(node, DictLiteral):
            return self._expr_dict(node)
        elif isinstance(node, TupleLiteral):
            return self._expr_tuple(node)
        elif isinstance(node, IndexAccess):
            if isinstance(node.array, VarRef) and node.array.name in self.enums:
                if isinstance(node.index, Literal) and isinstance(node.index.value, str):
                    return self.T.get('enumAccess', '{key}').replace('{name}', node.array.name).replace('{key}', node.index.value)
            return f"{self.expr(node.array)}[{self.expr(node.index)}]"
        elif isinstance(node, BinaryOp):
            if node.op == '%' and (self.is_float_expr(node.left) or self.is_float_expr(node.right)):
                fm = self.T.get('floatMod', 'fmod({left}, {right})')
                return fm.replace('{left}', self.expr(node.left)).replace('{right}', self.expr(node.right))
            return f"({self.expr(node.left)} {node.op} {self.expr(node.right)})"
        elif isinstance(node, UnaryOp):
            return f"({node.op}{self.expr(node.operand)})"
        elif isinstance(node, FuncCall):
            return self.T['call'].replace('{name}', node.name).replace('{args}', ', '.join(self.expr(a) for a in node.args))
        elif isinstance(node, MethodCallExpr):
            s = self.expr(node.args[0]) if node.args else '""'
            if node.method == 'upper': return f'_jj_upper({s})'
            if node.method == 'lower': return f'_jj_lower({s})'
            if node.method == 'length': return f'(int)strlen({s})'
            if node.method == 'trim': return f'_jj_trim({s})'
            if node.method == 'contains' and len(node.args) >= 2: return f'(strstr({s}, {self.expr(node.args[1])}) != NULL)'
            if node.method == 'replace' and len(node.args) >= 3: return f'_jj_replace({s}, {self.expr(node.args[1])}, {self.expr(node.args[2])})'
            if node.method == 'split': return f'/* split not supported in C */'
            if node.method == 'substring' and len(node.args) >= 3: return f'_jj_substr({s}, {self.expr(node.args[1])}, {self.expr(node.args[2])})'
        return ""

    def _expr_array(self, node: ArrayLiteral) -> str:
        elements = ', '.join(self.expr(e) for e in node.elements)
        return f"{{{elements}}}"

    def _expr_dict(self, node: DictLiteral) -> str:
        pairs = ', '.join(f"{self.expr(k)}: {self.expr(v)}" for k, v in node.pairs)
        return f"/* dict: {{{pairs}}} */"

    def _expr_tuple(self, node: TupleLiteral) -> str:
        elements = ', '.join(self.expr(e) for e in node.elements)
        return f"{{{elements}}}"
