#!/usr/bin/env python3
"""
JibJab (JJ) Language Interpreter and Transpiler
A language designed for AI comprehension

This is the CLI entry point. The implementation is in the jj/ package.
"""

import sys
from jj import (
    Lexer, Parser, Interpreter,
    PythonTranspiler, JavaScriptTranspiler, CTranspiler, AssemblyTranspiler, SwiftTranspiler
)


def main():
    if len(sys.argv) < 3:
        print("JibJab Language v1.0")
        print("Usage:")
        print("  python3 jj.py run <file.jj>            - Run JJ program")
        print("  python3 jj.py transpile <file.jj> py   - Transpile to Python")
        print("  python3 jj.py transpile <file.jj> js   - Transpile to JavaScript")
        print("  python3 jj.py transpile <file.jj> c    - Transpile to C")
        print("  python3 jj.py transpile <file.jj> asm  - Transpile to ARM64 Assembly")
        print("  python3 jj.py transpile <file.jj> swift - Transpile to Swift")
        sys.exit(1)

    command = sys.argv[1]
    filename = sys.argv[2]

    with open(filename, 'r') as f:
        source = f.read()

    lexer = Lexer(source)
    tokens = lexer.tokenize()
    parser = Parser(tokens)
    program = parser.parse()

    if command == 'run':
        interpreter = Interpreter()
        interpreter.run(program)
    elif command == 'transpile':
        target = sys.argv[3] if len(sys.argv) > 3 else 'py'
        transpilers = {
            'py': PythonTranspiler,
            'js': JavaScriptTranspiler,
            'c': CTranspiler,
            'asm': AssemblyTranspiler,
            'swift': SwiftTranspiler,
        }
        if target not in transpilers:
            print(f"Unknown target: {target}")
            print("Valid targets: py, js, c, asm, swift")
            sys.exit(1)
        transpiler = transpilers[target]()
        print(transpiler.transpile(program))
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    main()
