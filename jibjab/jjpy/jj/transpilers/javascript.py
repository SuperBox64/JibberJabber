"""
JibJab JavaScript Transpiler - Converts JJ to JavaScript
Uses shared config from common/jj.json
"""

from ..lexer import JJ, load_target_config
from ..ast import (
    ASTNode, Program, PrintStmt, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt,
    ArrayLiteral, DictLiteral, TupleLiteral, IndexAccess, EnumDef,
    StringInterpolation
)

# Get target config and operators
T = load_target_config('js')
OP = JJ['operators']


class JavaScriptTranspiler:
    def __init__(self):
        self.indent = 0
        self.bool_vars = set()

    def transpile(self, program: Program) -> str:
        lines = [T['header'].rstrip()]
        for stmt in program.statements:
            lines.append(self.stmt(stmt))
        return '\n'.join(lines)

    def ind(self) -> str:
        return T['indent'] * self.indent

    def stmt(self, node: ASTNode) -> str:
        if isinstance(node, PrintStmt):
            if isinstance(node.expr, VarRef) and node.expr.name in self.bool_vars:
                return self.ind() + T.get('printBool', T['print']).replace('{expr}', self.expr(node.expr))
            return self.ind() + T['print'].replace('{expr}', self.expr(node.expr))
        elif isinstance(node, VarDecl):
            if isinstance(node.value, Literal) and isinstance(node.value.value, bool):
                self.bool_vars.add(node.name)
            return self.ind() + T['var'].replace('{name}', node.name).replace('{value}', self.expr(node.value))
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
        elif isinstance(node, FuncDef):
            header = self.ind() + T['func'].replace('{name}', node.name).replace('{params}', ', '.join(node.params))
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body)
            self.indent -= 1
            return f"{header}\n{body}\n{self.ind()}{T['blockEnd']}"
        elif isinstance(node, ReturnStmt):
            return self.ind() + T['return'].replace('{value}', self.expr(node.value))
        elif isinstance(node, EnumDef):
            cases = ', '.join(f"{c}: '{c}'" for c in node.cases)
            tmpl = T.get('enum', 'const {name} = { {cases} };')
            return self.ind() + tmpl.replace('{name}', node.name).replace('{cases}', cases)
        return ""

    def expr(self, node: ASTNode) -> str:
        if isinstance(node, StringInterpolation):
            open_delim = T.get('interpOpen', '`')
            close_delim = T.get('interpClose', '`')
            var_open = T.get('interpVarOpen', '${')
            var_close = T.get('interpVarClose', '}')
            result = open_delim
            for kind, text in node.parts:
                if kind == 'literal':
                    result += text.replace('`', '\\`')
                else:
                    result += f'{var_open}{text}{var_close}'
            return result + close_delim
        if isinstance(node, Literal):
            if isinstance(node.value, str):
                return repr(node.value).replace("'", '"')
            elif node.value is None:
                return T['nil']
            elif isinstance(node.value, bool):
                return T['true'] if node.value else T['false']
            return str(node.value)
        elif isinstance(node, VarRef):
            return node.name
        elif isinstance(node, ArrayLiteral):
            elements = ', '.join(self.expr(e) for e in node.elements)
            return f"[{elements}]"
        elif isinstance(node, DictLiteral):
            pairs = ', '.join(f"{self.expr(k)}: {self.expr(v)}" for k, v in node.pairs)
            return "{" + pairs + "}"
        elif isinstance(node, TupleLiteral):
            # JavaScript doesn't have tuples, use arrays
            elements = ', '.join(self.expr(e) for e in node.elements)
            return f"[{elements}]"
        elif isinstance(node, IndexAccess):
            return f"{self.expr(node.array)}[{self.expr(node.index)}]"
        elif isinstance(node, BinaryOp):
            op = node.op
            if op == OP['eq']['emit']: op = T.get('eq', '===')
            if op == OP['neq']['emit']: op = T.get('neq', '!==')
            return f"({self.expr(node.left)} {op} {self.expr(node.right)})"
        elif isinstance(node, UnaryOp):
            return f"({node.op}{self.expr(node.operand)})"
        elif isinstance(node, FuncCall):
            return T['call'].replace('{name}', node.name).replace('{args}', ', '.join(self.expr(a) for a in node.args))
        return ""
