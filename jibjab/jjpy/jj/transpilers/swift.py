"""
JibJab Swift Transpiler - Converts JJ to Swift
Uses shared config from common/jj.json
"""

from ..lexer import JJ, load_target_config
from ..ast import (
    ASTNode, Program, PrintStmt, LogStmt, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, TryStmt, FuncDef, FuncCall,
    ReturnStmt, ThrowStmt, EnumDef, IndexAccess, ArrayLiteral, DictLiteral,
    TupleLiteral, StringInterpolation
)

# Get target config and operators
T = load_target_config('swift')
OP = JJ['operators']


class SwiftTranspiler:
    def __init__(self):
        self.indent = 0
        self.enums = set()
        self.double_vars = set()
        self.dict_vars = set()
        self.tuple_vars = set()
        self.bool_vars = set()

    def is_float_expr(self, node) -> bool:
        """Check if expression involves floating-point values"""
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
        lines = [T['header'].rstrip()]
        if self._needs_error_struct(program.statements) and T.get('errorStruct'):
            lines.append('')
            lines.append(T['errorStruct'])
        for stmt in program.statements:
            lines.append(self.stmt(stmt))
        return '\n'.join(lines)

    def _needs_error_struct(self, stmts) -> bool:
        for s in stmts:
            if isinstance(s, ThrowStmt) or isinstance(s, TryStmt):
                return True
            if isinstance(s, IfStmt):
                if self._needs_error_struct(s.then_body):
                    return True
                if s.else_body and self._needs_error_struct(s.else_body):
                    return True
            if isinstance(s, LoopStmt) and self._needs_error_struct(s.body):
                return True
            if isinstance(s, FuncDef) and self._needs_error_struct(s.body):
                return True
            if isinstance(s, TryStmt):
                if self._needs_error_struct(s.try_body):
                    return True
                if s.oops_body and self._needs_error_struct(s.oops_body):
                    return True
        return False

    def ind(self) -> str:
        return T['indent'] * self.indent

    def stmt(self, node: ASTNode) -> str:
        if isinstance(node, PrintStmt):
            if isinstance(node.expr, VarRef) and node.expr.name in self.bool_vars:
                return self.ind() + T.get('printBool', T['print']).replace('{expr}', self.expr(node.expr))
            return self.ind() + T['print'].replace('{expr}', self.expr(node.expr))
        elif isinstance(node, LogStmt):
            return self.ind() + T['log'].replace('{expr}', self.expr(node.expr))
        elif isinstance(node, VarDecl):
            # Track bool variables
            if isinstance(node.value, Literal) and isinstance(node.value.value, bool):
                self.bool_vars.add(node.name)
            # Track double variables
            if isinstance(node.value, Literal) and isinstance(node.value.value, float):
                self.double_vars.add(node.name)
            # Dict declaration
            if isinstance(node.value, DictLiteral):
                self.dict_vars.add(node.name)
                value = T.get('dictEmpty', '[:]') if not node.value.pairs else self.expr(node.value)
                tmpl = T.get('varDict', T['var'])
                return self.ind() + tmpl.replace('{name}', node.name).replace('{value}', value).replace('{type}', '')
            # Tuple declaration
            if isinstance(node.value, TupleLiteral):
                self.tuple_vars.add(node.name)
                template = T.get('varInfer', T['var'])
                return self.ind() + template.replace('{name}', node.name).replace('{value}', self.expr(node.value))
            template = T.get('varInfer', T['var'])
            return self.ind() + template.replace('{name}', node.name).replace('{value}', self.expr(node.value))
        elif isinstance(node, LoopStmt):
            if node.start is not None:
                header = self.ind() + T['forRange'].replace('{var}', node.var).replace('{start}', self.expr(node.start)).replace('{end}', self.expr(node.end))
            elif node.collection:
                header = self.ind() + T['forIn'].replace('{var}', node.var).replace('{collection}', self.expr(node.collection))
            else:
                header = self.ind() + T['while'].replace('{condition}', self.expr(node.condition))
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body)
            self.indent -= 1
            return f"{header}\n{body}\n{self.ind()}{T['blockEnd']}"
        elif isinstance(node, IfStmt):
            header = self.ind() + T['if'].replace('{condition}', self.expr(node.condition))
            self.indent += 1
            then = '\n'.join(self.stmt(s) for s in node.then_body)
            self.indent -= 1
            result = f"{header}\n{then}\n{self.ind()}{T['blockEnd']}"
            if node.else_body:
                result = result[:-len(T['blockEnd'])] + T['else']
                self.indent += 1
                result += '\n' + '\n'.join(self.stmt(s) for s in node.else_body)
                self.indent -= 1
                result += f"\n{self.ind()}{T['blockEnd']}"
            return result
        elif isinstance(node, TryStmt):
            header = self.ind() + T['try']
            self.indent += 1
            try_body = '\n'.join(self.stmt(s) for s in node.try_body)
            self.indent -= 1
            result = f"{header}\n{try_body}\n{self.ind()}{T['blockEnd']}"
            if node.oops_body:
                catch_tmpl = T['catch']
                if node.oops_var and 'catchVar' in T:
                    catch_tmpl = T['catchVar'].replace('{var}', node.oops_var)
                result = result[:-len(T['blockEnd'])] + catch_tmpl
                self.indent += 1
                if node.oops_var and 'catchVarBind' in T:
                    result += '\n' + self.ind() + T['catchVarBind'].replace('{var}', node.oops_var)
                result += '\n' + '\n'.join(self.stmt(s) for s in node.oops_body)
                self.indent -= 1
                result += f"\n{self.ind()}{T['blockEnd']}"
            return result
        elif isinstance(node, FuncDef):
            param_fmt = T.get('paramFormat', '{name}: {type}')
            param_type = T.get('types', {}).get('Int', 'Int')
            typed_params = ', '.join(param_fmt.replace('{name}', p).replace('{type}', param_type) for p in node.params)
            header = self.ind() + T['func'].replace('{name}', node.name).replace('{params}', typed_params)
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body)
            self.indent -= 1
            return f"{header}\n{body}\n{self.ind()}{T['blockEnd']}"
        elif isinstance(node, ReturnStmt):
            return self.ind() + T['return'].replace('{value}', self.expr(node.value))
        elif isinstance(node, ThrowStmt):
            tmpl = T.get('throw')
            if tmpl:
                return self.ind() + tmpl.replace('{value}', self.expr(node.value))
            return self.ind() + T.get('comment', '//') + ' throw ' + self.expr(node.value)
        elif isinstance(node, EnumDef):
            self.enums.add(node.name)
            cases = ', '.join(node.cases)
            tmpl = T.get('enum', 'enum {name} { case {cases} }')
            return self.ind() + tmpl.replace('{name}', node.name).replace('{cases}', cases)
        return ""

    def expr(self, node: ASTNode) -> str:
        if isinstance(node, StringInterpolation):
            open_delim = T.get('interpOpen', '"')
            close_delim = T.get('interpClose', '"')
            var_open = T.get('interpVarOpen', '\\(')
            var_close = T.get('interpVarClose', ')')
            result = open_delim
            for kind, text in node.parts:
                if kind == 'literal':
                    result += text.replace('\\', '\\\\').replace('"', '\\"')
                else:
                    result += f'{var_open}{text}{var_close}'
            return result + close_delim
        if isinstance(node, Literal):
            if isinstance(node.value, str):
                # Swift uses double quotes for strings
                escaped = node.value.replace('\\', '\\\\').replace('"', '\\"')
                return f'"{escaped}"'
            elif node.value is None:
                return T['nil']
            elif isinstance(node.value, bool):
                return T['true'] if node.value else T['false']
            elif isinstance(node.value, float):
                return str(node.value)
            elif isinstance(node.value, int):
                return str(node.value)
            return str(node.value)
        elif isinstance(node, VarRef):
            # If referencing an enum type directly
            if node.name in self.enums:
                return T.get('enumSelf', '{name}.self').replace('{name}', node.name)
            return node.name
        elif isinstance(node, IndexAccess):
            # Check if this is enum access (e.g., Color["Red"] -> Color.Red)
            if isinstance(node.array, VarRef) and node.array.name in self.enums:
                if isinstance(node.index, Literal) and isinstance(node.index.value, str):
                    return T.get('enumAccess', '{name}.{key}').replace('{name}', node.array.name).replace('{key}', node.index.value)
            # Tuple access: use .N dot syntax instead of [N]
            if isinstance(node.array, VarRef) and node.array.name in self.tuple_vars:
                if isinstance(node.index, Literal) and isinstance(node.index.value, int):
                    return f"{node.array.name}.{node.index.value}"
            # Nested dict access (e.g., data["items"][0]) - must come before simple dict access
            if isinstance(node.array, IndexAccess):
                if isinstance(node.array.array, VarRef) and node.array.array.name in self.dict_vars:
                    # Access raw dict value and safely cast to array
                    dict_name = node.array.array.name
                    key = self.expr(node.array.index)
                    idx = self.expr(node.index)
                    return f"({dict_name}[{key}] as? [Any] ?? [])[{idx}]"
                inner = self.expr(node.array)
                idx = self.expr(node.index)
                return f"{inner}[{idx}]"
            # Dict access: use nil coalescing instead of force unwrap
            if isinstance(node.array, VarRef) and node.array.name in self.dict_vars:
                return f'{self.expr(node.array)}[{self.expr(node.index)}] as Any? ?? ""'
            return f"{self.expr(node.array)}[{self.expr(node.index)}]"
        elif isinstance(node, ArrayLiteral):
            elements = ', '.join(self.expr(e) for e in node.elements)
            return f"[{elements}]"
        elif isinstance(node, DictLiteral):
            if not node.pairs:
                return T.get('dictEmpty', '[:]')
            pairs = ', '.join(f"{self.expr(k)}: {self.expr(v)}" for k, v in node.pairs)
            return f"[{pairs}]"
        elif isinstance(node, TupleLiteral):
            if not node.elements:
                return "()"
            if len(node.elements) == 1:
                return f"({self.expr(node.elements[0])},)"
            elements = ', '.join(self.expr(e) for e in node.elements)
            return f"({elements})"
        elif isinstance(node, BinaryOp):
            # Float modulo
            if node.op == '%' and (self.is_float_expr(node.left) or self.is_float_expr(node.right)):
                fm = T.get('floatMod')
                if fm:
                    return fm.replace('{left}', self.expr(node.left)).replace('{right}', self.expr(node.right))
            return f"({self.expr(node.left)} {node.op} {self.expr(node.right)})"
        elif isinstance(node, UnaryOp):
            return f"({node.op}{self.expr(node.operand)})"
        elif isinstance(node, FuncCall):
            return T['call'].replace('{name}', node.name).replace('{args}', ', '.join(self.expr(a) for a in node.args))
        return ""
