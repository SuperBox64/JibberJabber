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
from jj.lexer import load_target_config

TRANSPILERS = {
    'py': PythonTranspiler, 'js': JavaScriptTranspiler,
    'c': CTranspiler, 'cpp': CppTranspiler,
    'swift': SwiftTranspiler, 'objc': ObjCTranspiler,
    'objcpp': ObjCppTranspiler, 'asm': AssemblyTranspiler,
    'applescript': AppleScriptTranspiler,
}


def get_target_cfg(target):
    try:
        return load_target_config(target)
    except FileNotFoundError:
        return None


def get_file_ext(target):
    cfg = get_target_cfg(target)
    return cfg['ext'] if cfg and 'ext' in cfg else '.txt'


def transpile_code(target, program):
    if target not in TRANSPILERS:
        print(f"Unknown target: {target}")
        print(f"Valid targets: {', '.join(TRANSPILERS.keys())}")
        sys.exit(1)
    return TRANSPILERS[target]().transpile(program)


def write_src(code, basename, target):
    ext = get_file_ext(target)
    src_file = f'/tmp/{basename}{ext}'
    with open(src_file, 'w') as f:
        f.write(code)
    return src_file


def compile_src(target, src_file, out_file):
    """Compile using JSON config or special asm handling."""
    if target == 'asm':
        obj_file = src_file.replace('.s', '.o')
        subprocess.run(['as', '-o', obj_file, src_file], check=True)
        sdk_path = subprocess.check_output(['xcrun', '-sdk', 'macosx', '--show-sdk-path']).decode().strip()
        subprocess.run(['ld', '-o', out_file, obj_file, '-lSystem', '-syslibroot', sdk_path, '-e', '_main', '-arch', 'arm64'], check=True)
        return True
    cfg = get_target_cfg(target)
    if cfg and 'compile' in cfg:
        cmd = [a.replace('{src}', src_file).replace('{out}', out_file) for a in cfg['compile']]
        subprocess.run(cmd, check=True)
        return True
    return False


def run_src(target, src_file):
    """Run using JSON config."""
    cfg = get_target_cfg(target)
    if cfg and 'run' in cfg:
        cmd = [a.replace('{src}', src_file) for a in cfg['run']]
        subprocess.run(cmd)
        return True
    return False


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
        print(f"Targets: {', '.join(TRANSPILERS.keys())}")
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
        code = AssemblyTranspiler().transpile(program)
        basename = os.path.basename(output)
        src_file = f'/tmp/{basename}.s'
        with open(src_file, 'w') as f:
            f.write(code)
        compile_src('asm', src_file, output)
        print(f"Compiled to {output}")
    elif command == 'transpile':
        target = sys.argv[3] if len(sys.argv) > 3 else 'py'
        code = transpile_code(target, program)
        print(code)

    elif command == 'build':
        target = sys.argv[3] if len(sys.argv) > 3 else 'c'
        basename = os.path.splitext(os.path.basename(filename))[0]
        output = sys.argv[4] if len(sys.argv) > 4 else f'{basename}_{target}'

        code = transpile_code(target, program)
        src_file = write_src(code, basename, target)

        cfg = get_target_cfg(target)
        has_compiler = cfg and 'compile' in cfg

        if has_compiler or target == 'asm':
            compile_src(target, src_file, output)
            print(f"Built: {output}")
        elif cfg and 'run' in cfg:
            # Interpreted language (py) - src file is the output
            print(f"Built: {src_file} (interpreted)")
        else:
            print(f"No compiler for target: {target}")
            sys.exit(1)

    elif command == 'exec':
        target = sys.argv[3] if len(sys.argv) > 3 else 'c'
        basename = os.path.splitext(os.path.basename(filename))[0]
        output = f'/tmp/{basename}_{target}'

        code = transpile_code(target, program)
        src_file = write_src(code, basename, target)

        cfg = get_target_cfg(target)
        has_compiler = cfg and 'compile' in cfg
        has_runner = cfg and 'run' in cfg

        if has_compiler and has_runner:
            # Compile then run the source (e.g. js with qjsc, applescript with osacompile)
            # For applescript, run the compiled output with osascript
            compile_src(target, src_file, output)
            if target == 'applescript':
                run_src(target, output)
            else:
                subprocess.run([output])
        elif has_compiler:
            # Compile to binary and run
            compile_src(target, src_file, output)
            subprocess.run([output])
        elif has_runner:
            # Interpreted - just run the source
            run_src(target, src_file)
        elif target == 'asm':
            compile_src('asm', src_file, output)
            subprocess.run([output])
        else:
            print(f"No compiler or runner for target: {target}")
            sys.exit(1)

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    main()
