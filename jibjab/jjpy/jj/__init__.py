"""
JibJab (JJ) Programming Language
A language designed for AI comprehension
"""

from .lexer import Lexer, Token, TokenType
from .ast import (
    ASTNode, Program, PrintStmt, InputExpr, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt,
    ArrayLiteral
)
from .parser import Parser
from .interpreter import Interpreter
from .transpilers import (
    PythonTranspiler,
    JavaScriptTranspiler,
    CTranspiler,
    AssemblyTranspiler,
    SwiftTranspiler,
    AppleScriptTranspiler,
    CppTranspiler,
    ObjCTranspiler,
    ObjCppTranspiler,
    GoTranspiler
)
from .native_compiler import NativeCompiler
from .reverse_transpiler import get_reverse_transpiler

__version__ = '1.0.0'

__all__ = [
    # Core
    'Lexer', 'Token', 'TokenType',
    'Parser',
    'Interpreter',
    'NativeCompiler',

    # AST
    'ASTNode', 'Program', 'PrintStmt', 'InputExpr', 'VarDecl', 'VarRef',
    'Literal', 'BinaryOp', 'UnaryOp', 'LoopStmt', 'IfStmt', 'FuncDef',
    'FuncCall', 'ReturnStmt', 'ArrayLiteral',

    # Transpilers
    'PythonTranspiler',
    'JavaScriptTranspiler',
    'CTranspiler',
    'AssemblyTranspiler',
    'SwiftTranspiler',
    'AppleScriptTranspiler',
    'CppTranspiler',
    'ObjCTranspiler',
    'ObjCppTranspiler',
    'GoTranspiler',

    # Reverse Transpiler
    'get_reverse_transpiler',
]
