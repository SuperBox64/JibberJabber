"""
JibJab C++ Transpiler - Converts JJ to C++
Uses shared C-family base from cfamily.py
"""

from ..ast import Literal, VarRef, ArrayLiteral, DictLiteral, TupleLiteral, PrintStmt
from .cfamily import CFamilyTranspiler


class CppTranspiler(CFamilyTranspiler):
    target_name = 'cpp'

    def _print_stmt(self, node: PrintStmt) -> str:
        expr_node = node.expr
        if isinstance(expr_node, Literal) and isinstance(expr_node.value, str):
            return self.ind() + f'std::cout << {self.expr(expr_node)} << std::endl;'
        if isinstance(expr_node, VarRef) and expr_node.name in self.enums:
            return self.ind() + f'std::cout << "enum {expr_node.name}" << std::endl;'
        return self.ind() + self.T['printInt'].replace('{expr}', self.expr(node.expr))

    def _expr_dict(self, node: DictLiteral) -> str:
        pairs = ', '.join(f"{{{self.expr(k)}, {self.expr(v)}}}" for k, v in node.pairs)
        return f"{{{pairs}}}"

    def _expr_tuple(self, node: TupleLiteral) -> str:
        elements = ', '.join(self.expr(e) for e in node.elements)
        return f"std::make_tuple({elements})"
