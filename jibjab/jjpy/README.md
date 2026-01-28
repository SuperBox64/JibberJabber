# jjpy - Python Implementation of JibJab

Python interpreter and transpiler for the JibJab (JJ) programming language.

## Requirements

- Python 3.8+

## Usage

```bash
cd jjpy

# Run a JJ program
python3 jj.py run ../examples/hello.jj
python3 jj.py run ../examples/fibonacci.jj
python3 jj.py run ../examples/fizzbuzz.jj

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
    └── transpilers/
        ├── python.py
        ├── javascript.py
        ├── c.py
        ├── cpp.py
        ├── asm.py         # ARM64 Assembly (macOS)
        ├── swift.py
        ├── applescript.py
        ├── objc.py
        └── objcpp.py
```

## Pipeline

```
.jj source → Lexer → Tokens → Parser → AST → Interpreter (run)
                                          → Transpiler (transpile)
```

## See Also

- [../README.md](../README.md) - Implementation details
- [../SPEC.md](../SPEC.md) - Language specification
- [../../README.md](../../README.md) - Project overview
