"""
JibJab Python Transpiler - Converts JJ to Python
"""

from ..ast import (
    ASTNode, Program, PrintStmt, InputExpr, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt
)


class PythonTranspiler:
    def __init__(self):
        self.indent = 0

    def transpile(self, program: Program) -> str:
        lines = ['#!/usr/bin/env python3', '# Transpiled from JibJab', '']
        for stmt in program.statements:
            lines.append(self.stmt(stmt))
        return '\n'.join(lines)

    def ind(self) -> str:
        return '    ' * self.indent

    def stmt(self, node: ASTNode) -> str:
        if isinstance(node, PrintStmt):
            return f"{self.ind()}print({self.expr(node.expr)})"
        elif isinstance(node, VarDecl):
            return f"{self.ind()}{node.name} = {self.expr(node.value)}"
        elif isinstance(node, LoopStmt):
            if node.start is not None:
                header = f"{self.ind()}for {node.var} in range({self.expr(node.start)}, {self.expr(node.end)}):"
            elif node.collection:
                header = f"{self.ind()}for {node.var} in {self.expr(node.collection)}:"
            else:
                header = f"{self.ind()}while {self.expr(node.condition)}:"
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body) or f"{self.ind()}pass"
            self.indent -= 1
            return f"{header}\n{body}"
        elif isinstance(node, IfStmt):
            header = f"{self.ind()}if {self.expr(node.condition)}:"
            self.indent += 1
            then = '\n'.join(self.stmt(s) for s in node.then_body) or f"{self.ind()}pass"
            self.indent -= 1
            result = f"{header}\n{then}"
            if node.else_body:
                result += f"\n{self.ind()}else:"
                self.indent += 1
                result += '\n' + '\n'.join(self.stmt(s) for s in node.else_body)
                self.indent -= 1
            return result
        elif isinstance(node, FuncDef):
            header = f"{self.ind()}def {node.name}({', '.join(node.params)}):"
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body) or f"{self.ind()}pass"
            self.indent -= 1
            return f"{header}\n{body}"
        elif isinstance(node, ReturnStmt):
            return f"{self.ind()}return {self.expr(node.value)}"
        return ""

    def expr(self, node: ASTNode) -> str:
        if isinstance(node, Literal):
            if isinstance(node.value, str):
                return repr(node.value)
            elif node.value is None:
                return 'None'
            elif isinstance(node.value, bool):
                return 'True' if node.value else 'False'
            return str(node.value)
        elif isinstance(node, VarRef):
            return node.name
        elif isinstance(node, BinaryOp):
            op = node.op
            if op == '&&': op = 'and'
            if op == '||': op = 'or'
            return f"({self.expr(node.left)} {op} {self.expr(node.right)})"
        elif isinstance(node, UnaryOp):
            op = 'not ' if node.op == '!' else node.op
            return f"({op}{self.expr(node.operand)})"
        elif isinstance(node, InputExpr):
            return f"input({self.expr(node.prompt)})"
        elif isinstance(node, FuncCall):
            args = ', '.join(self.expr(a) for a in node.args)
            return f"{node.name}({args})"
        return ""
