"""
JibJab Parser - Parses tokens into AST
"""

import re
from typing import List, Optional

from .lexer import Lexer, Token, TokenType
from .ast import (
    ASTNode, Program, PrintStmt, InputExpr, VarDecl, VarRef, Literal,
    BinaryOp, UnaryOp, LoopStmt, IfStmt, FuncDef, FuncCall, ReturnStmt
)


class Parser:
    def __init__(self, tokens: List[Token]):
        self.tokens = [t for t in tokens if t.type != TokenType.NEWLINE]
        self.pos = 0

    def peek(self, offset: int = 0) -> Token:
        pos = self.pos + offset
        if pos < len(self.tokens):
            return self.tokens[pos]
        return Token(TokenType.EOF, None, 0, 0)

    def advance(self) -> Token:
        token = self.peek()
        self.pos += 1
        return token

    def match(self, *types: TokenType) -> Optional[Token]:
        if self.peek().type in types:
            return self.advance()
        return None

    def expect(self, type: TokenType) -> Token:
        if self.peek().type == type:
            return self.advance()
        raise SyntaxError(f"Expected {type}, got {self.peek().type} at line {self.peek().line}")

    def parse(self) -> Program:
        statements = []
        while self.peek().type != TokenType.EOF:
            stmt = self.parse_statement()
            if stmt:
                statements.append(stmt)
        return Program(statements)

    def parse_statement(self) -> Optional[ASTNode]:
        if self.peek().type == TokenType.PRINT:
            return self.parse_print()
        if self.peek().type == TokenType.SNAG:
            return self.parse_var_decl()
        if self.peek().type == TokenType.LOOP:
            return self.parse_loop()
        if self.peek().type == TokenType.WHEN:
            return self.parse_if()
        if self.peek().type == TokenType.MORPH:
            return self.parse_func_def()
        if self.peek().type == TokenType.YEET:
            return self.parse_return()
        return None

    def parse_print(self) -> PrintStmt:
        self.advance()  # PRINT
        self.expect(TokenType.ACTION)
        self.expect(TokenType.EMIT)
        self.expect(TokenType.LPAREN)
        expr = self.parse_expression()
        self.expect(TokenType.RPAREN)
        return PrintStmt(expr)

    def parse_var_decl(self) -> VarDecl:
        self.advance()  # SNAG
        self.expect(TokenType.LBRACE)
        name = self.expect(TokenType.IDENTIFIER).value
        self.expect(TokenType.RBRACE)
        self.expect(TokenType.ACTION)
        self.expect(TokenType.VAL)
        self.expect(TokenType.LPAREN)
        value = self.parse_expression()
        self.expect(TokenType.RPAREN)
        return VarDecl(name, value)

    def parse_loop(self) -> LoopStmt:
        token = self.advance()  # LOOP with value
        loop_spec = token.value
        body = self.parse_block()

        # Parse loop specification
        if '..' in loop_spec:
            parts = loop_spec.split(':')
            var = parts[0]
            range_parts = parts[1].split('..')
            start = self.parse_inline_expr(range_parts[0])
            end = self.parse_inline_expr(range_parts[1])
            return LoopStmt(var, start, end, None, None, body)
        elif ':' in loop_spec:
            parts = loop_spec.split(':')
            var = parts[0]
            collection = VarRef(parts[1])
            return LoopStmt(var, None, None, collection, None, body)
        else:
            condition = self.parse_inline_expr(loop_spec)
            return LoopStmt('_', None, None, None, condition, body)

    def parse_if(self) -> IfStmt:
        token = self.advance()  # WHEN with condition
        condition = self.parse_inline_expr(token.value)
        then_body = self.parse_block()
        else_body = None

        if self.peek().type == TokenType.ELSE:
            self.advance()
            else_body = self.parse_block()

        return IfStmt(condition, then_body, else_body)

    def parse_func_def(self) -> FuncDef:
        token = self.advance()  # MORPH with signature
        sig = token.value
        match = re.match(r'(\w+)\(([^)]*)\)', sig)
        name = match.group(1)
        params = [p.strip() for p in match.group(2).split(',') if p.strip()]
        body = self.parse_block()
        return FuncDef(name, params, body)

    def parse_return(self) -> ReturnStmt:
        self.advance()  # YEET
        self.expect(TokenType.LBRACE)
        value = self.parse_expression()
        self.expect(TokenType.RBRACE)
        return ReturnStmt(value)

    def parse_block(self) -> List[ASTNode]:
        statements = []
        while self.peek().type not in (TokenType.BLOCK_END, TokenType.ELSE, TokenType.EOF):
            stmt = self.parse_statement()
            if stmt:
                statements.append(stmt)
        if self.peek().type == TokenType.BLOCK_END:
            self.advance()
        return statements

    def parse_expression(self) -> ASTNode:
        return self.parse_or()

    def parse_or(self) -> ASTNode:
        left = self.parse_and()
        while self.match(TokenType.OR):
            right = self.parse_and()
            left = BinaryOp(left, '||', right)
        return left

    def parse_and(self) -> ASTNode:
        left = self.parse_equality()
        while self.match(TokenType.AND):
            right = self.parse_equality()
            left = BinaryOp(left, '&&', right)
        return left

    def parse_equality(self) -> ASTNode:
        left = self.parse_comparison()
        while True:
            if self.match(TokenType.EQ):
                left = BinaryOp(left, '==', self.parse_comparison())
            elif self.match(TokenType.NEQ):
                left = BinaryOp(left, '!=', self.parse_comparison())
            else:
                break
        return left

    def parse_comparison(self) -> ASTNode:
        left = self.parse_additive()
        while True:
            if self.match(TokenType.LT):
                left = BinaryOp(left, '<', self.parse_additive())
            elif self.match(TokenType.GT):
                left = BinaryOp(left, '>', self.parse_additive())
            else:
                break
        return left

    def parse_additive(self) -> ASTNode:
        left = self.parse_multiplicative()
        while True:
            if self.match(TokenType.ADD):
                left = BinaryOp(left, '+', self.parse_multiplicative())
            elif self.match(TokenType.SUB):
                left = BinaryOp(left, '-', self.parse_multiplicative())
            else:
                break
        return left

    def parse_multiplicative(self) -> ASTNode:
        left = self.parse_unary()
        while True:
            if self.match(TokenType.MUL):
                left = BinaryOp(left, '*', self.parse_unary())
            elif self.match(TokenType.DIV):
                left = BinaryOp(left, '/', self.parse_unary())
            elif self.match(TokenType.MOD):
                left = BinaryOp(left, '%', self.parse_unary())
            else:
                break
        return left

    def parse_unary(self) -> ASTNode:
        if self.match(TokenType.NOT):
            return UnaryOp('!', self.parse_unary())
        return self.parse_primary()

    def parse_primary(self) -> ASTNode:
        if self.match(TokenType.LPAREN):
            expr = self.parse_expression()
            self.expect(TokenType.RPAREN)
            return expr

        if token := self.match(TokenType.NUMBER):
            return Literal(token.value)
        if token := self.match(TokenType.STRING):
            return Literal(token.value)
        if self.match(TokenType.TRUE):
            return Literal(True)
        if self.match(TokenType.FALSE):
            return Literal(False)
        if self.match(TokenType.NIL):
            return Literal(None)

        if self.match(TokenType.INPUT):
            self.expect(TokenType.ACTION)
            self.expect(TokenType.GRAB)
            self.expect(TokenType.LPAREN)
            prompt = self.parse_expression()
            self.expect(TokenType.RPAREN)
            return InputExpr(prompt)

        if self.match(TokenType.INVOKE):
            self.expect(TokenType.LBRACE)
            name = self.expect(TokenType.IDENTIFIER).value
            self.expect(TokenType.RBRACE)
            self.expect(TokenType.ACTION)
            self.expect(TokenType.WITH)
            self.expect(TokenType.LPAREN)
            args = []
            if self.peek().type != TokenType.RPAREN:
                args.append(self.parse_expression())
                while self.match(TokenType.COMMA):
                    args.append(self.parse_expression())
            self.expect(TokenType.RPAREN)
            return FuncCall(name, args)

        if token := self.match(TokenType.IDENTIFIER):
            return VarRef(token.value)

        raise SyntaxError(f"Unexpected token: {self.peek().type}")

    def parse_inline_expr(self, text: str) -> ASTNode:
        """Parse an inline expression from WHEN/LOOP conditions"""
        lexer = Lexer(text)
        tokens = lexer.tokenize()
        parser = Parser(tokens)
        return parser.parse_expression()
