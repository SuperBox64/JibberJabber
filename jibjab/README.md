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
│               ├── CppTranspiler.swift
│               ├── AssemblyTranspiler.swift
│               ├── SwiftTranspiler.swift
│               ├── AppleScriptTranspiler.swift
│               ├── ObjCTranspiler.swift
│               └── ObjCppTranspiler.swift
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
│           ├── cpp.py
│           ├── asm.py       # ARM64 Assembly (macOS)
│           ├── swift.py
│           ├── applescript.py
│           ├── objc.py
│           └── objcpp.py
│
├── examples/                # Example JJ programs
│   ├── hello.jj
│   ├── variables.jj
│   ├── fibonacci.jj
│   └── fizzbuzz.jj
│
├── output/                  # Pre-built transpiled code and binaries
│   ├── jjpy/                # Output from Python implementation (jjpy)
│   │   ├── *.c, *.cpp, *.js, *.py, *.s, *.swift, *.applescript, *.m, *.mm
│   │   ├── *_c              # C binaries (~33KB)
│   │   ├── *_cpp            # C++ binaries (~33KB)
│   │   ├── *_asm            # ARM64 Assembly binaries (~49KB)
│   │   ├── *_swift          # Swift binaries (~50KB)
│   │   ├── *_objc           # Objective-C binaries (~33KB)
│   │   ├── *_objcpp         # Objective-C++ binaries (~33KB)
│   │   ├── *_qjs            # QuickJS JavaScript binaries (~722KB)
│   │   └── *_py             # PyInstaller Python binaries (~3.4MB)
│   └── jjswift/             # Output from Swift implementation (jjswift)
│       ├── *.c, *.cpp, *.js, *.py, *.s, *.swift, *.applescript, *.m, *.mm
│       ├── *_c              # C binaries (~33KB)
│       ├── *_cpp            # C++ binaries (~33KB)
│       ├── *_asm            # ARM64 Assembly binaries (~49KB)
│       ├── *_swift          # Swift binaries (~50KB)
│       ├── *_objc           # Objective-C binaries (~33KB)
│       ├── *_objcpp         # Objective-C++ binaries (~33KB)
│       ├── *_qjs            # QuickJS JavaScript binaries (~722KB)
│       └── *_py             # PyInstaller Python binaries (~3.4MB)
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
swift run jjswift transpile ../examples/fibonacci.jj py          # Python
swift run jjswift transpile ../examples/fibonacci.jj js          # JavaScript
swift run jjswift transpile ../examples/fibonacci.jj c           # C
swift run jjswift transpile ../examples/fibonacci.jj cpp         # C++
swift run jjswift transpile ../examples/fibonacci.jj asm         # ARM64 Assembly
swift run jjswift transpile ../examples/fibonacci.jj swift       # Swift
swift run jjswift transpile ../examples/fibonacci.jj applescript # AppleScript
swift run jjswift transpile ../examples/fibonacci.jj objc        # Objective-C
swift run jjswift transpile ../examples/fibonacci.jj objcpp      # Objective-C++
```

### Using Python (`jjpy`)

```bash
cd jjpy

# Run examples
python3 jj.py run ../examples/hello.jj
python3 jj.py run ../examples/fibonacci.jj

# Transpile
python3 jj.py transpile ../examples/fibonacci.jj py          # Python
python3 jj.py transpile ../examples/fibonacci.jj js          # JavaScript
python3 jj.py transpile ../examples/fibonacci.jj c           # C
python3 jj.py transpile ../examples/fibonacci.jj cpp         # C++
python3 jj.py transpile ../examples/fibonacci.jj asm         # ARM64 Assembly
python3 jj.py transpile ../examples/fibonacci.jj swift       # Swift
python3 jj.py transpile ../examples/fibonacci.jj applescript # AppleScript
python3 jj.py transpile ../examples/fibonacci.jj objc        # Objective-C
python3 jj.py transpile ../examples/fibonacci.jj objcpp      # Objective-C++
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
    "try": "<~try>>",
    "oops": "<~oops>>",
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

### Structure & Syntax
```json
{
  "structure": {
    "action": "::",
    "range": "..",
    "colon": ":"
  },
  "syntax": {
    "emit": "emit",
    "grab": "grab",
    "val": "val",
    "with": "with"
  },
  "literals": {
    "numberPrefix": "#",
    "stringDelim": "\"",
    "comment": "@@"
  }
}
```

### Transpilation Targets
Each target language (py, js, c, swift) has templates for code generation:
```json
{
  "targets": {
    "py": {
      "name": "Python",
      "ext": ".py",
      "header": "#!/usr/bin/env python3\n# Transpiled from JibJab\n",
      "print": "print({expr})",
      "var": "{name} = {value}",
      "forRange": "for {var} in range({start}, {end}):",
      "if": "if {condition}:",
      "else": "else:",
      "func": "def {name}({params}):",
      "return": "return {value}",
      "call": "{name}({args})",
      "indent": "    ",
      "true": "True",
      "false": "False",
      "nil": "None"
    }
  }
}
```
See `common/jj.json` for complete templates for all targets (py, js, c, swift).

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
  → Swift: "var x = 42"
```

**Files:** `jjswift/Sources/jjswift/JJ/Transpilers/*.swift`, `jjpy/jj/transpilers/*.py`

---

## Test Results

All examples pass on both implementations across all targets:

| Example | Swift Interp | Python Interp | Python | JavaScript | C | C++ | ARM64 ASM | Swift | AppleScript | Obj-C | Obj-C++ |
|---------|:------------:|:-------------:|:------:|:----------:|:-:|:---:|:---------:|:-----:|:-----------:|:-----:|:-------:|
| hello.jj | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| variables.jj | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| fibonacci.jj | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| fizzbuzz.jj | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Creating Standalone Binaries

You can create standalone executables from transpiled code. Here's the size comparison:

| Target | Size | Tool |
|--------|------|------|
| C | ~33KB | gcc/clang |
| C++ | ~33KB | g++/clang++ |
| Objective-C | ~33KB | clang |
| Objective-C++ | ~33KB | clang++ |
| ARM64 Assembly | ~49KB | as + ld |
| Swift | ~100KB | swiftc |
| JavaScript | ~722KB | QuickJS |
| Python | ~3.4MB | PyInstaller |

### Prerequisites (macOS)

C, Assembly, and Swift compilation require Xcode Command Line Tools:

```bash
# Install Xcode Command Line Tools (includes gcc, clang, as, ld, swiftc)
xcode-select --install
```

### C Binaries

```bash
# Step 1: Transpile JJ to C
swift run jjswift transpile ../examples/fibonacci.jj c > fib.c

# Step 2: Compile C to binary
gcc -o fib_c fib.c

# Step 3: Run the binary
./fib_c
```

### C++ Binaries

```bash
# Step 1: Transpile JJ to C++
swift run jjswift transpile ../examples/fibonacci.jj cpp > fib.cpp

# Step 2: Compile C++ to binary
g++ -o fib_cpp fib.cpp

# Step 3: Run the binary
./fib_cpp
```

### Objective-C Binaries

```bash
# Step 1: Transpile JJ to Objective-C
swift run jjswift transpile ../examples/fibonacci.jj objc > fib.m

# Step 2: Compile Objective-C to binary
clang -framework Foundation -o fib_objc fib.m

# Step 3: Run the binary
./fib_objc
```

### Objective-C++ Binaries

```bash
# Step 1: Transpile JJ to Objective-C++
swift run jjswift transpile ../examples/fibonacci.jj objcpp > fib.mm

# Step 2: Compile Objective-C++ to binary
clang++ -framework Foundation -o fib_objcpp fib.mm

# Step 3: Run the binary
./fib_objcpp
```

### ARM64 Assembly Binaries (macOS)

```bash
# Step 1: Transpile JJ to Assembly
swift run jjswift transpile ../examples/fibonacci.jj asm > fib.s

# Step 2: Assemble to object file
as -o fib.o fib.s

# Step 3: Link to binary
ld -o fib_asm fib.o -lSystem -syslibroot $(xcrun -sdk macosx --show-sdk-path) -e _main -arch arm64

# Step 4: Run the binary
./fib_asm
```

### Swift Binaries

```bash
# Step 1: Transpile JJ to Swift
swift run jjswift transpile ../examples/fibonacci.jj swift > fib.swift

# Step 2: Compile Swift to binary
swiftc -O -o fib_swift fib.swift

# Step 3: Run the binary
./fib_swift
```

### JavaScript Binaries (QuickJS)

QuickJS produces small standalone JS executables (~722KB vs ~44MB for Node.js pkg).

```bash
# Step 1: Install QuickJS (one time)
brew install quickjs

# Step 2: Transpile JJ to JavaScript
swift run jjswift transpile ../examples/fibonacci.jj js > fib.js

# Step 3: Compile JS to binary
qjsc -o fib_qjs fib.js

# Step 4: Run the binary
./fib_qjs
```

### Python Binaries (PyInstaller)

PyInstaller creates standalone Python executables (~3.4MB).

```bash
# Step 1: Install PyInstaller (one time)
pip3 install pyinstaller --user

# Step 2: Transpile JJ to Python
swift run jjswift transpile ../examples/fibonacci.jj py > fib.py

# Step 3: Compile Python to binary
python3 -m PyInstaller --onefile --distpath . --workpath /tmp/pyinstaller --specpath /tmp/pyinstaller fib.py

# Step 4: Run the binary
./fib
```

**PyInstaller options:**
- `--onefile`: Bundle everything into a single executable
- `--distpath .`: Output directory for the binary
- `--workpath /tmp/pyinstaller`: Temp build directory (keeps your folder clean)
- `--specpath /tmp/pyinstaller`: Spec file location

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
