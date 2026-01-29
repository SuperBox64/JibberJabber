# jjswift - Swift Implementation of JibJab

Swift interpreter, native compiler, and transpiler for the JibJab (JJ) programming language.

## Requirements

- macOS 13+
- Swift 5.9+
- Xcode Command Line Tools
- Apple Silicon (ARM64) for native compilation

## Build

```bash
cd jjswift
swift build -c release
```

The executable will be at `.build/release/jjswift`

## Usage

```bash
# Run via interpreter
swift run jjswift run ../examples/hello.jj
swift run jjswift run ../examples/fibonacci.jj

# Native compilation (two methods)
swift run jjswift compile ../examples/fibonacci.jj fib    # True native: JJ → Machine Code → Mach-O
swift run jjswift asm ../examples/fibonacci.jj fib_asm    # Via transpiler: JJ → ASM → as/ld → binary

# Transpile to other languages
swift run jjswift transpile ../examples/fibonacci.jj py          # Python
swift run jjswift transpile ../examples/fibonacci.jj js          # JavaScript
swift run jjswift transpile ../examples/fibonacci.jj c           # C
swift run jjswift transpile ../examples/fibonacci.jj cpp         # C++
swift run jjswift transpile ../examples/fibonacci.jj asm         # ARM64 Assembly
swift run jjswift transpile ../examples/fibonacci.jj swift       # Swift
swift run jjswift transpile ../examples/fibonacci.jj applescript # AppleScript
swift run jjswift transpile ../examples/fibonacci.jj objc        # Objective-C
swift run jjswift transpile ../examples/fibonacci.jj objcpp      # Objective-C++
swift run jjswift transpile ../examples/fibonacci.jj go          # Go

# Build (transpile + compile to binary)
swift run jjswift build ../examples/fibonacci.jj c               # Build C binary
swift run jjswift build ../examples/fibonacci.jj swift           # Build Swift binary

# Exec (transpile + compile + run)
swift run jjswift exec ../examples/fibonacci.jj c                # Run via C
swift run jjswift exec ../examples/fibonacci.jj swift            # Run via Swift

# Using release binary
.build/release/jjswift run ../examples/hello.jj
```

## Native Compilation

jjswift includes a **true native compiler** that generates ARM64 Mach-O executables directly from JJ source code without any external tools:

```bash
swift run jjswift compile ../examples/hello.jj hello
./hello  # Runs standalone binary
```

**How it works:**
- Parses JJ source to AST
- Generates ARM64 machine code directly
- Writes valid Mach-O executable format
- Uses syscalls for I/O (no libc dependency)
- Requires only `codesign` for Apple Silicon

**Two compilation methods:**

| Command | Method | External Tools | Size |
|---------|--------|----------------|------|
| `compile` | True native compiler | None (codesign only) | ~48KB |
| `asm` | Assembly transpiler | `as` + `ld` | ~49KB |

## Structure

```
jjswift/
├── Package.swift           # Swift package manifest
└── Sources/jjswift/
    ├── main.swift          # CLI entry point
    └── JJ/
        ├── Lexer.swift     # Tokenization
        ├── Token.swift     # Token types
        ├── AST.swift       # AST node definitions
        ├── Parser.swift    # Recursive descent parser
        ├── Interpreter.swift # Direct execution
        ├── NativeCompiler.swift # ARM64 Mach-O generator
        ├── JJConfig.swift  # Configuration loader
        └── Transpilers/
            ├── PythonTranspiler.swift
            ├── JavaScriptTranspiler.swift
            ├── CFamilyTranspiler.swift  # Shared C-family base transpiler
            ├── CTranspiler.swift
            ├── CppTranspiler.swift
            ├── AssemblyTranspiler.swift
            ├── SwiftTranspiler.swift
            ├── AppleScriptTranspiler.swift
            ├── ObjCTranspiler.swift
            ├── ObjCppTranspiler.swift
            └── GoTranspiler.swift
```

## Pipeline

```
.jj source → Lexer → Tokens → Parser → AST → Interpreter (run)
                                          → NativeCompiler (compile)
                                          → Transpiler (transpile/asm)
```

## See Also

- [../README.md](../README.md) - Implementation details
- [../SPEC.md](../SPEC.md) - Language specification
- [../../README.md](../../README.md) - Project overview
