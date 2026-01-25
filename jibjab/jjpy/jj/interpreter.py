"""
JibJab Interpreter - Executes JJ programs directly
"""

from typing import Any, Dict, List

from .ast import (
    ASTNode, Program, PrintStmt, InputExpr, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt
)


class Interpreter:
    def __init__(self):
        self.globals: Dict[str, Any] = {}
        self.locals: List[Dict[str, Any]] = [{}]
        self.functions: Dict[str, FuncDef] = {}

    def run(self, program: Program):
        for stmt in program.statements:
            self.execute(stmt)

    def execute(self, node: ASTNode) -> Any:
        if isinstance(node, PrintStmt):
            value = self.evaluate(node.expr)
            print(value)
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
        elif isinstance(node, ReturnStmt):
            return ('return', self.evaluate(node.value))
        return None

    def evaluate(self, node: ASTNode) -> Any:
        if isinstance(node, Literal):
            return node.value
        elif isinstance(node, VarRef):
            for scope in reversed(self.locals):
                if node.name in scope:
                    return scope[node.name]
            raise NameError(f"Undefined variable: {node.name}")
        elif isinstance(node, BinaryOp):
            left = self.evaluate(node.left)
            right = self.evaluate(node.right)
            ops = {
                '+': lambda a, b: a + b,
                '-': lambda a, b: a - b,
                '*': lambda a, b: a * b,
                '/': lambda a, b: a / b,
                '%': lambda a, b: a % b,
                '==': lambda a, b: a == b,
                '!=': lambda a, b: a != b,
                '<': lambda a, b: a < b,
                '>': lambda a, b: a > b,
                '&&': lambda a, b: a and b,
                '||': lambda a, b: a or b,
            }
            return ops[node.op](left, right)
        elif isinstance(node, UnaryOp):
            operand = self.evaluate(node.operand)
            if node.op == '!':
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
