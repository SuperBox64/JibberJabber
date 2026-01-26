"""
JibJab AppleScript Transpiler - Converts JJ to AppleScript
Uses shared config from common/jj.json
"""

from ..lexer import JJ, load_target_config
from ..ast import (
    ASTNode, Program, PrintStmt, InputExpr, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt
)

# Get target config and operators
T = load_target_config('applescript')
OP = JJ['operators']


class AppleScriptTranspiler:
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
            body = '\n'.join(self.stmt(s) for s in node.body)
            self.indent -= 1
            return f"{header}\n{body}\n{self.ind()}end repeat"
        elif isinstance(node, IfStmt):
            header = self.ind() + T['if'].replace('{condition}', self.expr(node.condition))
            self.indent += 1
            then = '\n'.join(self.stmt(s) for s in node.then_body)
            self.indent -= 1
            result = f"{header}\n{then}"
            if node.else_body:
                result += f"\n{self.ind()}{T['else']}"
                self.indent += 1
                result += '\n' + '\n'.join(self.stmt(s) for s in node.else_body)
                self.indent -= 1
            result += f"\n{self.ind()}end if"
            return result
        elif isinstance(node, FuncDef):
            header = self.ind() + T['func'].replace('{name}', node.name).replace('{params}', ', '.join(node.params))
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body)
            self.indent -= 1
            return f"{header}\n{body}\n{self.ind()}end {node.name}"
        elif isinstance(node, ReturnStmt):
            return self.ind() + T['return'].replace('{value}', self.expr(node.value))
        return ""

    def expr(self, node: ASTNode) -> str:
        if isinstance(node, Literal):
            if isinstance(node.value, str):
                return f'"{node.value}"'
            elif node.value is None:
                return T['nil']
            elif isinstance(node.value, bool):
                return T['true'] if node.value else T['false']
            return str(node.value)
        elif isinstance(node, VarRef):
            return node.name
        elif isinstance(node, BinaryOp):
            op = node.op
            # Map operators to AppleScript equivalents
            if op == OP['and']['emit'] or op == '&&':
                op = T['and']
            elif op == OP['or']['emit'] or op == '||':
                op = T['or']
            elif op == '==' or op == OP['eq']['emit']:
                op = T['eq']
            elif op == '!=' or op == OP['neq']['emit']:
                op = T['neq']
            elif op == '%' or op == OP['mod']['emit']:
                op = T['mod']
            return f"({self.expr(node.left)} {op} {self.expr(node.right)})"
        elif isinstance(node, UnaryOp):
            op = T['not'] if node.op == OP['not']['emit'] or node.op == '!' else node.op
            return f"({op}{self.expr(node.operand)})"
        elif isinstance(node, InputExpr):
            # AppleScript uses display dialog for input
            return f'text returned of (display dialog {self.expr(node.prompt)} default answer "")'
        elif isinstance(node, FuncCall):
            args = ', '.join(self.expr(a) for a in node.args)
            return f"{node.name}({args})"
        return ""
