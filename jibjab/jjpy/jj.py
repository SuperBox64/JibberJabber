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


def get_compile_cmd(target, src_file, out_file):
    """Return compile command for each target."""
    cmds = {
        'c': ['clang', src_file, '-o', out_file],
        'cpp': ['clang++', src_file, '-o', out_file],
        'swift': ['swiftc', src_file, '-o', out_file],
        'objc': ['clang', '-framework', 'Foundation', src_file, '-o', out_file],
        'objcpp': ['clang++', '-framework', 'Foundation', src_file, '-o', out_file],
        'js': ['qjsc', '-o', out_file, src_file],
    }
    return cmds.get(target)


def get_file_ext(target):
    """Return file extension for each target."""
    exts = {
        'py': '.py', 'js': '.js', 'c': '.c', 'cpp': '.cpp',
        'swift': '.swift', 'objc': '.m', 'objcpp': '.mm', 'asm': '.s'
    }
    return exts.get(target, '.txt')


def main():
    if len(sys.argv) < 3:
        print("JibJab Language v1.0")
        print("Usage:")
        print("  python3 jj.py run <file.jj>              - Run JJ program")
        print("  python3 jj.py compile <file.jj> <output> - Compile to ARM64 Mach-O")
        print("  python3 jj.py asm <file.jj> <output>     - Compile via assembly")
        print("  python3 jj.py transpile <file.jj> <target>           - Transpile to target")
        print("  python3 jj.py build <file.jj> <target> [output]      - Transpile + compile")
        print("  python3 jj.py exec <file.jj> <target>                - Transpile + compile + run")
        print("")
        print("Targets: py, js, c, cpp, asm, swift, applescript, objc, objcpp")
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

    elif command == 'build':
        # Transpile + compile to binary
        target = sys.argv[3] if len(sys.argv) > 3 else 'c'
        basename = os.path.splitext(os.path.basename(filename))[0]
        output = sys.argv[4] if len(sys.argv) > 4 else f'{basename}_{target}'

        transpilers = {
            'py': PythonTranspiler, 'js': JavaScriptTranspiler,
            'c': CTranspiler, 'cpp': CppTranspiler,
            'swift': SwiftTranspiler, 'objc': ObjCTranspiler,
            'objcpp': ObjCppTranspiler, 'asm': AssemblyTranspiler,
            'applescript': AppleScriptTranspiler,
        }
        if target not in transpilers:
            print(f"Unknown target: {target}")
            sys.exit(1)

        transpiler = transpilers[target]()
        code = transpiler.transpile(program)

        if target == 'applescript':
            temp_file = '/tmp/jj_temp.applescript'
            with open(temp_file, 'w') as f:
                f.write(code)
            subprocess.run(['osacompile', '-o', output, temp_file], check=True)
            os.remove(temp_file)
            print(f"Built: {output}")
        elif target == 'py':
            with open(output + '.py', 'w') as f:
                f.write(code)
            print(f"Built: {output}.py (interpreted, no binary)")
        elif target == 'asm':
            asm_file = f'/tmp/{basename}.s'
            obj_file = f'/tmp/{basename}.o'
            with open(asm_file, 'w') as f:
                f.write(code)
            subprocess.run(['as', '-o', obj_file, asm_file], check=True)
            sdk_path = subprocess.check_output(['xcrun', '-sdk', 'macosx', '--show-sdk-path']).decode().strip()
            subprocess.run(['ld', '-o', output, obj_file, '-lSystem', '-syslibroot', sdk_path, '-e', '_main', '-arch', 'arm64'], check=True)
            print(f"Built: {output}")
        else:
            ext = get_file_ext(target)
            src_file = f'/tmp/{basename}{ext}'
            with open(src_file, 'w') as f:
                f.write(code)
            compile_cmd = get_compile_cmd(target, src_file, output)
            if compile_cmd:
                subprocess.run(compile_cmd, check=True)
                print(f"Built: {output}")
            else:
                print(f"No compiler for target: {target}")
                sys.exit(1)

    elif command == 'exec':
        # Transpile + compile + run
        target = sys.argv[3] if len(sys.argv) > 3 else 'c'
        basename = os.path.splitext(os.path.basename(filename))[0]
        output = f'/tmp/{basename}_{target}'

        transpilers = {
            'py': PythonTranspiler, 'js': JavaScriptTranspiler,
            'c': CTranspiler, 'cpp': CppTranspiler,
            'swift': SwiftTranspiler, 'objc': ObjCTranspiler,
            'objcpp': ObjCppTranspiler, 'asm': AssemblyTranspiler,
            'applescript': AppleScriptTranspiler,
        }
        if target not in transpilers:
            print(f"Unknown target: {target}")
            sys.exit(1)

        transpiler = transpilers[target]()
        code = transpiler.transpile(program)

        if target == 'applescript':
            src_file = f'/tmp/{basename}.applescript'
            scpt_file = f'/tmp/{basename}.scpt'
            with open(src_file, 'w') as f:
                f.write(code)
            subprocess.run(['osacompile', '-o', scpt_file, src_file], check=True)
            subprocess.run(['osascript', scpt_file])
        elif target == 'py':
            src_file = f'/tmp/{basename}.py'
            with open(src_file, 'w') as f:
                f.write(code)
            subprocess.run(['python3', src_file])
        elif target == 'js':
            src_file = f'/tmp/{basename}.js'
            with open(src_file, 'w') as f:
                f.write(code)
            # Try node first, fall back to qjs
            result = subprocess.run(['which', 'node'], capture_output=True)
            if result.returncode == 0:
                subprocess.run(['node', src_file])
            else:
                subprocess.run(['qjs', src_file])
        elif target == 'asm':
            asm_file = f'/tmp/{basename}.s'
            obj_file = f'/tmp/{basename}.o'
            with open(asm_file, 'w') as f:
                f.write(code)
            subprocess.run(['as', '-o', obj_file, asm_file], check=True)
            sdk_path = subprocess.check_output(['xcrun', '-sdk', 'macosx', '--show-sdk-path']).decode().strip()
            subprocess.run(['ld', '-o', output, obj_file, '-lSystem', '-syslibroot', sdk_path, '-e', '_main', '-arch', 'arm64'], check=True)
            subprocess.run([output])
        else:
            ext = get_file_ext(target)
            src_file = f'/tmp/{basename}{ext}'
            with open(src_file, 'w') as f:
                f.write(code)
            compile_cmd = get_compile_cmd(target, src_file, output)
            if compile_cmd:
                subprocess.run(compile_cmd, check=True)
                subprocess.run([output])
            else:
                print(f"No compiler for target: {target}")
                sys.exit(1)

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    main()
