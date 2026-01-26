/// JibJab (JJ) Language Interpreter and Transpiler
/// A language designed for AI comprehension
///
/// This is the CLI entry point. The implementation is in the JJ/ directory.

import Foundation

func main() {
    let args = CommandLine.arguments

    if args.count < 3 {
        print("JibJab Language v1.0 (Swift)")
        print("Usage:")
        print("  jjswift run <file.jj>            - Run JJ program")
        print("  jjswift transpile <file.jj> py   - Transpile to Python")
        print("  jjswift transpile <file.jj> js   - Transpile to JavaScript")
        print("  jjswift transpile <file.jj> c    - Transpile to C")
        print("  jjswift transpile <file.jj> asm  - Transpile to ARM64 Assembly")
        print("  jjswift transpile <file.jj> swift - Transpile to Swift")
        print("  jjswift transpile <file.jj> applescript - Transpile to AppleScript")
        print("  jjswift transpile <file.jj> cpp - Transpile to C++")
        print("  jjswift transpile <file.jj> objc - Transpile to Objective-C")
        print("  jjswift transpile <file.jj> objcpp - Transpile to Objective-C++")
        exit(1)
    }

    let command = args[1]
    let filename = args[2]

    // Read source file
    guard let source = try? String(contentsOfFile: filename, encoding: .utf8) else {
        print("Error: Could not read file '\(filename)'")
        exit(1)
    }

    // Lex and parse
    let lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    let parser = Parser(tokens: tokens)

    let program: Program
    do {
        program = try parser.parse()
    } catch {
        print("Parse error: \(error)")
        exit(1)
    }

    if command == "run" {
        let interpreter = Interpreter()
        interpreter.run(program)
    } else if command == "transpile" {
        let target = args.count > 3 ? args[3] : "py"

        switch target {
        case "py":
            let transpiler = PythonTranspiler()
            print(transpiler.transpile(program))
        case "js":
            let transpiler = JavaScriptTranspiler()
            print(transpiler.transpile(program))
        case "c":
            let transpiler = CTranspiler()
            print(transpiler.transpile(program))
        case "asm":
            let transpiler = AssemblyTranspiler()
            print(transpiler.transpile(program))
        case "swift":
            let transpiler = SwiftTranspiler()
            print(transpiler.transpile(program))
        case "applescript":
            let transpiler = AppleScriptTranspiler()
            print(transpiler.transpile(program))
        case "cpp":
            let transpiler = CppTranspiler()
            print(transpiler.transpile(program))
        case "objc":
            let transpiler = ObjCTranspiler()
            print(transpiler.transpile(program))
        case "objcpp":
            let transpiler = ObjCppTranspiler()
            print(transpiler.transpile(program))
        default:
            print("Unknown target: \(target)")
            print("Valid targets: py, js, c, asm, swift, applescript, cpp, objc, objcpp")
            exit(1)
        }
    } else {
        print("Unknown command: \(command)")
        exit(1)
    }
}

main()
