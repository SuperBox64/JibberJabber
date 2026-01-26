#!/usr/bin/env python3
"""
JibJab (JJ) Language Interpreter and Transpiler
A language designed for AI comprehension

This is the CLI entry point. The implementation is in the jj/ package.
"""

import sys
import os
import subprocess
from jj import (
    Lexer, Parser, Interpreter, NativeCompiler,
    PythonTranspiler, JavaScriptTranspiler, CTranspiler, AssemblyTranspiler, SwiftTranspiler,
    AppleScriptTranspiler, CppTranspiler, ObjCTranspiler, ObjCppTranspiler
)


def main():
    if len(sys.argv) < 3:
        print("JibJab Language v1.0")
        print("Usage:")
        print("  python3 jj.py run <file.jj>              - Run JJ program")
        print("  python3 jj.py compile <file.jj> <output> - Compile to ARM64 Mach-O")
        print("  python3 jj.py asm <file.jj> <output>     - Compile via assembly")
        print("  python3 jj.py transpile <file.jj> py     - Transpile to Python")
        print("  python3 jj.py transpile <file.jj> js     - Transpile to JavaScript")
        print("  python3 jj.py transpile <file.jj> c      - Transpile to C")
        print("  python3 jj.py transpile <file.jj> cpp    - Transpile to C++")
        print("  python3 jj.py transpile <file.jj> asm    - Transpile to ARM64 Assembly")
        print("  python3 jj.py transpile <file.jj> swift  - Transpile to Swift")
        print("  python3 jj.py transpile <file.jj> applescript [output] - Compile to AppleScript")
        print("  python3 jj.py transpile <file.jj> objc   - Transpile to Objective-C")
        print("  python3 jj.py transpile <file.jj> objcpp - Transpile to Objective-C++")
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
    elif command == 'compile':
        output = sys.argv[3] if len(sys.argv) > 3 else 'a.out'
        compiler = NativeCompiler()
        compiler.compile(program, output)
        subprocess.run(['codesign', '-s', '-', output], check=True)
        print(f"Compiled to {output}")
    elif command == 'asm':
        output = sys.argv[3] if len(sys.argv) > 3 else 'a.out'
        transpiler = AssemblyTranspiler()
        asm_code = transpiler.transpile(program)
        basename = os.path.basename(output)
        asm_file = f'/tmp/{basename}.s'
        obj_file = f'/tmp/{basename}.o'
        with open(asm_file, 'w') as f:
            f.write(asm_code)
        subprocess.run(['as', '-o', obj_file, asm_file], check=True)
        sdk_path = subprocess.check_output(['xcrun', '-sdk', 'macosx', '--show-sdk-path']).decode().strip()
        subprocess.run(['ld', '-o', output, obj_file, '-lSystem', '-syslibroot', sdk_path, '-e', '_main', '-arch', 'arm64'], check=True)
        print(f"Compiled to {output}")
    elif command == 'transpile':
        target = sys.argv[3] if len(sys.argv) > 3 else 'py'
        transpilers = {
            'py': PythonTranspiler,
            'js': JavaScriptTranspiler,
            'c': CTranspiler,
            'asm': AssemblyTranspiler,
            'swift': SwiftTranspiler,
            'applescript': AppleScriptTranspiler,
            'cpp': CppTranspiler,
            'objc': ObjCTranspiler,
            'objcpp': ObjCppTranspiler,
        }
        if target not in transpilers:
            print(f"Unknown target: {target}")
            print("Valid targets: py, js, c, cpp, asm, swift, applescript, objc, objcpp")
            sys.exit(1)
        transpiler = transpilers[target]()
        code = transpiler.transpile(program)

        # AppleScript: compile with osacompile
        if target == 'applescript':
            output = sys.argv[4] if len(sys.argv) > 4 else 'a.scpt'
            temp_file = f'/tmp/jj_temp.applescript'
            with open(temp_file, 'w') as f:
                f.write(code)
            subprocess.run(['osacompile', '-o', output, temp_file], check=True)
            os.remove(temp_file)
            print(f"Compiled to {output}")
        else:
            print(code)
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    main()
