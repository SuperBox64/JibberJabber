"""
JibJab Lexer - Tokenizes JJ source code
Uses shared language definition from common/jj.json
"""

import re
import json
import os
from typing import Any, List, Optional
from dataclasses import dataclass
from enum import Enum, auto


class TokenType(Enum):
    # Keywords
    PRINT = auto()
    INPUT = auto()
    LOOP = auto()
    WHEN = auto()
    ELSE = auto()
    MORPH = auto()
    YEET = auto()
    SNAG = auto()
    INVOKE = auto()
    ENUM = auto()
    TRY = auto()
    OOPS = auto()
    BLOCK_END = auto()

    # Operators
    ADD = auto()
    SUB = auto()
    MUL = auto()
    DIV = auto()
    MOD = auto()
    EQ = auto()
    NEQ = auto()
    LT = auto()
    LTE = auto()
    GT = auto()
    GTE = auto()
    AND = auto()
    OR = auto()
    NOT = auto()

    # Literals
    NUMBER = auto()
    STRING = auto()
    ARRAY = auto()
    MAP = auto()
    NIL = auto()
    TRUE = auto()
    FALSE = auto()

    # Structure
    ACTION = auto()
    EMIT = auto()
    GRAB = auto()
    VAL = auto()
    WITH = auto()
    CASES = auto()
    RANGE = auto()
    COLON = auto()
    LPAREN = auto()
    RPAREN = auto()
    LBRACKET = auto()
    RBRACKET = auto()
    LBRACE = auto()
    RBRACE = auto()
    COMMA = auto()

    # Other
    IDENTIFIER = auto()
    COMMENT = auto()
    NEWLINE = auto()
    EOF = auto()


@dataclass
class Token:
    type: TokenType
    value: Any
    line: int
    col: int


def load_jj_config():
    """Load language definition from common/jj.json"""
    config_paths = [
        os.path.join(os.path.dirname(__file__), '..', '..', 'common', 'jj.json'),
        os.path.join(os.path.dirname(__file__), '..', '..', '..', 'common', 'jj.json'),
    ]
    for path in config_paths:
        if os.path.exists(path):
            with open(path) as f:
                return json.load(f)
    raise FileNotFoundError("Could not find common/jj.json")


# Load config at module level
JJ = load_jj_config()


def _extract_keyword_names():
    """Extract keyword names from jj.json (e.g. 'frob' from '~>frob{7a3}', 'snag' from '~>snag')"""
    names = []
    for kw in JJ['keywords'].values():
        if not kw.startswith('~>'):
            continue
        name = kw[2:]
        brace = name.find('{')
        names.append(name[:brace] if brace >= 0 else name)
    return names


def _lcs_length(a: str, b: str) -> int:
    """Longest common subsequence length"""
    m, n = len(a), len(b)
    dp = [[0] * (n + 1) for _ in range(m + 1)]
    for i in range(1, m + 1):
        for j in range(1, n + 1):
            if a[i-1] == b[j-1]:
                dp[i][j] = dp[i-1][j-1] + 1
            else:
                dp[i][j] = max(dp[i-1][j], dp[i][j-1])
    return dp[m][n]


def _closest_keyword(input_kw: str) -> Optional[str]:
    """Find the closest valid keyword using longest common subsequence"""
    candidates = _extract_keyword_names()
    input_lower = input_kw.lower()
    best, best_score = None, 0
    for c in candidates:
        score = _lcs_length(input_lower, c.lower())
        if score > best_score and score >= 2:
            best_score = score
            best = c
    return best


def load_target_config(target: str):
    """Load target config from common/targets/{target}.json"""
    target_paths = [
        os.path.join(os.path.dirname(__file__), '..', '..', 'common', 'targets', f'{target}.json'),
        os.path.join(os.path.dirname(__file__), '..', '..', '..', 'common', 'targets', f'{target}.json'),
    ]
    for path in target_paths:
        if os.path.exists(path):
            with open(path) as f:
                return json.load(f)
    raise FileNotFoundError(f"Could not find common/targets/{target}.json")


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
        if self.match(JJ['literals']['comment']):
            while self.peek() and self.peek() != '\n':
                self.advance()
            return

        # Newlines
        if self.peek() == '\n':
            self.advance()
            self.add_token(TokenType.NEWLINE)
            return

        # Keywords
        if self.match(JJ['keywords']['print']):
            self.add_token(TokenType.PRINT)
            return
        if self.match(JJ['keywords']['input']):
            self.add_token(TokenType.INPUT)
            return
        if self.match(JJ['keywords']['yeet']):
            self.add_token(TokenType.YEET)
            return
        if self.match(JJ['keywords']['snag']):
            self.add_token(TokenType.SNAG)
            return
        if self.match(JJ['keywords']['invoke']):
            self.add_token(TokenType.INVOKE)
            return
        if self.match(JJ['keywords']['enum']):
            self.add_token(TokenType.ENUM)
            return
        if self.match(JJ['keywords']['nil']):
            self.add_token(TokenType.NIL)
            return
        if self.match(JJ['keywords']['true']):
            self.add_token(TokenType.TRUE)
            return
        if self.match(JJ['keywords']['false']):
            self.add_token(TokenType.FALSE)
            return

        # Catch malformed JJ action keywords (e.g. ~>frob33333{7a3} or ~>fr999ob{7aww3})
        # Must come after valid keyword checks. Consume the rest of the line.
        if self.source[self.pos:].startswith('~>'):
            m = self.match_regex(r'~>[a-zA-Z0-9]+\{[^}]*\}[^\n]*')
            if m:
                # Extract keyword and hash, validate each against known values
                after_arrow = m[2:]  # remove "~>"
                brace_idx = after_arrow.index('{')
                keyword = after_arrow[:brace_idx]
                hash_val = after_arrow[brace_idx+1:after_arrow.index('}')]
                valid_hashes = JJ.get('validHashes', {})
                if keyword in valid_hashes:
                    msg = f"Invalid hash '{{{hash_val}}}' for keyword '~>{keyword}' (expected '{{{valid_hashes[keyword]}}}')"
                else:
                    hint = _closest_keyword(keyword)
                    if hint:
                        msg = f"Unknown keyword '~>{keyword}{{{hash_val}}}', did you mean '~>{hint}'?"
                    else:
                        msg = f"Unknown keyword '~>{keyword}{{{hash_val}}}'"
                self.add_token(TokenType.IDENTIFIER, msg)
                return

        # Block structures
        loop_prefix = JJ['blocks']['loop']
        when_prefix = JJ['blocks']['when']
        morph_prefix = JJ['blocks']['morph']
        block_suffix = JJ['blockSuffix']

        if m := self.match_regex(rf'{re.escape(loop_prefix)}([^}}]*){re.escape(block_suffix)}'):
            content = m[len(loop_prefix):-len(block_suffix)]
            self.add_token(TokenType.LOOP, content)
            return
        if m := self.match_regex(rf'{re.escape(when_prefix)}([^}}]*){re.escape(block_suffix)}'):
            content = m[len(when_prefix):-len(block_suffix)]
            self.add_token(TokenType.WHEN, content)
            return
        if self.match(JJ['blocks']['else']):
            self.add_token(TokenType.ELSE)
            return
        if m := self.match_regex(rf'{re.escape(morph_prefix)}([^}}]*){re.escape(block_suffix)}'):
            content = m[len(morph_prefix):-len(block_suffix)]
            self.add_token(TokenType.MORPH, content)
            return
        if self.match(JJ['blocks']['try']):
            self.add_token(TokenType.TRY)
            return
        if self.match(JJ['blocks']['oops']):
            self.add_token(TokenType.OOPS)
            return
        if self.match(JJ['blocks']['end']):
            self.add_token(TokenType.BLOCK_END)
            return

        # Operators (now have symbol/emit format)
        if self.match(JJ['operators']['add']['symbol']):
            self.add_token(TokenType.ADD)
            return
        if self.match(JJ['operators']['sub']['symbol']):
            self.add_token(TokenType.SUB)
            return
        if self.match(JJ['operators']['mul']['symbol']):
            self.add_token(TokenType.MUL)
            return
        if self.match(JJ['operators']['div']['symbol']):
            self.add_token(TokenType.DIV)
            return
        if self.match(JJ['operators']['mod']['symbol']):
            self.add_token(TokenType.MOD)
            return
        if self.match(JJ['operators']['neq']['symbol']):
            self.add_token(TokenType.NEQ)
            return
        if self.match(JJ['operators']['eq']['symbol']):
            self.add_token(TokenType.EQ)
            return
        if self.match(JJ['operators']['lte']['symbol']):
            self.add_token(TokenType.LTE)
            return
        if self.match(JJ['operators']['lt']['symbol']):
            self.add_token(TokenType.LT)
            return
        if self.match(JJ['operators']['gte']['symbol']):
            self.add_token(TokenType.GTE)
            return
        if self.match(JJ['operators']['gt']['symbol']):
            self.add_token(TokenType.GT)
            return
        if self.match(JJ['operators']['and']['symbol']):
            self.add_token(TokenType.AND)
            return
        if self.match(JJ['operators']['or']['symbol']):
            self.add_token(TokenType.OR)
            return
        if self.match(JJ['operators']['not']['symbol']):
            self.add_token(TokenType.NOT)
            return

        # Structure
        if self.match(JJ['structure']['action']):
            self.add_token(TokenType.ACTION)
            return
        if self.match(JJ['structure']['range']):
            self.add_token(TokenType.RANGE)
            return
        if self.match(JJ['structure']['colon']):
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
        if self.peek() == JJ['literals']['numberPrefix']:
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
        if self.peek() == JJ['literals']['stringDelim']:
            self.advance()
            value = ''
            while self.peek() and self.peek() != JJ['literals']['stringDelim']:
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

        # Syntax keywords
        if self.match(JJ['syntax']['emit']):
            self.add_token(TokenType.EMIT)
            return
        if self.match(JJ['syntax']['grab']):
            self.add_token(TokenType.GRAB)
            return
        if self.match(JJ['syntax']['val']):
            self.add_token(TokenType.VAL)
            return
        if self.match(JJ['syntax']['with']):
            self.add_token(TokenType.WITH)
            return
        if self.match(JJ['syntax']['cases']):
            self.add_token(TokenType.CASES)
            return

        # Identifiers
        if m := self.match_regex(r'[a-zA-Z_][a-zA-Z0-9_]*'):
            self.add_token(TokenType.IDENTIFIER, m)
            return

        # Unknown - skip
        self.advance()
