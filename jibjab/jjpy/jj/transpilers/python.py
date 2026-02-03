"""
JibJab Python Transpiler - Converts JJ to Python
Uses shared config from common/jj.json
"""

from ..lexer import JJ, load_target_config
from ..ast import (
    ASTNode, Program, PrintStmt, LogStmt, InputExpr, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, TryStmt, FuncDef, FuncCall,
    ReturnStmt, ThrowStmt, ArrayLiteral, DictLiteral, TupleLiteral, IndexAccess,
    EnumDef, StringInterpolation
)

# Get target config and operators
T = load_target_config('py')
OP = JJ['operators']


class PythonTranspiler:
    def __init__(self):
        self.indent = 0
        self.bool_vars = set()

    def transpile(self, program: Program) -> str:
        lines = [T['header'].rstrip()]
        for stmt in program.statements:
            lines.append(self.stmt(stmt))
        return '\n'.join(lines)

    def ind(self) -> str:
        return T['indent'] * self.indent

    def stmt(self, node: ASTNode) -> str:
        if isinstance(node, PrintStmt):
            if isinstance(node.expr, VarRef) and node.expr.name in self.bool_vars:
                return self.ind() + T.get('printBool', T['print']).replace('{expr}', self.expr(node.expr))
            return self.ind() + T['print'].replace('{expr}', self.expr(node.expr))
        elif isinstance(node, LogStmt):
            if isinstance(node.expr, VarRef) and node.expr.name in self.bool_vars:
                return self.ind() + T.get('logBool', T['log']).replace('{expr}', self.expr(node.expr))
            return self.ind() + T['log'].replace('{expr}', self.expr(node.expr))
        elif isinstance(node, VarDecl):
            if isinstance(node.value, Literal) and isinstance(node.value.value, bool):
                self.bool_vars.add(node.name)
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
        elif isinstance(node, TryStmt):
            header = self.ind() + T['try']
            self.indent += 1
            try_body = '\n'.join(self.stmt(s) for s in node.try_body) or f"{self.ind()}pass"
            self.indent -= 1
            result = f"{header}\n{try_body}"
            if node.oops_body:
                catch_tmpl = T['catch']
                if node.oops_var and 'catchVar' in T:
                    catch_tmpl = T['catchVar'].replace('{var}', node.oops_var)
                result += f"\n{self.ind()}{catch_tmpl}"
                self.indent += 1
                if node.oops_var and 'catchVarBind' in T:
                    result += '\n' + self.ind() + T['catchVarBind'].replace('{var}', node.oops_var)
                oops_str = '\n'.join(self.stmt(s) for s in node.oops_body) or f"{self.ind()}pass"
                result += f"\n{oops_str}"
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
        elif isinstance(node, ThrowStmt):
            tmpl = T.get('throw')
            if tmpl:
                return self.ind() + tmpl.replace('{value}', self.expr(node.value))
            return self.ind() + T.get('comment', '#') + ' throw ' + self.expr(node.value)
        elif isinstance(node, EnumDef):
            # Python: Color = {'Red': 'Red', 'Green': 'Green', 'Blue': 'Blue'}
            cases = ', '.join(f"'{c}': '{c}'" for c in node.cases)
            return self.ind() + f"{node.name} = {{{cases}}}"
        return ""

    def expr(self, node: ASTNode) -> str:
        if isinstance(node, StringInterpolation):
            fstr = 'f"'
            for kind, text in node.parts:
                if kind == 'literal':
                    fstr += text.replace('\\', '\\\\').replace('"', '\\"')
                else:
                    if text in self.bool_vars:
                        fstr += '{str(' + text + ').lower()}'
                    else:
                        fstr += '{' + text + '}'
            return fstr + '"'
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
        elif isinstance(node, ArrayLiteral):
            elements = ', '.join(self.expr(e) for e in node.elements)
            return f"[{elements}]"
        elif isinstance(node, DictLiteral):
            pairs = ', '.join(f"{self.expr(k)}: {self.expr(v)}" for k, v in node.pairs)
            return "{" + pairs + "}"
        elif isinstance(node, TupleLiteral):
            elements = ', '.join(self.expr(e) for e in node.elements)
            # Single element tuple needs trailing comma
            if len(node.elements) == 1:
                return f"({elements},)"
            return f"({elements})"
        elif isinstance(node, IndexAccess):
            return f"{self.expr(node.array)}[{self.expr(node.index)}]"
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
