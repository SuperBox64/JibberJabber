"""
JibJab AppleScript Transpiler - Converts JJ to AppleScript
Uses shared config from common/jj.json
"""

from ..lexer import JJ, load_target_config
from ..ast import (
    ASTNode, Program, PrintStmt, InputExpr, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt,
    ArrayLiteral, DictLiteral, TupleLiteral, IndexAccess, EnumDef
)

# Get target config and operators
T = load_target_config('applescript')
OP = JJ['operators']

# AppleScript reserved words and class names that can't be used as variable names
APPLESCRIPT_RESERVED = {
    # Language keywords
    'it', 'me', 'my', 'true', 'false', 'error', 'return', 'every', 'some',
    'first', 'last', 'middle', 'front', 'back',
    # Standard Suite commands
    'activate', 'close', 'count', 'copy', 'delete', 'duplicate', 'exists',
    'get', 'launch', 'make', 'move', 'open', 'print', 'quit', 'reopen',
    'run', 'save', 'set',
    # Standard Suite classes
    'alias', 'application', 'boolean', 'class', 'data', 'date', 'file',
    'integer', 'item', 'list', 'number', 'point', 'real', 'record',
    'reference', 'script', 'text',
    # Common properties
    'bounds', 'color', 'document', 'folder', 'disk', 'id', 'index',
    'length', 'name', 'position', 'property', 'result', 'size', 'value',
    'version', 'visible', 'window',
    # Text/collection elements
    'characters', 'items', 'numbers', 'paragraphs', 'strings', 'words',
    # Constants
    'missing', 'pi', 'tab', 'linefeed', 'quote', 'space', 'container',
}


def safe_name(name: str) -> str:
    """Prefix variable names that conflict with AppleScript reserved words."""
    if name.lower() in APPLESCRIPT_RESERVED:
        return f"my_{name}"
    return name


class AppleScriptTranspiler:
    def __init__(self):
        self.indent = 0
        self.dict_vars = set()

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
            if isinstance(node.value, DictLiteral):
                self.dict_vars.add(node.name)
            return self.ind() + T['var'].replace('{name}', safe_name(node.name)).replace('{value}', self.expr(node.value))
        elif isinstance(node, LoopStmt):
            if node.start is not None:
                header = self.ind() + T['forRange'].replace('{var}', safe_name(node.var)).replace('{start}', self.expr(node.start)).replace('{end}', self.expr(node.end))
            elif node.collection:
                header = self.ind() + T['forIn'].replace('{var}', safe_name(node.var)).replace('{collection}', self.expr(node.collection))
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
            params = ', '.join(safe_name(p) for p in node.params)
            header = self.ind() + T['func'].replace('{name}', safe_name(node.name)).replace('{params}', params)
            self.indent += 1
            body = '\n'.join(self.stmt(s) for s in node.body)
            self.indent -= 1
            return f"{header}\n{body}\n{self.ind()}end {safe_name(node.name)}"
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
            return safe_name(node.name)
        elif isinstance(node, ArrayLiteral):
            elements = ', '.join(self.expr(e) for e in node.elements)
            return f"{{{elements}}}"
        elif isinstance(node, DictLiteral):
            def safe_key(k):
                s = self.expr(k)
                if s.startswith('"') and s.endswith('"'):
                    s = s[1:-1]
                return safe_name(s)
            pairs = ', '.join(f"{safe_key(k)}:{self.expr(v)}" for k, v in node.pairs)
            return f"{{{pairs}}}"
        elif isinstance(node, TupleLiteral):
            elements = ', '.join(self.expr(e) for e in node.elements)
            return f"{{{elements}}}"
        elif isinstance(node, IndexAccess):
            # Dict access: person["name"] -> name of person
            if isinstance(node.array, VarRef) and node.array.name in self.dict_vars:
                if isinstance(node.index, Literal) and isinstance(node.index.value, str):
                    return f"{safe_name(node.index.value)} of {safe_name(node.array.name)}"
            # AppleScript uses 1-based indexing (nested dict+array resolves recursively)
            return f"item ({self.expr(node.index)} + 1) of {self.expr(node.array)}"
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
            return f"{safe_name(node.name)}({args})"
        return ""
