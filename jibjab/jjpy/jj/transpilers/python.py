"""
JibJab Python Transpiler - Converts JJ to Python
Uses shared config from common/jj.json
"""

from ..lexer import JJ
from ..ast import (
    ASTNode, Program, PrintStmt, InputExpr, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt
)

# Get target config
T = JJ['targets']['py']


class PythonTranspiler:
    def __init__(self):
        self.indent = 0

    def transpile(self, program: Program) -> str:
        lines = [T['header'].rstrip()]
        for stmt in program.statements:
            lines.append(self.stmt(stmt))
        return '\n'.join(lines)

    def ind(self) -> str:
        return T['indent'] * self.indent

    def stmt(self, node: ASTNode) -> str:
        if isinstance(node, PrintStmt):
            return self.ind() + T['print'].format(expr=self.expr(node.expr))
        elif isinstance(node, VarDecl):
            return self.ind() + T['var'].format(name=node.name, value=self.expr(node.value))
        elif isinstance(node, LoopStmt):
            if node.start is not None:
                header = self.ind() + T['forRange'].format(
                    var=node.var, start=self.expr(node.start), end=self.expr(node.end))
            elif node.collection:
                header = self.ind() + T['forIn'].format(
                    var=node.var, collection=self.expr(node.collection))
            else:
                header = self.ind() + T['while'].format(condition=self.expr(node.condition))
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body) or f"{self.ind()}pass"
            self.indent -= 1
            return f"{header}\n{body}"
        elif isinstance(node, IfStmt):
            header = self.ind() + T['if'].format(condition=self.expr(node.condition))
            self.indent += 1
            then = '\n'.join(self.stmt(s) for s in node.then_body) or f"{self.ind()}pass"
            self.indent -= 1
            result = f"{header}\n{then}"
            if node.else_body:
                result += f"\n{self.ind()}{T['else']}"
                self.indent += 1
                result += '\n' + '\n'.join(self.stmt(s) for s in node.else_body)
                self.indent -= 1
            return result
        elif isinstance(node, FuncDef):
            header = self.ind() + T['func'].format(name=node.name, params=', '.join(node.params))
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body) or f"{self.ind()}pass"
            self.indent -= 1
            return f"{header}\n{body}"
        elif isinstance(node, ReturnStmt):
            return self.ind() + T['return'].format(value=self.expr(node.value))
        return ""

    def expr(self, node: ASTNode) -> str:
        if isinstance(node, Literal):
            if isinstance(node.value, str):
                return repr(node.value)
            elif node.value is None:
                return T['nil']
            elif isinstance(node.value, bool):
                return T['true'] if node.value else T['false']
            return str(node.value)
        elif isinstance(node, VarRef):
            return node.name
        elif isinstance(node, BinaryOp):
            op = node.op
            if op == '&&': op = T['and']
            if op == '||': op = T['or']
            return f"({self.expr(node.left)} {op} {self.expr(node.right)})"
        elif isinstance(node, UnaryOp):
            op = T['not'] if node.op == '!' else node.op
            return f"({op}{self.expr(node.operand)})"
        elif isinstance(node, InputExpr):
            return f"input({self.expr(node.prompt)})"
        elif isinstance(node, FuncCall):
            return T['call'].format(name=node.name, args=', '.join(self.expr(a) for a in node.args))
        return ""
