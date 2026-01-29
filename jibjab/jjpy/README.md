# jjpy - Python Implementation of JibJab

Python interpreter, native compiler, and transpiler for the JibJab (JJ) programming language.

## Requirements

- Python 3.8+
- Apple Silicon (ARM64) for native compilation

## Usage

```bash
cd jjpy

# Run a JJ program
python3 jj.py run ../examples/hello.jj
python3 jj.py run ../examples/fibonacci.jj
python3 jj.py run ../examples/fizzbuzz.jj

# Native compilation (two methods)
python3 jj.py compile ../examples/fibonacci.jj fib      # True native: JJ → Machine Code → Mach-O
python3 jj.py asm ../examples/fibonacci.jj fib_asm      # Via transpiler: JJ → ASM → as/ld → binary

# Transpile to other languages
python3 jj.py transpile ../examples/fibonacci.jj py          # Python
python3 jj.py transpile ../examples/fibonacci.jj js          # JavaScript
python3 jj.py transpile ../examples/fibonacci.jj c           # C
python3 jj.py transpile ../examples/fibonacci.jj cpp         # C++
python3 jj.py transpile ../examples/fibonacci.jj asm         # ARM64 Assembly
python3 jj.py transpile ../examples/fibonacci.jj swift       # Swift
python3 jj.py transpile ../examples/fibonacci.jj applescript # AppleScript
python3 jj.py transpile ../examples/fibonacci.jj objc        # Objective-C
python3 jj.py transpile ../examples/fibonacci.jj objcpp      # Objective-C++
python3 jj.py transpile ../examples/fibonacci.jj go          # Go

# Build (transpile + compile to binary)
python3 jj.py build ../examples/fibonacci.jj c               # Build C binary
python3 jj.py build ../examples/fibonacci.jj swift           # Build Swift binary

# Exec (transpile + compile + run)
python3 jj.py exec ../examples/fibonacci.jj c                # Run via C
python3 jj.py exec ../examples/fibonacci.jj swift            # Run via Swift
```

## Structure

```
jjpy/
├── jj.py              # CLI entry point
└── jj/
    ├── __init__.py    # Package exports
    ├── lexer.py       # Tokenization
    ├── ast.py         # AST node definitions
    ├── parser.py      # Recursive descent parser
    ├── interpreter.py # Direct execution
    ├── native_compiler.py # ARM64 Mach-O generator
    └── transpilers/
        ├── python.py
        ├── javascript.py
        ├── cfamily.py     # Shared C-family base transpiler
        ├── c.py
        ├── cpp.py
        ├── asm.py         # ARM64 Assembly (macOS)
        ├── swift.py
        ├── applescript.py
        ├── objc.py
        ├── objcpp.py
        └── go.py
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
