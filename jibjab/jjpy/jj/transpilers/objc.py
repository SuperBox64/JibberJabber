"""
JibJab Objective-C Transpiler - Converts JJ to Objective-C
Uses shared config from common/jj.json
"""

from ..lexer import JJ
from ..ast import (
    ASTNode, Program, PrintStmt, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt
)

# Get target config
T = JJ['targets']['objc']


class ObjCTranspiler:
    def __init__(self):
        self.indent = 0

    def transpile(self, program: Program) -> str:
        lines = [T['header'].rstrip(), '']

        # Forward declarations
        funcs = [s for s in program.statements if isinstance(s, FuncDef)]
        for f in funcs:
            params = ', '.join(f'int {p}' for p in f.params)
            lines.append(T['funcDecl'].replace('{name}', f.name).replace('{params}', params))
        if funcs:
            lines.append('')

        # Function definitions
        for f in funcs:
            lines.append(self.stmt(f))
            lines.append('')

        # Main with @autoreleasepool
        main_stmts = [s for s in program.statements if not isinstance(s, FuncDef)]
        if main_stmts:
            lines.append('int main(int argc, const char * argv[]) {')
            lines.append('    @autoreleasepool {')
            self.indent = 2
            for stmt in main_stmts:
                lines.append(self.stmt(stmt))
            lines.append('    }')
            lines.append('    return 0;')
            lines.append('}')

        return '\n'.join(lines)

    def ind(self) -> str:
        return T['indent'] * self.indent

    def stmt(self, node: ASTNode) -> str:
        if isinstance(node, PrintStmt):
            expr = node.expr
            if isinstance(expr, Literal) and isinstance(expr.value, str):
                # String literal - use @"string" format
                return self.ind() + f'NSLog(@"%@", @{self.expr(expr)});'
            return self.ind() + T['printInt'].replace('{expr}', self.expr(expr))
        elif isinstance(node, VarDecl):
            return self.ind() + T['var'].replace('{name}', node.name).replace('{value}', self.expr(node.value))
        elif isinstance(node, LoopStmt):
            if node.start is not None:
                header = self.ind() + T['forRange'].replace('{var}', node.var).replace('{start}', self.expr(node.start)).replace('{end}', self.expr(node.end))
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
            params = ', '.join(f'int {p}' for p in node.params)
            header = T['func'].replace('{name}', node.name).replace('{params}', params)
            self.indent = 1
            body = '\n'.join(self.stmt(s) for s in node.body)
            self.indent = 0
            return f"{header}\n{body}\n{T['blockEnd']}"
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
            return str(int(node.value))
        elif isinstance(node, VarRef):
            return node.name
        elif isinstance(node, BinaryOp):
            return f"({self.expr(node.left)} {node.op} {self.expr(node.right)})"
        elif isinstance(node, UnaryOp):
            return f"({node.op}{self.expr(node.operand)})"
        elif isinstance(node, FuncCall):
            return T['call'].replace('{name}', node.name).replace('{args}', ', '.join(self.expr(a) for a in node.args))
        return ""
