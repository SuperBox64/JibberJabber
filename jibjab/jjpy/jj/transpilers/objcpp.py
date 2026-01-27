"""
JibJab Objective-C++ Transpiler - Converts JJ to Objective-C++
Uses shared config from common/jj.json
"""

from ..lexer import load_target_config
from ..ast import (
    ASTNode, Program, PrintStmt, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt,
    ArrayLiteral, DictLiteral, TupleLiteral, IndexAccess, EnumDef
)

# Get target config
T = load_target_config('objcpp')


def infer_type(node) -> str:
    """Infer JJ type from AST node"""
    if isinstance(node, Literal):
        if isinstance(node.value, bool):
            return 'Int'  # ObjC++ uses int for bool
        elif isinstance(node.value, int):
            return 'Int'
        elif isinstance(node.value, float):
            return 'Double'
        elif isinstance(node.value, str):
            return 'String'
    elif isinstance(node, ArrayLiteral):
        return 'Array'
    return 'Int'  # default

def get_target_type(jj_type: str) -> str:
    """Get target language type from JJ type"""
    types = T.get('types', {})
    return types.get(jj_type, 'int')


class ObjCppTranspiler:
    def __init__(self):
        self.indent = 0

    def transpile(self, program: Program) -> str:
        lines = [T['header'].rstrip(), '']

        # Forward declarations
        funcs = [s for s in program.statements if isinstance(s, FuncDef)]
        for f in funcs:
            param_type = get_target_type('Int')
            params = ', '.join(f'{param_type} {p}' for p in f.params)
            return_type = get_target_type('Int')
            lines.append(T['funcDecl'].replace('{type}', return_type).replace('{name}', f.name).replace('{params}', params))
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
                return self.ind() + f'NSLog(@"%@", @{self.expr(expr)});'
            elif isinstance(expr, ArrayLiteral) or isinstance(expr, VarRef):
                return self.ind() + f'NSLog(@"%@", {self.expr(expr)});'
            elif isinstance(expr, IndexAccess):
                return self.ind() + f'NSLog(@"%@", {self.expr(expr)});'
            return self.ind() + T['printInt'].replace('{expr}', self.expr(node.expr))
        elif isinstance(node, VarDecl):
            # Check if it's an array
            if isinstance(node.value, ArrayLiteral):
                return self.ind() + f"NSArray *{node.name} = {self.expr(node.value)};"
            var_type = get_target_type(infer_type(node.value))
            return self.ind() + T['var'].replace('{type}', var_type).replace('{name}', node.name).replace('{value}', self.expr(node.value))
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
            param_type = get_target_type('Int')
            params = ', '.join(f'{param_type} {p}' for p in node.params)
            return_type = get_target_type('Int')
            header = T['func'].replace('{type}', return_type).replace('{name}', node.name).replace('{params}', params)
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
        elif isinstance(node, ArrayLiteral):
            def box_element(e):
                if isinstance(e, Literal):
                    if isinstance(e.value, str):
                        return f'@{self.expr(e)}'  # @"string"
                    else:
                        return f'@({self.expr(e)})'  # @(number)
                elif isinstance(e, ArrayLiteral):
                    return self.expr(e)  # Nested arrays
                else:
                    return f'@({self.expr(e)})'
            elements = ', '.join(box_element(e) for e in node.elements)
            return f"@[{elements}]"
        elif isinstance(node, DictLiteral):
            pairs = ', '.join(f"{{{self.expr(k)}, {self.expr(v)}}}" for k, v in node.pairs)
            return f"{{{pairs}}}"
        elif isinstance(node, TupleLiteral):
            elements = ', '.join(self.expr(e) for e in node.elements)
            return f"std::make_tuple({elements})"
        elif isinstance(node, IndexAccess):
            return f"{self.expr(node.array)}[{self.expr(node.index)}]"
        elif isinstance(node, BinaryOp):
            return f"({self.expr(node.left)} {node.op} {self.expr(node.right)})"
        elif isinstance(node, UnaryOp):
            return f"({node.op}{self.expr(node.operand)})"
        elif isinstance(node, FuncCall):
            return T['call'].replace('{name}', node.name).replace('{args}', ', '.join(self.expr(a) for a in node.args))
        return ""
