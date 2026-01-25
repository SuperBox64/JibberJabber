"""
JibJab Lexer - Tokenizes JJ source code
"""

import re
from typing import Any, List, Optional
from dataclasses import dataclass
from enum import Enum, auto


class TokenType(Enum):
    # Keywords
    PRINT = auto()      # ~>frob{7a3}
    INPUT = auto()      # ~>slurp{9f2}
    LOOP = auto()       # <~loop{...}>>
    WHEN = auto()       # <~when{...}>>
    ELSE = auto()       # <~else>>
    MORPH = auto()      # <~morph{...}>>
    YEET = auto()       # ~>yeet{...}
    SNAG = auto()       # ~>snag{...}
    INVOKE = auto()     # ~>invoke{...}
    TRY = auto()        # <~try>>
    OOPS = auto()       # <~oops>>
    BLOCK_END = auto()  # <~>>

    # Operators
    ADD = auto()        # <+>
    SUB = auto()        # <->
    MUL = auto()        # <*>
    DIV = auto()        # </>
    MOD = auto()        # <%>
    EQ = auto()         # <=>
    NEQ = auto()        # <!=>
    LT = auto()         # <lt>
    GT = auto()         # <gt>
    AND = auto()        # <&&>
    OR = auto()         # <||>
    NOT = auto()        # <!>

    # Literals
    NUMBER = auto()     # #42 or #3.14
    STRING = auto()     # "..."
    ARRAY = auto()      # [...]
    MAP = auto()        # {...}
    NIL = auto()        # ~nil
    TRUE = auto()       # ~yep
    FALSE = auto()      # ~nope

    # Structure
    ACTION = auto()     # ::
    EMIT = auto()       # emit
    GRAB = auto()       # grab
    VAL = auto()        # val
    WITH = auto()       # with
    RANGE = auto()      # ..
    COLON = auto()      # :
    LPAREN = auto()     # (
    RPAREN = auto()     # )
    LBRACKET = auto()   # [
    RBRACKET = auto()   # ]
    LBRACE = auto()     # {
    RBRACE = auto()     # }
    COMMA = auto()      # ,

    # Other
    IDENTIFIER = auto()
    COMMENT = auto()    # @@
    NEWLINE = auto()
    EOF = auto()


@dataclass
class Token:
    type: TokenType
    value: Any
    line: int
    col: int


class Lexer:
    def __init__(self, source: str):
        self.source = source
        self.pos = 0
        self.line = 1
        self.col = 1
        self.tokens: List[Token] = []

    def peek(self, offset: int = 0) -> str:
        pos = self.pos + offset
        return self.source[pos] if pos < len(self.source) else ''

    def advance(self, count: int = 1) -> str:
        result = self.source[self.pos:self.pos + count]
        for ch in result:
            if ch == '\n':
                self.line += 1
                self.col = 1
            else:
                self.col += 1
        self.pos += count
        return result

    def match(self, pattern: str) -> Optional[str]:
        if self.source[self.pos:].startswith(pattern):
            return self.advance(len(pattern))
        return None

    def match_regex(self, pattern: str) -> Optional[str]:
        match = re.match(pattern, self.source[self.pos:])
        if match:
            return self.advance(len(match.group(0)))
        return None

    def add_token(self, type: TokenType, value: Any = None):
        self.tokens.append(Token(type, value, self.line, self.col))

    def tokenize(self) -> List[Token]:
        while self.pos < len(self.source):
            self.scan_token()
        self.add_token(TokenType.EOF)
        return self.tokens

    def scan_token(self):
        # Skip whitespace (except newlines)
        while self.peek() in ' \t\r':
            self.advance()

        if self.pos >= len(self.source):
            return

        # Comments
        if self.match('@@'):
            while self.peek() and self.peek() != '\n':
                self.advance()
            return

        # Newlines
        if self.peek() == '\n':
            self.advance()
            self.add_token(TokenType.NEWLINE)
            return

        # Keywords and special tokens
        if self.match('~>frob{7a3}'):
            self.add_token(TokenType.PRINT)
            return
        if self.match('~>slurp{9f2}'):
            self.add_token(TokenType.INPUT)
            return
        if self.match('~>yeet'):
            self.add_token(TokenType.YEET)
            return
        if self.match('~>snag'):
            self.add_token(TokenType.SNAG)
            return
        if self.match('~>invoke'):
            self.add_token(TokenType.INVOKE)
            return
        if self.match('~nil'):
            self.add_token(TokenType.NIL)
            return
        if self.match('~yep'):
            self.add_token(TokenType.TRUE)
            return
        if self.match('~nope'):
            self.add_token(TokenType.FALSE)
            return

        # Block structures
        if m := self.match_regex(r'<~loop\{([^}]*)\}>>'):
            self.add_token(TokenType.LOOP, m[7:-3])
            return
        if m := self.match_regex(r'<~when\{([^}]*)\}>>'):
            content = m[7:-3]
            self.add_token(TokenType.WHEN, content)
            return
        if self.match('<~else>>'):
            self.add_token(TokenType.ELSE)
            return
        if m := self.match_regex(r'<~morph\{([^}]*)\}>>'):
            self.add_token(TokenType.MORPH, m[8:-3])
            return
        if self.match('<~try>>'):
            self.add_token(TokenType.TRY)
            return
        if self.match('<~oops>>'):
            self.add_token(TokenType.OOPS)
            return
        if self.match('<~>>'):
            self.add_token(TokenType.BLOCK_END)
            return

        # Operators
        if self.match('<+>'):
            self.add_token(TokenType.ADD)
            return
        if self.match('<->'):
            self.add_token(TokenType.SUB)
            return
        if self.match('<*>'):
            self.add_token(TokenType.MUL)
            return
        if self.match('</>'):
            self.add_token(TokenType.DIV)
            return
        if self.match('<%>'):
            self.add_token(TokenType.MOD)
            return
        if self.match('<!=>'):
            self.add_token(TokenType.NEQ)
            return
        if self.match('<=>'):
            self.add_token(TokenType.EQ)
            return
        if self.match('<lt>'):
            self.add_token(TokenType.LT)
            return
        if self.match('<gt>'):
            self.add_token(TokenType.GT)
            return
        if self.match('<&&>'):
            self.add_token(TokenType.AND)
            return
        if self.match('<||>'):
            self.add_token(TokenType.OR)
            return
        if self.match('<!>'):
            self.add_token(TokenType.NOT)
            return

        # Structure
        if self.match('::'):
            self.add_token(TokenType.ACTION)
            return
        if self.match('..'):
            self.add_token(TokenType.RANGE)
            return
        if self.match(':'):
            self.add_token(TokenType.COLON)
            return

        # Single characters
        simple = {
            '(': TokenType.LPAREN,
            ')': TokenType.RPAREN,
            '[': TokenType.LBRACKET,
            ']': TokenType.RBRACKET,
            '{': TokenType.LBRACE,
            '}': TokenType.RBRACE,
            ',': TokenType.COMMA,
        }
        if self.peek() in simple:
            self.add_token(simple[self.advance()])
            return

        # Numbers (with # prefix for JJ syntax)
        if self.peek() == '#':
            self.advance()
            num = self.match_regex(r'-?\d+\.?\d*')
            if num:
                if '.' in num:
                    self.add_token(TokenType.NUMBER, float(num))
                else:
                    self.add_token(TokenType.NUMBER, int(num))
                return

        # Plain numbers (for inline expressions)
        if self.peek().isdigit() or (self.peek() == '-' and self.source[self.pos+1:self.pos+2].isdigit()):
            num = self.match_regex(r'-?\d+\.?\d*')
            if num:
                if '.' in num:
                    self.add_token(TokenType.NUMBER, float(num))
                else:
                    self.add_token(TokenType.NUMBER, int(num))
                return

        # Strings
        if self.peek() == '"':
            self.advance()
            value = ''
            while self.peek() and self.peek() != '"':
                if self.peek() == '\\':
                    self.advance()
                    escapes = {'n': '\n', 't': '\t', 'r': '\r', '"': '"', '\\': '\\'}
                    value += escapes.get(self.peek(), self.peek())
                    self.advance()
                else:
                    value += self.advance()
            self.advance()  # closing quote
            self.add_token(TokenType.STRING, value)
            return

        # Keywords
        if self.match('emit'):
            self.add_token(TokenType.EMIT)
            return
        if self.match('grab'):
            self.add_token(TokenType.GRAB)
            return
        if self.match('val'):
            self.add_token(TokenType.VAL)
            return
        if self.match('with'):
            self.add_token(TokenType.WITH)
            return

        # Identifiers
        if m := self.match_regex(r'[a-zA-Z_][a-zA-Z0-9_]*'):
            self.add_token(TokenType.IDENTIFIER, m)
            return

        # Unknown - skip
        self.advance()
