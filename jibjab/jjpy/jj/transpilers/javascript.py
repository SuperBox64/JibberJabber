"""
JibJab JavaScript Transpiler - Converts JJ to JavaScript
"""

from ..ast import (
    ASTNode, Program, PrintStmt, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt
)


class JavaScriptTranspiler:
    def __init__(self):
        self.indent = 0

    def transpile(self, program: Program) -> str:
        lines = ['// Transpiled from JibJab', '']
        for stmt in program.statements:
            lines.append(self.stmt(stmt))
        return '\n'.join(lines)

    def ind(self) -> str:
        return '    ' * self.indent

    def stmt(self, node: ASTNode) -> str:
        if isinstance(node, PrintStmt):
            return f"{self.ind()}console.log({self.expr(node.expr)});"
        elif isinstance(node, VarDecl):
            return f"{self.ind()}let {node.name} = {self.expr(node.value)};"
        elif isinstance(node, LoopStmt):
            if node.start is not None:
                header = f"{self.ind()}for (let {node.var} = {self.expr(node.start)}; {node.var} < {self.expr(node.end)}; {node.var}++) {{"
            elif node.collection:
                header = f"{self.ind()}for (const {node.var} of {self.expr(node.collection)}) {{"
            else:
                header = f"{self.ind()}while ({self.expr(node.condition)}) {{"
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body)
            self.indent -= 1
            return f"{header}\n{body}\n{self.ind()}}}"
        elif isinstance(node, IfStmt):
            header = f"{self.ind()}if ({self.expr(node.condition)}) {{"
            self.indent += 1
            then = '\n'.join(self.stmt(s) for s in node.then_body)
            self.indent -= 1
            result = f"{header}\n{then}\n{self.ind()}}}"
            if node.else_body:
                result += f" else {{"
                self.indent += 1
                result += '\n' + '\n'.join(self.stmt(s) for s in node.else_body)
                self.indent -= 1
                result += f"\n{self.ind()}}}"
            return result
        elif isinstance(node, FuncDef):
            header = f"{self.ind()}function {node.name}({', '.join(node.params)}) {{"
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body)
            self.indent -= 1
            return f"{header}\n{body}\n{self.ind()}}}"
        elif isinstance(node, ReturnStmt):
            return f"{self.ind()}return {self.expr(node.value)};"
        return ""

    def expr(self, node: ASTNode) -> str:
        if isinstance(node, Literal):
            if isinstance(node.value, str):
                return repr(node.value).replace("'", '"')
            elif node.value is None:
                return 'null'
            elif isinstance(node.value, bool):
                return 'true' if node.value else 'false'
            return str(node.value)
        elif isinstance(node, VarRef):
            return node.name
        elif isinstance(node, BinaryOp):
            op = node.op
            if op == '==': op = '==='
            if op == '!=': op = '!=='
            return f"({self.expr(node.left)} {op} {self.expr(node.right)})"
        elif isinstance(node, UnaryOp):
            return f"({node.op}{self.expr(node.operand)})"
        elif isinstance(node, FuncCall):
            args = ', '.join(self.expr(a) for a in node.args)
            return f"{node.name}({args})"
        return ""
