"""
JibJab Interpreter - Executes JJ programs directly
Uses emit values from common/jj.json
"""

from typing import Any, Dict, List

from .lexer import JJ
from .ast import (
    ASTNode, Program, PrintStmt, InputExpr, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt,
    EnumDef, ArrayLiteral, DictLiteral, TupleLiteral, IndexAccess,
    StringInterpolation
)

OP = JJ['operators']


class Interpreter:
    def __init__(self):
        self.globals: Dict[str, Any] = {}
        self.locals: List[Dict[str, Any]] = [{}]
        self.functions: Dict[str, FuncDef] = {}

    @staticmethod
    def stringify(value) -> str:
        if value is None:
            return 'nil'
        if isinstance(value, bool):
            return 'true' if value else 'false'
        if isinstance(value, float):
            if value == int(value):
                return str(int(value))
            return str(value)
        if isinstance(value, list):
            return '[' + ', '.join(Interpreter.stringify(v) for v in value) + ']'
        if isinstance(value, tuple):
            return '(' + ', '.join(Interpreter.stringify(v) for v in value) + ')'
        if isinstance(value, dict):
            items = ', '.join(f'"{k}": {Interpreter.stringify(v)}' for k, v in value.items())
            return '{' + items + '}'
        return str(value)

    def run(self, program: Program):
        for stmt in program.statements:
            self.execute(stmt)

    def execute(self, node: ASTNode) -> Any:
        if isinstance(node, PrintStmt):
            value = self.evaluate(node.expr)
            print(self.stringify(value))
        elif isinstance(node, VarDecl):
            self.locals[-1][node.name] = self.evaluate(node.value)
        elif isinstance(node, LoopStmt):
            if node.start is not None and node.end is not None:
                start = int(self.evaluate(node.start))
                end = int(self.evaluate(node.end))
                for i in range(start, end):
                    self.locals[-1][node.var] = i
                    for stmt in node.body:
                        result = self.execute(stmt)
                        if isinstance(result, tuple) and result[0] == 'return':
                            return result
            elif node.collection is not None:
                collection = self.evaluate(node.collection)
                for item in collection:
                    self.locals[-1][node.var] = item
                    for stmt in node.body:
                        result = self.execute(stmt)
                        if isinstance(result, tuple) and result[0] == 'return':
                            return result
            elif node.condition is not None:
                while self.evaluate(node.condition):
                    for stmt in node.body:
                        result = self.execute(stmt)
                        if isinstance(result, tuple) and result[0] == 'return':
                            return result
        elif isinstance(node, IfStmt):
            if self.evaluate(node.condition):
                for stmt in node.then_body:
                    result = self.execute(stmt)
                    if isinstance(result, tuple) and result[0] == 'return':
                        return result
            elif node.else_body:
                for stmt in node.else_body:
                    result = self.execute(stmt)
                    if isinstance(result, tuple) and result[0] == 'return':
                        return result
        elif isinstance(node, FuncDef):
            self.functions[node.name] = node
        elif isinstance(node, EnumDef):
            # Store enum as a dictionary mapping case names to themselves
            self.locals[-1][node.name] = {case: case for case in node.cases}
        elif isinstance(node, ReturnStmt):
            return ('return', self.evaluate(node.value))
        return None

    def evaluate(self, node: ASTNode) -> Any:
        if isinstance(node, Literal):
            return node.value
        elif isinstance(node, StringInterpolation):
            result = ''
            for kind, text in node.parts:
                if kind == 'literal':
                    result += text
                elif kind == 'variable':
                    found = False
                    for scope in reversed(self.locals):
                        if text in scope:
                            result += self.stringify(scope[text])
                            found = True
                            break
                    if not found:
                        result += text
            return result
        elif isinstance(node, ArrayLiteral):
            return [self.evaluate(elem) for elem in node.elements]
        elif isinstance(node, DictLiteral):
            return {str(self.evaluate(k)): self.evaluate(v) for k, v in node.pairs}
        elif isinstance(node, TupleLiteral):
            return tuple(self.evaluate(elem) for elem in node.elements)
        elif isinstance(node, IndexAccess):
            container = self.evaluate(node.array)
            key = self.evaluate(node.index)
            if isinstance(container, (list, tuple)):
                idx = int(key)
                if idx < 0 or idx >= len(container):
                    raise IndexError(f"Index out of bounds: {idx}")
                return container[idx]
            elif isinstance(container, dict):
                key_str = str(key)
                if key_str not in container:
                    raise KeyError(f"Dictionary key not found: {key_str}")
                return container[key_str]
            raise TypeError("Cannot index non-array/non-tuple/non-dictionary value")
        elif isinstance(node, VarRef):
            for scope in reversed(self.locals):
                if node.name in scope:
                    return scope[node.name]
            raise NameError(f"Undefined variable: {node.name}")
        elif isinstance(node, BinaryOp):
            left = self.evaluate(node.left)
            right = self.evaluate(node.right)
            ops = {
                OP['add']['emit']: lambda a, b: a + b,
                OP['sub']['emit']: lambda a, b: a - b,
                OP['mul']['emit']: lambda a, b: a * b,
                OP['div']['emit']: lambda a, b: a / b,
                OP['mod']['emit']: lambda a, b: a % b,
                OP['eq']['emit']: lambda a, b: a == b,
                OP['neq']['emit']: lambda a, b: a != b,
                OP['lt']['emit']: lambda a, b: a < b,
                OP['lte']['emit']: lambda a, b: a <= b,
                OP['gt']['emit']: lambda a, b: a > b,
                OP['gte']['emit']: lambda a, b: a >= b,
                OP['and']['emit']: lambda a, b: a and b,
                OP['or']['emit']: lambda a, b: a or b,
            }
            return ops[node.op](left, right)
        elif isinstance(node, UnaryOp):
            operand = self.evaluate(node.operand)
            if node.op == OP['not']['emit']:
                return not operand
        elif isinstance(node, InputExpr):
            prompt = self.evaluate(node.prompt)
            return input(prompt)
        elif isinstance(node, FuncCall):
            func = self.functions.get(node.name)
            if not func:
                raise NameError(f"Undefined function: {node.name}")
            args = [self.evaluate(arg) for arg in node.args]
            self.locals.append({})
            for param, arg in zip(func.params, args):
                self.locals[-1][param] = arg
            result = None
            for stmt in func.body:
                result = self.execute(stmt)
                if isinstance(result, tuple) and result[0] == 'return':
                    self.locals.pop()
                    return result[1]
            self.locals.pop()
            return result
        return None
