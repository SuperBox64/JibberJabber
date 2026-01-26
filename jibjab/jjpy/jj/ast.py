"""
JibJab AST - Abstract Syntax Tree node definitions
"""

from typing import Any, List, Optional
from dataclasses import dataclass


@dataclass
class ASTNode:
    pass


@dataclass
class Program(ASTNode):
    statements: List[ASTNode]


@dataclass
class PrintStmt(ASTNode):
    expr: ASTNode


@dataclass
class InputExpr(ASTNode):
    prompt: ASTNode


@dataclass
class VarDecl(ASTNode):
    name: str
    value: ASTNode


@dataclass
class VarRef(ASTNode):
    name: str


@dataclass
class Literal(ASTNode):
    value: Any


@dataclass
class BinaryOp(ASTNode):
    left: ASTNode
    op: str
    right: ASTNode


@dataclass
class UnaryOp(ASTNode):
    op: str
    operand: ASTNode


@dataclass
class LoopStmt(ASTNode):
    var: str
    start: Optional[ASTNode]
    end: Optional[ASTNode]
    collection: Optional[ASTNode]
    condition: Optional[ASTNode]
    body: List[ASTNode]


@dataclass
class IfStmt(ASTNode):
    condition: ASTNode
    then_body: List[ASTNode]
    else_body: Optional[List[ASTNode]]


@dataclass
class FuncDef(ASTNode):
    name: str
    params: List[str]
    body: List[ASTNode]


@dataclass
class FuncCall(ASTNode):
    name: str
    args: List[ASTNode]


@dataclass
class ReturnStmt(ASTNode):
    value: ASTNode


@dataclass
class EnumDef(ASTNode):
    name: str
    cases: List[str]


@dataclass
class ArrayLiteral(ASTNode):
    elements: List[ASTNode]


@dataclass
class DictLiteral(ASTNode):
    pairs: List[tuple]  # List of (key: ASTNode, value: ASTNode) tuples


@dataclass
class TupleLiteral(ASTNode):
    elements: List[ASTNode]


@dataclass
class IndexAccess(ASTNode):
    array: ASTNode
    index: ASTNode
