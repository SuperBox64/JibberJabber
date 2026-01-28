"""
JibJab Objective-C Transpiler - Converts JJ to Objective-C
Uses shared C-family base from cfamily.py
"""

from ..ast import (
    Literal, VarRef, VarDecl, ArrayLiteral, DictLiteral, TupleLiteral,
    IndexAccess, EnumDef, PrintStmt, FuncDef
)
from .cfamily import CFamilyTranspiler, infer_type


class ObjCTranspiler(CFamilyTranspiler):
    target_name = 'objc'

    def _emit_main(self, lines, program):
        main_stmts = [s for s in program.statements if not isinstance(s, FuncDef)]
        if main_stmts:
            lines.append('int main(int argc, const char * argv[]) {')
            lines.append('    @autoreleasepool {')
            self.indent = 2
            for s in main_stmts:
                lines.append(self.stmt(s))
            lines.append('    }')
            lines.append('    return 0;')
            lines.append('}')

    def _print_stmt(self, node: PrintStmt) -> str:
        expr_node = node.expr
        if isinstance(expr_node, Literal) and isinstance(expr_node.value, str):
            return self.ind() + f'NSLog(@"%@", @{self.expr(expr_node)});'
        if isinstance(expr_node, VarRef):
            if expr_node.name in self.enums:
                return self.ind() + f'NSLog(@"%@", @"enum {expr_node.name}");'
            if expr_node.name in self.double_vars:
                return self.ind() + f'NSLog(@"%f", {self.expr(expr_node)});'
            if expr_node.name in self.int_vars:
                return self.ind() + f'NSLog(@"%ld", (long){self.expr(expr_node)});'
            return self.ind() + f'NSLog(@"%@", {self.expr(expr_node)});'
        if isinstance(expr_node, ArrayLiteral):
            return self.ind() + f'NSLog(@"%@", {self.expr(expr_node)});'
        if isinstance(expr_node, IndexAccess):
            if isinstance(expr_node.array, VarRef) and expr_node.array.name in self.enums:
                return self.ind() + f'NSLog(@"%ld", (long){self.expr(expr_node)});'
            return self.ind() + f'NSLog(@"%@", {self.expr(expr_node)});'
        if self.is_float_expr(expr_node):
            return self.ind() + f'NSLog(@"%f", {self.expr(expr_node)});'
        return self.ind() + self.T['printInt'].replace('{expr}', self.expr(expr_node))

    def _var_array(self, node: VarDecl) -> str:
        return self.ind() + f"NSArray *{node.name} = {self.expr(node.value)};"

    def _enum_def(self, node: EnumDef) -> str:
        self.enums.add(node.name)
        cases = ', '.join(node.cases)
        return self.ind() + f"typedef NS_ENUM(NSInteger, {node.name}) {{ {cases} }};"

    def _expr_array(self, node: ArrayLiteral) -> str:
        def box_element(e):
            if isinstance(e, Literal):
                if isinstance(e.value, str):
                    return f'@{self.expr(e)}'
                else:
                    return f'@({self.expr(e)})'
            elif isinstance(e, ArrayLiteral):
                return self.expr(e)
            else:
                return f'@({self.expr(e)})'
        elements = ', '.join(box_element(e) for e in node.elements)
        return f"@[{elements}]"

    def _expr_dict(self, node: DictLiteral) -> str:
        pairs = ', '.join(f"@{self.expr(k)}: @({self.expr(v)})" for k, v in node.pairs)
        return f"@{{{pairs}}}"

    def _expr_tuple(self, node: TupleLiteral) -> str:
        elements = ', '.join(f"@({self.expr(e)})" for e in node.elements)
        return f"@[{elements}]"
