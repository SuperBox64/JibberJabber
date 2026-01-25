# JibJab Implementation Details

This directory contains the complete JibJab language implementation with two interpreters (Swift and Python), a shared language definition, and example programs.

---

## Directory Structure

```
jibjab/
├── common/
│   └── jj.json              # Shared language definition (tokens, operators, transpiler templates)
│
├── jjswift/                 # Swift implementation
│   ├── Package.swift        # Swift package manifest
│   └── Sources/jjswift/
│       ├── main.swift       # CLI entry point
│       └── JJ/
│           ├── Lexer.swift      # Tokenization
│           ├── Token.swift      # Token types
│           ├── AST.swift        # AST node definitions
│           ├── Parser.swift     # Recursive descent parser
│           ├── Interpreter.swift # Direct execution
│           ├── JJConfig.swift   # Configuration loader
│           └── Transpilers/
│               ├── PythonTranspiler.swift
│               ├── JavaScriptTranspiler.swift
│               ├── CTranspiler.swift
│               └── AssemblyTranspiler.swift
│
├── jjpy/                    # Python implementation
│   ├── jj.py                # CLI entry point
│   └── jj/
│       ├── __init__.py      # Package exports
│       ├── lexer.py         # Tokenization
│       ├── ast.py           # AST node definitions
│       ├── parser.py        # Recursive descent parser
│       ├── interpreter.py   # Direct execution
│       └── transpilers/
│           ├── __init__.py
│           ├── python.py
│           ├── javascript.py
│           ├── c.py
│           └── asm.py       # ARM64 Assembly (macOS)
│
├── examples/                # Example JJ programs
│   ├── hello.jj
│   ├── variables.jj
│   ├── fibonacci.jj
│   └── fizzbuzz.jj
│
├── README.md                # This file
└── SPEC.md                  # Complete language specification
```

---

## Quick Start

### Using Swift (`jjswift`)

```bash
cd jjswift

# Build
swift build -c release

# Run examples
swift run jjswift run ../examples/hello.jj
swift run jjswift run ../examples/fibonacci.jj

# Transpile
swift run jjswift transpile ../examples/fibonacci.jj py    # Python
swift run jjswift transpile ../examples/fibonacci.jj js    # JavaScript
swift run jjswift transpile ../examples/fibonacci.jj c     # C
swift run jjswift transpile ../examples/fibonacci.jj asm   # ARM64 Assembly
```

### Using Python (`jjpy`)

```bash
cd jjpy

# Run examples
python3 jj.py run ../examples/hello.jj
python3 jj.py run ../examples/fibonacci.jj

# Transpile
python3 jj.py transpile ../examples/fibonacci.jj py    # Python
python3 jj.py transpile ../examples/fibonacci.jj js    # JavaScript
python3 jj.py transpile ../examples/fibonacci.jj c     # C
python3 jj.py transpile ../examples/fibonacci.jj asm   # ARM64 Assembly
```

---

## Common Language Definition (`common/jj.json`)

The `jj.json` file defines the entire JibJab language in a structured format that both implementations read:

### Keywords
```json
{
  "keywords": {
    "print": "~>frob{7a3}",
    "input": "~>slurp{9f2}",
    "yeet": "~>yeet",
    "snag": "~>snag",
    "invoke": "~>invoke",
    "nil": "~nil",
    "true": "~yep",
    "false": "~nope"
  }
}
```

### Block Structures
```json
{
  "blocks": {
    "loop": "<~loop{",
    "when": "<~when{",
    "else": "<~else>>",
    "morph": "<~morph{",
    "end": "<~>>"
  },
  "blockSuffix": "}>>"
}
```

### Operators
```json
{
  "operators": {
    "add": {"symbol": "<+>", "emit": "+"},
    "sub": {"symbol": "<->", "emit": "-"},
    "mul": {"symbol": "<*>", "emit": "*"},
    "div": {"symbol": "</>", "emit": "/"},
    "mod": {"symbol": "<%>", "emit": "%"},
    "eq":  {"symbol": "<=>", "emit": "=="},
    "neq": {"symbol": "<!=>", "emit": "!="},
    "lt":  {"symbol": "<lt>", "emit": "<"},
    "gt":  {"symbol": "<gt>", "emit": ">"},
    "and": {"symbol": "<&&>", "emit": "&&"},
    "or":  {"symbol": "<||>", "emit": "||"},
    "not": {"symbol": "<!>", "emit": "!"}
  }
}
```

### Transpilation Targets
Each target language has templates for code generation:
```json
{
  "targets": {
    "py": {
      "print": "print({expr})",
      "var": "{name} = {value}",
      "forRange": "for {var} in range({start}, {end}):",
      "if": "if {condition}:",
      "func": "def {name}({params}):"
    },
    "js": { ... },
    "c": { ... }
  }
}
```

---

## How the Pipeline Works

### 1. Lexer (Tokenization)

Reads source code character by character and produces tokens:

```
Input:  "~>snag{x}::val(#42)"
Output: [SNAG, LBRACE, IDENTIFIER("x"), RBRACE, ACTION, VAL, LPAREN, NUMBER(42), RPAREN]
```

**Files:** `jjswift/Sources/jjswift/JJ/Lexer.swift`, `jjpy/jj/lexer.py`

### 2. Parser (AST Construction)

Takes tokens and builds an Abstract Syntax Tree:

```
Tokens: [SNAG, LBRACE, IDENTIFIER("x"), RBRACE, ACTION, VAL, LPAREN, NUMBER(42), RPAREN]
AST:    VarDecl(name="x", value=Literal(42))
```

**Files:** `jjswift/Sources/jjswift/JJ/Parser.swift`, `jjpy/jj/parser.py`

### 3. Interpreter (Direct Execution)

Walks the AST and executes each node:

```
VarDecl(name="x", value=Literal(42))
  → Store 42 in variable "x"
```

**Files:** `jjswift/Sources/jjswift/JJ/Interpreter.swift`, `jjpy/jj/interpreter.py`

### 4. Transpilers (Code Generation)

Walks the AST and generates target language code:

```
VarDecl(name="x", value=Literal(42))
  → Python: "x = 42"
  → JavaScript: "let x = 42;"
  → C: "int x = 42;"
```

**Files:** `jjswift/Sources/jjswift/JJ/Transpilers/*.swift`, `jjpy/jj/transpilers/*.py`

---

## Test Results

All examples pass on both implementations across all targets:

| Example | Swift Interp | Python Interp | Python | JavaScript | C | ARM64 ASM |
|---------|:------------:|:-------------:|:------:|:----------:|:-:|:---------:|
| hello.jj | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| variables.jj | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| fibonacci.jj | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| fizzbuzz.jj | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Running Transpiled Code

### Python
```bash
swift run jjswift transpile ../examples/fibonacci.jj py > /tmp/fib.py
python3 /tmp/fib.py
```

### JavaScript
```bash
swift run jjswift transpile ../examples/fibonacci.jj js > /tmp/fib.js
node /tmp/fib.js
```

### C
```bash
swift run jjswift transpile ../examples/fibonacci.jj c > /tmp/fib.c
clang /tmp/fib.c -o /tmp/fib
/tmp/fib
```

### ARM64 Assembly (macOS)
```bash
swift run jjswift transpile ../examples/fibonacci.jj asm > /tmp/fib.s
clang /tmp/fib.s -o /tmp/fib
/tmp/fib
```

---

## Language Reference

### Statements

| JibJab | Meaning | Example |
|--------|---------|---------|
| `~>frob{7a3}::emit(expr)` | Print | `~>frob{7a3}::emit("Hello")` |
| `~>snag{name}::val(expr)` | Variable | `~>snag{x}::val(#10)` |
| `<~loop{var:start..end}>>` | For loop | `<~loop{i:0..10}>>` |
| `<~when{cond}>>` | If | `<~when{x <gt> #5}>>` |
| `<~else>>` | Else | `<~else>>` |
| `<~>>` | End block | `<~>>` |
| `<~morph{name(params)}>>` | Function | `<~morph{add(a,b)}>>` |
| `~>invoke{name}::with(args)` | Call | `~>invoke{add}::with(#1, #2)` |
| `~>yeet{expr}` | Return | `~>yeet{result}` |

### Operators

| JibJab | Operation |
|--------|-----------|
| `<+>` `<->` `<*>` `</>` `<%>` | Math |
| `<=>` `<!=>` `<lt>` `<gt>` | Comparison |
| `<&&>` `<\|\|>` `<!>` | Logic |

### Literals

| JibJab | Type |
|--------|------|
| `#42` | Integer |
| `#3.14` | Float |
| `"text"` | String |
| `~yep` | True |
| `~nope` | False |
| `~nil` | Null |
| `@@` | Comment |

---

## See Also

- [SPEC.md](SPEC.md) - Complete language specification
- [common/jj.json](common/jj.json) - Language definition file
- [examples/](examples/) - Example programs
