"""
JibJab Python Transpiler - Converts JJ to Python
Uses shared config from common/jj.json
"""

from ..lexer import JJ
from ..ast import (
    ASTNode, Program, PrintStmt, InputExpr, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt
)

# Get target config and operators
T = JJ['targets']['py']
OP = JJ['operators']


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
            return self.ind() + T['print'].replace('{expr}', self.expr(node.expr))
        elif isinstance(node, VarDecl):
            return self.ind() + T['var'].replace('{name}', node.name).replace('{value}', self.expr(node.value))
        elif isinstance(node, LoopStmt):
            if node.start is not None:
                header = self.ind() + T['forRange'].replace('{var}', node.var).replace('{start}', self.expr(node.start)).replace('{end}', self.expr(node.end))
            elif node.collection:
                header = self.ind() + T['forIn'].replace('{var}', node.var).replace('{collection}', self.expr(node.collection))
            else:
                header = self.ind() + T['while'].replace('{condition}', self.expr(node.condition))
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body) or f"{self.ind()}pass"
            self.indent -= 1
            return f"{header}\n{body}"
        elif isinstance(node, IfStmt):
            header = self.ind() + T['if'].replace('{condition}', self.expr(node.condition))
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
            header = self.ind() + T['func'].replace('{name}', node.name).replace('{params}', ', '.join(node.params))
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body) or f"{self.ind()}pass"
            self.indent -= 1
            return f"{header}\n{body}"
        elif isinstance(node, ReturnStmt):
            return self.ind() + T['return'].replace('{value}', self.expr(node.value))
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
            if op == OP['and']['emit']: op = T['and']
            if op == OP['or']['emit']: op = T['or']
            return f"({self.expr(node.left)} {op} {self.expr(node.right)})"
        elif isinstance(node, UnaryOp):
            op = T['not'] if node.op == OP['not']['emit'] else node.op
            return f"({op}{self.expr(node.operand)})"
        elif isinstance(node, InputExpr):
            return f"input({self.expr(node.prompt)})"
        elif isinstance(node, FuncCall):
            return T['call'].replace('{name}', node.name).replace('{args}', ', '.join(self.expr(a) for a in node.args))
        return ""
