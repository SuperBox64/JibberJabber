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
        print("  jjswift run <file.jj>                - Run JJ program (interpreter)")
        print("  jjswift compile <file.jj> [output]   - Compile direct to native binary")
        print("  jjswift asm <file.jj> [output]       - Compile via asm transpiler + as/ld")
        print("  jjswift transpile <file.jj> <target> - Transpile to target language")
        print("")
        print("Transpile targets: py, js, c, cpp, asm, swift, applescript [output], objc, objcpp")
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
    } else if command == "asm" {
        // Compile via assembly transpiler + system as/ld
        let outputPath = args.count > 3 ? args[3] : "a.out"

        // Generate assembly from AST
        let transpiler = AssemblyTranspiler()
        let asmCode = transpiler.transpile(program)

        // Write to temp file
        let tempAsm = "/tmp/jj_\(ProcessInfo.processInfo.processIdentifier).s"
        let tempObj = "/tmp/jj_\(ProcessInfo.processInfo.processIdentifier).o"

        do {
            try asmCode.write(toFile: tempAsm, atomically: true, encoding: .utf8)
        } catch {
            print("Error writing assembly: \(error)")
            exit(1)
        }

        // Assemble
        let asProcess = Process()
        asProcess.executableURL = URL(fileURLWithPath: "/usr/bin/as")
        asProcess.arguments = ["-o", tempObj, tempAsm]

        do {
            try asProcess.run()
            asProcess.waitUntilExit()
            if asProcess.terminationStatus != 0 {
                print("Assembly failed")
                exit(1)
            }
        } catch {
            print("Error running assembler: \(error)")
            exit(1)
        }

        // Link
        let sdkPath = Process()
        sdkPath.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        sdkPath.arguments = ["-sdk", "macosx", "--show-sdk-path"]
        let sdkPipe = Pipe()
        sdkPath.standardOutput = sdkPipe

        var sdkRoot = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
        do {
            try sdkPath.run()
            sdkPath.waitUntilExit()
            let data = sdkPipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                sdkRoot = path
            }
        } catch {}

        let ldProcess = Process()
        ldProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ld")
        ldProcess.arguments = [
            "-o", outputPath,
            tempObj,
            "-lSystem",
            "-syslibroot", sdkRoot,
            "-e", "_main",
            "-arch", "arm64"
        ]

        do {
            try ldProcess.run()
            ldProcess.waitUntilExit()
            if ldProcess.terminationStatus != 0 {
                print("Linking failed")
                exit(1)
            }
        } catch {
            print("Error running linker: \(error)")
            exit(1)
        }

        // Clean up temp files
        try? FileManager.default.removeItem(atPath: tempAsm)
        try? FileManager.default.removeItem(atPath: tempObj)

        print("Compiled: \(outputPath)")

    } else if command == "compile" {
        // True native compilation: JJ -> AST -> Machine Code -> Mach-O (no external tools)
        let outputPath = args.count > 3 ? args[3] : "a.out"

        let compiler = NativeCompiler()
        do {
            try compiler.compile(program, outputPath: outputPath)
            print("Compiled: \(outputPath)")
        } catch {
            print("Compilation error: \(error)")
            exit(1)
        }

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
            let code = transpiler.transpile(program)
            let output = args.count > 4 ? args[4] : "a.scpt"
            let tempFile = "/tmp/jj_temp.applescript"
            do {
                try code.write(toFile: tempFile, atomically: true, encoding: .utf8)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
                process.arguments = ["-o", output, tempFile]
                try process.run()
                process.waitUntilExit()
                try? FileManager.default.removeItem(atPath: tempFile)
                if process.terminationStatus == 0 {
                    print("Compiled to \(output)")
                } else {
                    print("osacompile failed")
                    exit(1)
                }
            } catch {
                print("Error: \(error)")
                exit(1)
            }
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
