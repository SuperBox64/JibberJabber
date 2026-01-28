# JibJab Implementation Details

Two interpreters (Swift and Python), a native ARM64 compiler, shared language definition, and examples.

---

## Directory Structure

```
jibjab/
├── common/
│   ├── jj.json              # Shared language definition (tokens, operators, transpiler templates)
│   └── arm64.json           # Shared ARM64/Mach-O constants for native compiler
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
│           ├── NativeCompiler.swift # ARM64 Mach-O generator
│           ├── JJConfig.swift   # Configuration loader
│           └── Transpilers/
│               ├── PythonTranspiler.swift
│               ├── JavaScriptTranspiler.swift
│               ├── CFamilyTranspiler.swift  # Shared C-family base
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
│       ├── native_compiler.py # ARM64 Mach-O generator
│       └── transpilers/
│           ├── __init__.py
│           ├── python.py
│           ├── javascript.py
│           ├── cfamily.py   # Shared C-family base transpiler
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
│   ├── fizzbuzz.jj
│   ├── numbers.jj
│   ├── enums.jj
│   ├── dictionaries.jj
│   ├── tuples.jj
│   ├── arrays.jj
│   └── comparisons.jj
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

# Native compilation (two methods)
swift run jjswift compile ../examples/fibonacci.jj fib      # True native compiler
swift run jjswift asm ../examples/fibonacci.jj fib_asm      # Via assembly transpiler
./fib      # Run the binary

# Transpile
swift run jjswift transpile ../examples/fibonacci.jj py          # Python
swift run jjswift transpile ../examples/fibonacci.jj js          # JavaScript
swift run jjswift transpile ../examples/fibonacci.jj c           # C
swift run jjswift transpile ../examples/fibonacci.jj cpp         # C++
swift run jjswift transpile ../examples/fibonacci.jj asm         # ARM64 Assembly
swift run jjswift transpile ../examples/fibonacci.jj swift       # Swift
swift run jjswift transpile ../examples/fibonacci.jj applescript fib.scpt # AppleScript (compiled)
swift run jjswift transpile ../examples/fibonacci.jj objc        # Objective-C
swift run jjswift transpile ../examples/fibonacci.jj objcpp      # Objective-C++

# Build (transpile + compile to binary)
swift run jjswift build ../examples/fibonacci.jj c               # Build C binary

# Exec (transpile + compile + run)
swift run jjswift exec ../examples/fibonacci.jj c                # Run via C
```

### Using Python (`jjpy`)

```bash
cd jjpy

# Run examples
python3 jj.py run ../examples/hello.jj
python3 jj.py run ../examples/fibonacci.jj

# Native compilation (two methods)
python3 jj.py compile ../examples/fibonacci.jj fib      # True native compiler
python3 jj.py asm ../examples/fibonacci.jj fib_asm      # Via assembly transpiler
./fib      # Run the binary

# Transpile
python3 jj.py transpile ../examples/fibonacci.jj py          # Python
python3 jj.py transpile ../examples/fibonacci.jj js          # JavaScript
python3 jj.py transpile ../examples/fibonacci.jj c           # C
python3 jj.py transpile ../examples/fibonacci.jj cpp         # C++
python3 jj.py transpile ../examples/fibonacci.jj asm         # ARM64 Assembly
python3 jj.py transpile ../examples/fibonacci.jj swift       # Swift
python3 jj.py transpile ../examples/fibonacci.jj applescript fib.scpt # AppleScript (compiled)
python3 jj.py transpile ../examples/fibonacci.jj objc        # Objective-C
python3 jj.py transpile ../examples/fibonacci.jj objcpp      # Objective-C++

# Build (transpile + compile to binary)
python3 jj.py build ../examples/fibonacci.jj c               # Build C binary

# Exec (transpile + compile + run)
python3 jj.py exec ../examples/fibonacci.jj c                # Run via C
```

---

## 1. Interpreting (Run)

Execute JJ programs directly without compilation:

```bash
# Swift
jjswift run examples/fibonacci.jj

# Python
python3 jj.py run examples/fibonacci.jj
```

The interpreter executes the AST directly - no intermediate files or binaries.

---

## 2. Compiling (Native Binaries)

Generate standalone ARM64 Mach-O executables:

| Method | Command | Description |
|--------|---------|-------------|
| Native | `compile` | Direct AST to machine code (no external tools) |
| Assembly | `asm` | AST to ARM64 assembly, then `as` + `ld` |

```bash
# Native compiler (built-in, no external tools)
jjswift compile examples/fibonacci.jj fib
./fib

# Via assembly transpiler
jjswift asm examples/fibonacci.jj fib_asm
./fib_asm
```

Both produce ~48-50KB signed Mach-O binaries.

---

## 3. Transpiling (To Source or Binary)

Convert JJ to other languages - outputs source code or compiled binaries:

| Target | Output | Compile | Run |
|--------|--------|---------|-----|
| `py` | Source | - | `python3 fib.py` |
| `js` | Source | - | `qjs fib.js` |
| `c` | Source | `clang fib.c -o fib` | `./fib` |
| `cpp` | Source | `clang++ fib.cpp -o fib` | `./fib` |
| `swift` | Source | `swiftc fib.swift -o fib` | `./fib` |
| `objc` | Source | `clang -framework Foundation fib.m -o fib` | `./fib` |
| `objcpp` | Source | `clang++ -framework Foundation fib.mm -o fib` | `./fib` |
| `asm` | Source | `as fib.s -o fib.o && ld ...` | `./fib` |
| `applescript` | **Binary** | (automatic via osacompile) | `osascript fib.scpt` |

```bash
# Interpreted languages (prints source code)
jjswift transpile examples/fibonacci.jj py
jjswift transpile examples/fibonacci.jj js

# Compiled languages (prints source code, compile separately)
jjswift transpile examples/fibonacci.jj c > fib.c
clang fib.c -o fib && ./fib

# AppleScript (compiles directly to binary via osacompile)
jjswift transpile examples/fibonacci.jj applescript fib.scpt
osascript fib.scpt
```

---

## Language Definition (`common/jj.json`)

Both implementations read from this shared definition:

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

Each target has code generation templates. See `common/jj.json` for details.

---

## Pipeline

```
Source → Lexer → Tokens → Parser → AST → Interpreter (run)
                                       → NativeCompiler (compile)
                                       → Transpiler (transpile/asm)
```

| Stage | Input | Output |
|-------|-------|--------|
| Lexer | `~>snag{x}::val(#42)` | Token stream |
| Parser | Tokens | AST: `VarDecl(name="x", value=42)` |
| Interpreter | AST | Executes directly |
| Transpiler | AST | `x = 42` (Python), `int x = 42;` (C), etc. |

---

## Test Results

Run `bash regression.sh -vg` from the project root for full results.

```
              run  comp asm  py   js   c    cpp  swft objc ocpp
              ---- ---- ---- ---- ---- ---- ---- ---- ---- ----
numbers       ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
fizzbuzz      ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
fibonacci     ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
variables     ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
enums         ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
dictionaries  ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
tuples        ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
arrays        ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
comparisons   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
hello         ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅

TOTAL: 340 passed, 0 failed (both jjpy and jjswift)
```

---

## Creating Binaries

Binary sizes by target:

| Target | Size | Tool |
|--------|------|------|
| **Native (compile)** | ~48KB | None (built-in) |
| Native (asm) | ~49KB | as + ld |
| C | ~33KB | gcc/clang |
| C++ | ~33KB | g++/clang++ |
| Objective-C | ~33KB | clang |
| Objective-C++ | ~33KB | clang++ |
| Swift | ~100KB | swiftc |
| AppleScript | ~1.5KB | osacompile (built-in) |
| JavaScript | ~722KB | QuickJS |
| Python | ~3.4MB | PyInstaller |

### Native Compilation (No External Tools)

The `compile` command uses the built-in native compiler to generate ARM64 Mach-O binaries directly:

```bash
swift run jjswift compile ../examples/fibonacci.jj fib
codesign -s - fib  # Sign for Apple Silicon
./fib
```

This generates machine code directly from the AST without any external assembler or linker.

### Prerequisites (macOS)

```bash
xcode-select --install  # Xcode Command Line Tools
```

### C / C++

```bash
swift run jjswift transpile ../examples/fibonacci.jj c > fib.c && gcc -o fib_c fib.c && ./fib_c
swift run jjswift transpile ../examples/fibonacci.jj cpp > fib.cpp && g++ -o fib_cpp fib.cpp && ./fib_cpp
```

### Objective-C / Objective-C++

```bash
swift run jjswift transpile ../examples/fibonacci.jj objc > fib.m && clang -framework Foundation -o fib_objc fib.m && ./fib_objc
swift run jjswift transpile ../examples/fibonacci.jj objcpp > fib.mm && clang++ -framework Foundation -o fib_objcpp fib.mm && ./fib_objcpp
```

### ARM64 Assembly (macOS)

```bash
swift run jjswift transpile ../examples/fibonacci.jj asm > fib.s
as -o fib.o fib.s
ld -o fib_asm fib.o -lSystem -syslibroot $(xcrun -sdk macosx --show-sdk-path) -e _main -arch arm64
./fib_asm
```

### Swift

```bash
swift run jjswift transpile ../examples/fibonacci.jj swift > fib.swift && swiftc -O -o fib_swift fib.swift && ./fib_swift
```

### JavaScript (QuickJS)

```bash
brew install quickjs  # one time
swift run jjswift transpile ../examples/fibonacci.jj js > fib.js && qjsc -o fib_qjs fib.js && ./fib_qjs
```

### AppleScript (osacompile)

The `transpile applescript` command internally uses `osacompile` to produce a compiled binary:

```bash
swift run jjswift transpile ../examples/fibonacci.jj applescript fib.scpt
osascript fib.scpt
```

You can also compile to an app bundle:

```bash
swift run jjswift transpile ../examples/fibonacci.jj applescript fib.app
osascript fib.app
```

### Python Binaries (PyInstaller)

```bash
pip3 install pyinstaller --user
swift run jjswift transpile ../examples/fibonacci.jj py > fib.py
python3 -m PyInstaller --onefile --distpath . --workpath /tmp/pyinstaller --specpath /tmp/pyinstaller fib.py
./fib
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
