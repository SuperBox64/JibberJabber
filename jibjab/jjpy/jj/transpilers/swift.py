"""
JibJab Swift Transpiler - Converts JJ to Swift
Uses shared config from common/jj.json
"""

from ..lexer import JJ, load_target_config
from ..ast import (
    ASTNode, Program, PrintStmt, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt,
    EnumDef, IndexAccess, ArrayLiteral, DictLiteral, TupleLiteral
)

# Get target config and operators
T = load_target_config('swift')
OP = JJ['operators']


class SwiftTranspiler:
    def __init__(self):
        self.indent = 0
        self.enums = set()
        self.double_vars = set()
        self.dict_vars = set()
        self.tuple_vars = set()

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
            # Track double variables
            if isinstance(node.value, Literal) and isinstance(node.value.value, float):
                self.double_vars.add(node.name)
            # Dict declaration
            if isinstance(node.value, DictLiteral):
                self.dict_vars.add(node.name)
                if not node.value.pairs:
                    return self.ind() + f"var {node.name}: [String: Any] = [:]"
                return self.ind() + f"var {node.name}: [String: Any] = {self.expr(node.value)}"
            # Tuple declaration
            if isinstance(node.value, TupleLiteral):
                self.tuple_vars.add(node.name)
                template = T.get('varInfer', T['var'])
                return self.ind() + template.replace('{name}', node.name).replace('{value}', self.expr(node.value))
            template = T.get('varInfer', T['var'])
            return self.ind() + template.replace('{name}', node.name).replace('{value}', self.expr(node.value))
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
            # Swift requires typed parameters with _ to suppress argument labels
            typed_params = ', '.join(f'_ {p}: Int' for p in node.params)
            header = self.ind() + T['func'].replace('{name}', node.name).replace('{params}', typed_params)
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body)
            self.indent -= 1
            return f"{header}\n{body}\n{self.ind()}{T['blockEnd']}"
        elif isinstance(node, ReturnStmt):
            return self.ind() + T['return'].replace('{value}', self.expr(node.value))
        elif isinstance(node, EnumDef):
            self.enums.add(node.name)
            cases = ', '.join(node.cases)
            return self.ind() + f"enum {node.name} {{ case {cases} }}"
        return ""

    def expr(self, node: ASTNode) -> str:
        if isinstance(node, Literal):
            if isinstance(node.value, str):
                # Swift uses double quotes for strings
                escaped = node.value.replace('\\', '\\\\').replace('"', '\\"')
                return f'"{escaped}"'
            elif node.value is None:
                return T['nil']
            elif isinstance(node.value, bool):
                return T['true'] if node.value else T['false']
            elif isinstance(node.value, float):
                return str(node.value)
            elif isinstance(node.value, int):
                return str(node.value)
            return str(node.value)
        elif isinstance(node, VarRef):
            # If referencing an enum type directly, use .self
            if node.name in self.enums:
                return f"{node.name}.self"
            return node.name
        elif isinstance(node, IndexAccess):
            # Check if this is enum access (e.g., Color["Red"] -> Color.Red)
            if isinstance(node.array, VarRef) and node.array.name in self.enums:
                if isinstance(node.index, Literal) and isinstance(node.index.value, str):
                    return f"{node.array.name}.{node.index.value}"
            # Tuple access: use .N dot syntax instead of [N]
            if isinstance(node.array, VarRef) and node.array.name in self.tuple_vars:
                if isinstance(node.index, Literal) and isinstance(node.index.value, int):
                    return f"{node.array.name}.{node.index.value}"
            # Dict access: force-unwrap with !
            if isinstance(node.array, VarRef) and node.array.name in self.dict_vars:
                # Nested access like data["items"][0]
                return f"{self.expr(node.array)}[{self.expr(node.index)}]!"
            # Nested dict access (e.g., data["items"] is already unwrapped, then [0])
            if isinstance(node.array, IndexAccess):
                inner = self.expr(node.array)
                idx = self.expr(node.index)
                # If inner is a dict access that returns Any, cast to array
                if isinstance(node.array.array, VarRef) and node.array.array.name in self.dict_vars:
                    return f"({inner} as! [Any])[{idx}]"
                return f"{inner}[{idx}]"
            return f"{self.expr(node.array)}[{self.expr(node.index)}]"
        elif isinstance(node, ArrayLiteral):
            elements = ', '.join(self.expr(e) for e in node.elements)
            return f"[{elements}]"
        elif isinstance(node, DictLiteral):
            if not node.pairs:
                return "[:]"
            pairs = ', '.join(f"{self.expr(k)}: {self.expr(v)}" for k, v in node.pairs)
            return f"[{pairs}]"
        elif isinstance(node, TupleLiteral):
            if not node.elements:
                return "()"
            if len(node.elements) == 1:
                return f"({self.expr(node.elements[0])},)"
            elements = ', '.join(self.expr(e) for e in node.elements)
            return f"({elements})"
        elif isinstance(node, BinaryOp):
            # Use truncatingRemainder for float modulo in Swift
            if node.op == '%' and (self.is_float_expr(node.left) or self.is_float_expr(node.right)):
                return f"{self.expr(node.left)}.truncatingRemainder(dividingBy: {self.expr(node.right)})"
            return f"({self.expr(node.left)} {node.op} {self.expr(node.right)})"
        elif isinstance(node, UnaryOp):
            return f"({node.op}{self.expr(node.operand)})"
        elif isinstance(node, FuncCall):
            return T['call'].replace('{name}', node.name).replace('{args}', ', '.join(self.expr(a) for a in node.args))
        return ""
