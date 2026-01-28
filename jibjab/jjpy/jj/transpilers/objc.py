"""
JibJab Objective-C Transpiler - Converts JJ to Objective-C
Uses shared config from common/jj.json
"""

from ..lexer import load_target_config
from ..ast import (
    ASTNode, Program, PrintStmt, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt,
    ArrayLiteral, DictLiteral, TupleLiteral, IndexAccess, EnumDef
)

# Get target config
T = load_target_config('objc')


def infer_type(node) -> str:
    """Infer JJ type from AST node"""
    if isinstance(node, Literal):
        if isinstance(node.value, bool):
            return 'Int'  # ObjC uses int for bool
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


class ObjCTranspiler:
    def __init__(self):
        self.indent = 0
        self.enums = set()  # Track defined enum names
        self.int_vars = set()  # Track integer variable names
        self.double_vars = set()  # Track double variable names

    def is_float_expr(self, node) -> bool:
        """Check if expression involves floating-point values"""
        if isinstance(node, Literal):
            return isinstance(node.value, float)
        if isinstance(node, VarRef):
            return node.name in self.double_vars
        if isinstance(node, BinaryOp):
            return self.is_float_expr(node.left) or self.is_float_expr(node.right)
        if isinstance(node, UnaryOp):
            return self.is_float_expr(node.operand)
        return False

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
                # String literal - use @"string" format
                return self.ind() + f'NSLog(@"%@", @{self.expr(expr)});'
            elif isinstance(expr, VarRef):
                # Check if trying to print an enum type (not a value)
                if expr.name in self.enums:
                    return self.ind() + f'NSLog(@"%@", @"enum {expr.name}");'
                # Double variables use %f
                if expr.name in self.double_vars:
                    return self.ind() + f'NSLog(@"%f", {self.expr(expr)});'
                # Integer variables need %ld format
                if expr.name in self.int_vars:
                    return self.ind() + f'NSLog(@"%ld", (long){self.expr(expr)});'
                # Arrays print with %@
                return self.ind() + f'NSLog(@"%@", {self.expr(expr)});'
            elif isinstance(expr, ArrayLiteral):
                return self.ind() + f'NSLog(@"%@", {self.expr(expr)});'
            elif isinstance(expr, IndexAccess):
                # Check if this is enum value access
                if isinstance(expr.array, VarRef) and expr.array.name in self.enums:
                    return self.ind() + f'NSLog(@"%ld", (long){self.expr(expr)});'
                # Index access on NSArray returns id, print with %@
                return self.ind() + f'NSLog(@"%@", {self.expr(expr)});'
            # Check if expression involves floats
            if self.is_float_expr(expr):
                return self.ind() + f'NSLog(@"%f", {self.expr(expr)});'
            return self.ind() + T['printInt'].replace('{expr}', self.expr(expr))
        elif isinstance(node, VarDecl):
            # Check if it's an array
            if isinstance(node.value, ArrayLiteral):
                return self.ind() + f"NSArray *{node.name} = {self.expr(node.value)};"
            # Track variable types for proper print formatting
            inferred = infer_type(node.value)
            if inferred == 'Int':
                self.int_vars.add(node.name)
            elif inferred == 'Double':
                self.double_vars.add(node.name)
            var_type = get_target_type(inferred)
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
        elif isinstance(node, EnumDef):
            self.enums.add(node.name)
            cases = ', '.join(node.cases)
            return self.ind() + f"typedef NS_ENUM(NSInteger, {node.name}) {{ {cases} }};"
        return ""

    def expr(self, node: ASTNode) -> str:
        if isinstance(node, Literal):
            if isinstance(node.value, str):
                return f'"{node.value}"'
            elif node.value is None:
                return T['nil']
            elif isinstance(node.value, bool):
                return T['true'] if node.value else T['false']
            elif isinstance(node.value, float):
                return str(node.value)
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
            pairs = ', '.join(f"@{self.expr(k)}: @({self.expr(v)})" for k, v in node.pairs)
            return f"@{{{pairs}}}"
        elif isinstance(node, TupleLiteral):
            elements = ', '.join(f"@({self.expr(e)})" for e in node.elements)
            return f"@[{elements}]"
        elif isinstance(node, IndexAccess):
            # Check if this is enum access (e.g., Color["Red"] -> Red)
            if isinstance(node.array, VarRef) and node.array.name in self.enums:
                if isinstance(node.index, Literal) and isinstance(node.index.value, str):
                    return node.index.value  # Just return the enum case name
            return f"{self.expr(node.array)}[{self.expr(node.index)}]"
        elif isinstance(node, BinaryOp):
            # Use fmod for float modulo
            if node.op == '%' and (self.is_float_expr(node.left) or self.is_float_expr(node.right)):
                return f"fmod({self.expr(node.left)}, {self.expr(node.right)})"
            return f"({self.expr(node.left)} {node.op} {self.expr(node.right)})"
        elif isinstance(node, UnaryOp):
            return f"({node.op}{self.expr(node.operand)})"
        elif isinstance(node, FuncCall):
            return T['call'].replace('{name}', node.name).replace('{args}', ', '.join(self.expr(a) for a in node.args))
        return ""
