<p align="center">
  <img src="battlescript.png" width="128" alt="BattleScript Icon">
</p>

# JibberJabber 1.0 JibJab (JJ) Programming Language

**AI-first syntax** - looks like noise to humans, but LLMs parse it naturally.

```jj
~>frob{7a3}::emit("Hello, World!")     @@ Humans see noise, LLMs see: print("Hello, World!")
```

### True Native Compiler + 10 Transpiler Targets

Write once, run anywhere. JibJab includes a **true native compiler** that generates ARM64 machine code directly (no assembler or linker required), plus transpilers to 10 languages.

**Supported targets:**
- 🐍 **Python** - Cross-platform
- 📜 **JavaScript** - QuickJS
- ⚙️ **C** - Native performance
- ➕ **C++** - OOP native
- 🔧 **ARM64 Assembly** - Apple Silicon
- 🍎 **Swift** - Apple ecosystem
- 📝 **AppleScript** - macOS automation
- 🔶 **Objective-C** - Apple legacy
- 🔷 **Objective-C++** - Mixed C++/ObjC
- 🐹 **Go** - Concurrent systems

**Coming soon:** Rust

---

### Why?

- 🤖 **AI-First** - Optimized for AI coding assistants
- 🔬 **Research** - Explore LLM code comprehension
- 🔒 **Obfuscation** - Readable by AI, opaque to humans
- 🎉 **Fun** - Experiment in language design

---

## Implementations

| Implementation | Language | Location | Best For |
|----------------|----------|----------|----------|
| **jjswift** | Swift | `jibjab/jjswift/` | Native macOS, ARM64 compilation |
| **jjpy** | Python | `jibjab/jjpy/` | Cross-platform |
| **BattleScript** | SwiftUI | `BattleScript/` | Visual IDE for JibJab |

### Capabilities

| Implementation | `run` | `compile` | `asm` | `transpile` |
|----------------|:-----:|:---------:|:-----:|:-----------:|
| **jjswift** | ✅ | ✅ | ✅ | ✅ |
| **jjpy** | ✅ | ✅ | ✅ | ✅ |
| **BattleScript** | ✅ | - | - | ✅ |

- **`run`** - Interpret JJ code directly
- **`compile`** - Generate ARM64 Mach-O binary (no external tools)
- **`asm`** - Compile via assembly transpiler (uses `as` + `ld`)
- **`transpile`** - Convert to Python, JavaScript, C, C++, ARM64 Assembly, Swift, AppleScript, Objective-C, Objective-C++, Go

---

## Quick Start

### Requirements

- **Swift implementation**: macOS 13+, Swift 5.9+
- **Python implementation**: Python 3.8+
- **For C/C++/ObjC/ObjC++ compilation**: `clang` (Xcode Command Line Tools)
- **For Assembly / Native compilation**: macOS ARM64 (Apple Silicon)

### Installation

```bash
git clone https://github.com/user/JibberJabber.git
cd JibberJabber/jibjab
```

### Installing External Dependencies

Some transpile targets require external tools. Install them via [Homebrew](https://brew.sh):

```bash
# Xcode Command Line Tools (C, C++, Swift, Assembly, ObjC, ObjC++)
xcode-select --install

# QuickJS - JavaScript runtime and compiler
brew install quickjs

# Go - Go compiler
brew install go
```

| Tool | Used For | Install |
|------|----------|---------|
| `clang` / `clang++` | C, C++, ObjC, ObjC++ | `xcode-select --install` |
| `swiftc` | Swift | `xcode-select --install` |
| `as` + `ld` | ARM64 Assembly | `xcode-select --install` |
| `python3` | Python | Pre-installed on macOS |
| `osascript` | AppleScript | Pre-installed on macOS |
| `qjs` / `qjsc` | JavaScript (QuickJS) | `brew install quickjs` |
| `go` | Go | `brew install go` |

---

## Using the Swift Interpreter (`jjswift`)

### Building

```bash
cd jibjab/jjswift
swift build -c release
```

The executable will be at `.build/release/jjswift`

### Running Programs

```bash
# Run via interpreter
swift run jjswift run ../examples/hello.jj
```

### Compiling to Native Binary

```bash
# True native compilation (no external tools)
swift run jjswift compile ../examples/fibonacci.jj fib
codesign -s - fib  # Sign for Apple Silicon
./fib

# Alternative: via assembly transpiler
swift run jjswift asm ../examples/fibonacci.jj fib_asm
./fib_asm
```

The `compile` command generates ARM64 machine code directly from JJ source, producing a standalone Mach-O executable without needing `as` or `ld`.

### Transpiling

```bash
swift run jjswift transpile ../examples/fibonacci.jj py          # Python
swift run jjswift transpile ../examples/fibonacci.jj js          # JavaScript
swift run jjswift transpile ../examples/fibonacci.jj c           # C
swift run jjswift transpile ../examples/fibonacci.jj cpp         # C++
swift run jjswift transpile ../examples/fibonacci.jj asm         # ARM64 Assembly
swift run jjswift transpile ../examples/fibonacci.jj swift       # Swift
swift run jjswift transpile ../examples/fibonacci.jj applescript fib.scpt  # AppleScript (compiled)
swift run jjswift transpile ../examples/fibonacci.jj objc        # Objective-C
swift run jjswift transpile ../examples/fibonacci.jj objcpp      # Objective-C++
swift run jjswift transpile ../examples/fibonacci.jj go          # Go
```

### Transpile and Execute

```bash
swift run jjswift transpile ../examples/fibonacci.jj py > /tmp/fib.py && python3 /tmp/fib.py
swift run jjswift transpile ../examples/fibonacci.jj c > /tmp/fib.c && clang /tmp/fib.c -o /tmp/fib && /tmp/fib
swift run jjswift transpile ../examples/fibonacci.jj applescript /tmp/fib.scpt && osascript /tmp/fib.scpt
```

---

## Using the Python Interpreter (`jjpy`)

### Running Programs

```bash
cd jibjab/jjpy

# Run via interpreter
python3 jj.py run ../examples/hello.jj
```

### Compiling to Native Binary

```bash
# True native compilation (no external tools)
python3 jj.py compile ../examples/fibonacci.jj fib
codesign -s - fib  # Sign for Apple Silicon
./fib

# Alternative: via assembly transpiler
python3 jj.py asm ../examples/fibonacci.jj fib_asm
./fib_asm
```

The `compile` command generates ARM64 machine code directly from JJ source, producing a standalone Mach-O executable without needing `as` or `ld`.

### Transpiling

```bash
python3 jj.py transpile ../examples/fibonacci.jj py          # Python
python3 jj.py transpile ../examples/fibonacci.jj js          # JavaScript
python3 jj.py transpile ../examples/fibonacci.jj c           # C
python3 jj.py transpile ../examples/fibonacci.jj cpp         # C++
python3 jj.py transpile ../examples/fibonacci.jj asm         # ARM64 Assembly
python3 jj.py transpile ../examples/fibonacci.jj swift       # Swift
python3 jj.py transpile ../examples/fibonacci.jj applescript fib.scpt  # AppleScript (compiled)
python3 jj.py transpile ../examples/fibonacci.jj objc        # Objective-C
python3 jj.py transpile ../examples/fibonacci.jj objcpp      # Objective-C++
python3 jj.py transpile ../examples/fibonacci.jj go          # Go
```

### Transpile and Execute

```bash
python3 jj.py transpile ../examples/fibonacci.jj py > /tmp/fib.py && python3 /tmp/fib.py
python3 jj.py transpile ../examples/fibonacci.jj c > /tmp/fib.c && clang /tmp/fib.c -o /tmp/fib && /tmp/fib
python3 jj.py transpile ../examples/fibonacci.jj applescript /tmp/fib.scpt && osascript /tmp/fib.scpt
```

---

## Language Syntax

| JibJab | Meaning | Python |
|---------------|---------------|-------------------|
| `~>frob{7a3}::emit(x)` | Print output | `print(x)` |
| `~>snag{x}::val(10)` | Assign variable | `x = 10` |
| `~>slurp{9f2}::grab("?")` | Get input | `input("?")` |
| `<~loop{i:0..10}>>` | For loop | `for i in range(0, 10):` |
| `<~when{x <gt> 5}>>` | If statement | `if x > 5:` |
| `<~else>>` | Else branch | `else:` |
| `<~>>` | End block | (end of indented block) |
| `<~morph{add(a,b)}>>` | Define function | `def add(a, b):` |
| `~>invoke{add}::with(1,2)` | Call function | `add(1, 2)` |
| `~>yeet{value}` | Return | `return value` |
| `~>enum{Color}::cases(R,G,B)` | Define enum | `class Color(Enum):` |
| `#42` | Number literal | `42` |
| `"text"` | String literal | `"text"` |
| `[#1, #2, #3]` | Array literal | `[1, 2, 3]` |
| `{"a": #1}` | Dictionary literal | `{"a": 1}` |
| `(#1, #2)` | Tuple literal | `(1, 2)` |
| `arr[#0]` | Index access | `arr[0]` |
| `dict["key"]` | Key access | `dict["key"]` |
| `~yep` / `~nope` | Boolean | `True` / `False` |
| `~nil` | Null value | `None` |
| `@@` | Comment | `#` |

### Operators

| JibJab | Meaning | Symbol |
|--------|---------|--------|
| `<+>` | Add | `+` |
| `<->` | Subtract | `-` |
| `<*>` | Multiply | `*` |
| `</>` | Divide | `/` |
| `<%>` | Modulo | `%` |
| `<=>` | Equals | `==` |
| `<!=>` | Not equals | `!=` |
| `<lt>` | Less than | `<` |
| `<lte>` | Less than or equal | `<=` |
| `<gt>` | Greater than | `>` |
| `<gte>` | Greater than or equal | `>=` |
| `<&&>` | And | `and` |
| `<\|\|>` | Or | `or` |
| `<!>` | Not | `not` |

---

## Example Programs

### Hello World
```jj
~>frob{7a3}::emit("Hello, JibJab World!")
```

### Variables and Math
```jj
~>snag{x}::val(#10)
~>snag{y}::val(#5)

~>frob{7a3}::emit(x <+> y)    @@ prints 15
~>frob{7a3}::emit(x <*> y)    @@ prints 50
```

### Conditionals
```jj
~>snag{age}::val(#21)

<~when{age <gt> #18}>>
    ~>frob{7a3}::emit("Adult")
<~else>>
    ~>frob{7a3}::emit("Minor")
<~>>
```

### Loops
```jj
@@ Count from 0 to 9
<~loop{i:0..10}>>
    ~>frob{7a3}::emit(i)
<~>>
```

### Functions (Fibonacci)
```jj
<~morph{fib(n)}>>
    <~when{n <lt> #2}>>
        ~>yeet{n}
    <~>>
    ~>yeet{(~>invoke{fib}::with(n <-> #1)) <+> (~>invoke{fib}::with(n <-> #2))}
<~>>

@@ Print first 15 Fibonacci numbers
<~loop{i:0..15}>>
    ~>frob{7a3}::emit(~>invoke{fib}::with(i))
<~>>
```

### FizzBuzz
```jj
<~loop{n:1..101}>>
    <~when{(n <%> #15) <=> #0}>>
        ~>frob{7a3}::emit("FizzBuzz")
    <~else>>
        <~when{(n <%> #3) <=> #0}>>
            ~>frob{7a3}::emit("Fizz")
        <~else>>
            <~when{(n <%> #5) <=> #0}>>
                ~>frob{7a3}::emit("Buzz")
            <~else>>
                ~>frob{7a3}::emit(n)
            <~>>
        <~>>
    <~>>
<~>>
```

---

## Regression Test Results

Run `bash regression.sh -vg` for verbose output with grid, `-v` for verbose only, `-g` for grid only.

```
[jjpy]
              run  comp asm  py   js   c    cpp  swft objc ocpp go
              ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ----
numbers       ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
fizzbuzz      ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
fibonacci     ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
variables     ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
enums         ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
dictionaries  ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
tuples        ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
arrays        ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
comparisons   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
hello         ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅

[jjswift]
              run  comp asm  py   js   c    cpp  swft objc ocpp go
              ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ----
numbers       ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
fizzbuzz      ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
fibonacci     ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
variables     ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
enums         ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
dictionaries  ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
tuples        ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
arrays        ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
comparisons   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅
hello         ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅   ✅

TOTAL: 380 passed, 0 failed
```

---

## BattleScript IDE

BattleScript is a native macOS app that provides a visual IDE for JibJab. Write JJ code and instantly see it transpiled to all 10 target languages, then compile and run any target with one click.

See [BattleScript/README.md](BattleScript/README.md) for details.

---

## Project Structure

```
JibberJabber/
├── BattleScript/               # macOS IDE app
│   ├── BattleScript.xcodeproj
│   └── BattleScript/
│       ├── BattleScriptApp.swift
│       ├── ContentView.swift
│       ├── EditorTabView.swift
│       ├── OutputView.swift
│       └── JJEngine.swift
│
├── jibjab/
│   ├── common/
│   │   ├── jj.json              # Shared language definition
│   │   └── arm64.json           # Shared ARM64/Mach-O constants
│   │
│   ├── jjswift/                 # Swift implementation
│   │   ├── Package.swift
│   │   └── Sources/jjswift/
│   │       ├── main.swift       # CLI entry point
│   │       └── JJ/
│   │           ├── Lexer.swift
│   │           ├── Token.swift
│   │           ├── AST.swift
│   │           ├── Parser.swift
│   │           ├── Interpreter.swift
│   │           ├── NativeCompiler.swift  # ARM64 Mach-O generator
│   │           ├── JJConfig.swift
│   │           └── Transpilers/
│   │               ├── PythonTranspiler.swift
│   │               ├── JavaScriptTranspiler.swift
│   │               ├── CTranspiler.swift
│   │               ├── CppTranspiler.swift
│   │               ├── AssemblyTranspiler.swift
│   │               ├── SwiftTranspiler.swift
│   │               ├── AppleScriptTranspiler.swift
│   │               ├── ObjCTranspiler.swift
│   │               ├── ObjCppTranspiler.swift
│   │               └── GoTranspiler.swift
│   │
│   ├── jjpy/                    # Python implementation
│   │   ├── jj.py                # CLI entry point
│   │   └── jj/
│   │       ├── __init__.py
│   │       ├── lexer.py
│   │       ├── ast.py
│   │       ├── parser.py
│   │       ├── interpreter.py
│   │       ├── native_compiler.py  # ARM64 Mach-O generator
│   │       └── transpilers/
│   │           ├── __init__.py
│   │           ├── python.py
│   │           ├── javascript.py
│   │           ├── c.py
│   │           ├── cpp.py
│   │           ├── asm.py
│   │           ├── swift.py
│   │           ├── applescript.py
│   │           ├── objc.py
│   │           ├── objcpp.py
│   │           └── go.py
│   │
│   ├── examples/                # Example JJ programs
│   │   ├── hello.jj
│   │   ├── variables.jj
│   │   ├── fibonacci.jj
│   │   ├── fizzbuzz.jj
│   │   ├── arrays.jj
│   │   ├── comparisons.jj
│   │   ├── dictionaries.jj
│   │   ├── enums.jj
│   │   ├── numbers.jj
│   │   └── tuples.jj
│   │
│   ├── README.md                # Detailed docs
│   └── SPEC.md                  # Language specification
│
└── README.md                    # This file
```

---

## Shared Language Definition (`jj.json`)

Both implementations read from `jibjab/common/jj.json`, which defines keywords, blocks, operators, and transpilation templates. This ensures identical output from both implementations.

---

## How It Works

### The Pipeline

<div align="center">

```mermaid
flowchart TD
    A[📜 JJ Source Code] --> B[✂️  Lexer]
    B --> C[🌳 Parser<br>Builds AST]
    C --> D{Interpret<br>Compile<br>Transpile}

    A1[".jj file with<br>JibJab syntax"] -.- A
    B1["Breaks code into<br>tokens"] -.- B
    C1["Builds Abstract<br>Syntax Tree"] -.- C

    D --> E[⚡ Interpreter]
    E --> F[🖥️  Program Output]

    D --> N1[🔧 Native Compiler]
    N1 --> N2[🍎 ARM64 Mach-O]
    N2 --> N3[🚀 Run Binary]
    N3 --> F

    D --> G[🛠️ Transpiler]
    G --> H[Python]
    G --> I[JS]
    G --> J[C/C++]
    G --> K[ASM]
    G --> L[Swift]
    G --> Q[ObjC/C++]

    H --> M[🔨 Create Binary]
    I --> M
    J --> M
    K --> M
    L --> M
    Q --> M
    M --> N[🚀 Run Binary]
    N --> F

    style N1 fill:#4a1a6e,stroke:#bf5fff,color:#fff
    style N2 fill:#3d1a5e,stroke:#bf5fff,color:#fff
    style N3 fill:#2d1a4e,stroke:#bf5fff,color:#fff

    style M fill:#2a4a6e,stroke:#ffa500,color:#fff
    style N fill:#16213e,stroke:#ffa500,color:#fff

    style A fill:#1a1a2e,stroke:#00d4ff,color:#fff
    style B fill:#16213e,stroke:#00d4ff,color:#fff
    style C fill:#16213e,stroke:#00d4ff,color:#fff
    style D fill:#0f3460,stroke:#e94560,color:#fff
    style E fill:#1a1a2e,stroke:#00ff88,color:#fff
    style F fill:#00ff88,stroke:#00ff88,color:#000
    style G fill:#2a4a6e,stroke:#ffa500,color:#fff
```

</div>

### Why LLMs Understand JibJab

1. **Semantic Tokens** - `frob`, `yeet`, `snag` cluster near their meanings in embedding space
2. **Predictable Structure** - `<~...>>` blocks follow consistent patterns
3. **Type Prefixes** - `#` for numbers, `~` for special values
4. **Distinct Operators** - `<op>` format makes operators clear tokens
5. **Action Chaining** - `::` separates object from action

**Humans see:** `~>frob{7a3}::emit(x <+> y)` → **LLMs see:** `print(x + y)`

---

## Documentation

| Document | Description |
|----------|-------------|
| [BattleScript/README.md](BattleScript/README.md) | BattleScript IDE docs |
| [jibjab/README.md](jibjab/README.md) | Detailed implementation docs |
| [jibjab/SPEC.md](jibjab/SPEC.md) | Complete language specification |
| [jibjab/common/jj.json](jibjab/common/jj.json) | Shared language definition |

---

## Contributing

Contributions welcome:
- New transpiler targets (Rust, Linux ARM64)
- Language features (objects, imports)
- IDE syntax highlighting

---

## License

MIT

---

*JibJab: Where humans see noise and AI sees code.*
