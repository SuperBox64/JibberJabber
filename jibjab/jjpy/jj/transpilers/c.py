"""
JibJab C Transpiler - Converts JJ to C
Uses shared config from common/jj.json
"""

from ..lexer import JJ
from ..ast import (
    ASTNode, Program, PrintStmt, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt
)

# Get target config
T = JJ['targets']['c']


class CTranspiler:
    def __init__(self):
        self.indent = 0

    def transpile(self, program: Program) -> str:
        lines = [T['header'].rstrip(), '']

        # Forward declarations
        funcs = [s for s in program.statements if isinstance(s, FuncDef)]
        for f in funcs:
            params = ', '.join(f'int {p}' for p in f.params)
            lines.append(T['funcDecl'].format(name=f.name, params=params))
        if funcs:
            lines.append('')

        # Function definitions
        for f in funcs:
            lines.append(self.stmt(f))
            lines.append('')

        # Main
        main_stmts = [s for s in program.statements if not isinstance(s, FuncDef)]
        if main_stmts:
            lines.append('int main() {')
            self.indent = 1
            for stmt in main_stmts:
                lines.append(self.stmt(stmt))
            lines.append(f"{T['indent']}return 0;")
            lines.append('}')

        return '\n'.join(lines)

    def ind(self) -> str:
        return T['indent'] * self.indent

    def stmt(self, node: ASTNode) -> str:
        if isinstance(node, PrintStmt):
            expr = node.expr
            if isinstance(expr, Literal) and isinstance(expr.value, str):
                return self.ind() + T['printStr'].format(expr=self.expr(expr))
            return self.ind() + T['printInt'].format(expr=self.expr(expr))
        elif isinstance(node, VarDecl):
            return self.ind() + T['var'].format(name=node.name, value=self.expr(node.value))
        elif isinstance(node, LoopStmt):
            if node.start is not None:
                header = self.ind() + T['forRange'].format(
                    var=node.var, start=self.expr(node.start), end=self.expr(node.end))
            else:
                header = self.ind() + T['while'].format(condition=self.expr(node.condition))
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body)
            self.indent -= 1
            return f"{header}\n{body}\n{self.ind()}{T['blockEnd']}"
        elif isinstance(node, IfStmt):
            header = self.ind() + T['if'].format(condition=self.expr(node.condition))
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
            params = ', '.join(f'int {p}' for p in node.params)
            header = T['func'].format(name=node.name, params=params)
            self.indent = 1
            body = '\n'.join(self.stmt(s) for s in node.body)
            self.indent = 0
            return f"{header}\n{body}\n{T['blockEnd']}"
        elif isinstance(node, ReturnStmt):
            return self.ind() + T['return'].format(value=self.expr(node.value))
        return ""

    def expr(self, node: ASTNode) -> str:
        if isinstance(node, Literal):
            if isinstance(node.value, str):
                return f'"{node.value}"'
            elif node.value is None:
                return T['nil']
            elif isinstance(node.value, bool):
                return T['true'] if node.value else T['false']
            return str(int(node.value))
        elif isinstance(node, VarRef):
            return node.name
        elif isinstance(node, BinaryOp):
            return f"({self.expr(node.left)} {node.op} {self.expr(node.right)})"
        elif isinstance(node, UnaryOp):
            return f"({node.op}{self.expr(node.operand)})"
        elif isinstance(node, FuncCall):
            return T['call'].format(name=node.name, args=', '.join(self.expr(a) for a in node.args))
        return ""
