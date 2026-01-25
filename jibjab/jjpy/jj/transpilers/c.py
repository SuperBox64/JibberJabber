"""
JibJab C Transpiler - Converts JJ to C
"""

from ..ast import (
    ASTNode, Program, PrintStmt, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt
)


class CTranspiler:
    def __init__(self):
        self.indent = 0

    def transpile(self, program: Program) -> str:
        lines = [
            '// Transpiled from JibJab',
            '#include <stdio.h>',
            '#include <stdlib.h>',
            '',
        ]

        # Forward declarations
        funcs = [s for s in program.statements if isinstance(s, FuncDef)]
        for f in funcs:
            lines.append(f"int {f.name}({', '.join(f'int {p}' for p in f.params)});")
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
            lines.append('    return 0;')
            lines.append('}')

        return '\n'.join(lines)

    def ind(self) -> str:
        return '    ' * self.indent

    def stmt(self, node: ASTNode) -> str:
        if isinstance(node, PrintStmt):
            expr = node.expr
            if isinstance(expr, Literal) and isinstance(expr.value, str):
                return f'{self.ind()}printf("%s\\n", {self.expr(expr)});'
            return f'{self.ind()}printf("%d\\n", {self.expr(expr)});'
        elif isinstance(node, VarDecl):
            return f"{self.ind()}int {node.name} = {self.expr(node.value)};"
        elif isinstance(node, LoopStmt):
            if node.start is not None:
                header = f"{self.ind()}for (int {node.var} = {self.expr(node.start)}; {node.var} < {self.expr(node.end)}; {node.var}++) {{"
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
            header = f"int {node.name}({', '.join(f'int {p}' for p in node.params)}) {{"
            self.indent = 1
            body = '\n'.join(self.stmt(s) for s in node.body)
            self.indent = 0
            return f"{header}\n{body}\n}}"
        elif isinstance(node, ReturnStmt):
            return f"{self.ind()}return {self.expr(node.value)};"
        return ""

    def expr(self, node: ASTNode) -> str:
        if isinstance(node, Literal):
            if isinstance(node.value, str):
                return f'"{node.value}"'
            elif node.value is None:
                return '0'
            elif isinstance(node.value, bool):
                return '1' if node.value else '0'
            return str(int(node.value))
        elif isinstance(node, VarRef):
            return node.name
        elif isinstance(node, BinaryOp):
            return f"({self.expr(node.left)} {node.op} {self.expr(node.right)})"
        elif isinstance(node, UnaryOp):
            return f"({node.op}{self.expr(node.operand)})"
        elif isinstance(node, FuncCall):
            args = ', '.join(self.expr(a) for a in node.args)
            return f"{node.name}({args})"
        return ""
