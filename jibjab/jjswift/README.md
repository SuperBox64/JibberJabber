# jjswift - Swift Implementation of JibJab

Swift interpreter and transpiler for the JibJab (JJ) programming language.

## Requirements

- macOS 13+
- Swift 5.9+
- Xcode Command Line Tools

## Build

```bash
cd jjswift
swift build -c release
```

The executable will be at `.build/release/jjswift`

## Usage

```bash
# Using swift run (development)
swift run jjswift run ../examples/hello.jj
swift run jjswift run ../examples/fibonacci.jj
swift run jjswift run ../examples/fizzbuzz.jj

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

# Using release binary
.build/release/jjswift run ../examples/hello.jj
```

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
        ├── JJConfig.swift  # Configuration loader
        └── Transpilers/
            ├── PythonTranspiler.swift
            ├── JavaScriptTranspiler.swift
            ├── CTranspiler.swift
            ├── CppTranspiler.swift
            ├── AssemblyTranspiler.swift
            ├── SwiftTranspiler.swift
            ├── AppleScriptTranspiler.swift
            ├── ObjCTranspiler.swift
            └── ObjCppTranspiler.swift
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
