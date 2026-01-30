/// JibJab (JJ) Language Interpreter and Transpiler
/// A language designed for AI comprehension
///
/// This is the CLI entry point. The implementation is in the JJ/ directory.

import Foundation
import JJLib

func getTranspiler(_ target: String) -> Any? {
    switch target {
    case "py": return PythonTranspiler()
    case "js": return JavaScriptTranspiler()
    case "c": return CTranspiler()
    case "cpp": return CppTranspiler()
    case "swift": return SwiftTranspiler()
    case "objc": return ObjCTranspiler()
    case "objcpp": return ObjCppTranspiler()
    case "asm": return AssemblyTranspiler()
    case "applescript": return AppleScriptTranspiler()
    case "go": return GoTranspiler()
    default: return nil
    }
}

func transpileCode(_ target: String, _ program: Program) -> String? {
    guard let t = getTranspiler(target) else {
        print("Unknown target: \(target)")
        print("Valid targets: py, js, c, cpp, asm, swift, applescript, objc, objcpp, go")
        return nil
    }
    if let cfamily = t as? CFamilyTranspiler { return cfamily.transpile(program) }
    if let py = t as? PythonTranspiler { return py.transpile(program) }
    if let js = t as? JavaScriptTranspiler { return js.transpile(program) }
    if let sw = t as? SwiftTranspiler { return sw.transpile(program) }
    if let asm = t as? AssemblyTranspiler { return asm.transpile(program) }
    if let apple = t as? AppleScriptTranspiler { return apple.transpile(program) }
    return nil
}

func writeSrc(_ code: String, _ basename: String, _ target: String) -> String {
    let ext = loadTarget(target)?.ext ?? ""
    let srcFile = "/tmp/\(basename)\(ext)"
    try? code.write(toFile: srcFile, atomically: true, encoding: .utf8)
    return srcFile
}

func compileSrc(_ target: String, _ srcFile: String, _ outFile: String) -> Bool {
    if target == "asm" {
        let objFile = srcFile.replacingOccurrences(of: ".s", with: ".o")
        let asProc = Process()
        asProc.executableURL = URL(fileURLWithPath: "/usr/bin/as")
        asProc.arguments = ["-o", objFile, srcFile]
        try? asProc.run()
        asProc.waitUntilExit()
        guard asProc.terminationStatus == 0 else { return false }
        let sdkProc = Process()
        sdkProc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        sdkProc.arguments = ["-sdk", "macosx", "--show-sdk-path"]
        let pipe = Pipe()
        sdkProc.standardOutput = pipe
        try? sdkProc.run()
        sdkProc.waitUntilExit()
        let sdkPath = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ldProc = Process()
        ldProc.executableURL = URL(fileURLWithPath: "/usr/bin/ld")
        ldProc.arguments = ["-o", outFile, objFile, "-lSystem", "-syslibroot", sdkPath, "-e", "_main", "-arch", "arm64"]
        try? ldProc.run()
        ldProc.waitUntilExit()
        return ldProc.terminationStatus == 0
    }
    guard let cfg = loadTarget(target) else { return false }
    guard let compileCmd = cfg.compile else { return false }
    let cmd = compileCmd.map { $0.replacingOccurrences(of: "{src}", with: srcFile).replacingOccurrences(of: "{out}", with: outFile) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = cmd
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch { return false }
}

func runSrc(_ target: String, _ srcFile: String) -> Bool {
    guard let cfg = loadTarget(target) else { return false }
    guard let runCmd = cfg.run else { return false }
    let cmd = runCmd.map { $0.replacingOccurrences(of: "{src}", with: srcFile) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = cmd
    try? process.run()
    process.waitUntilExit()
    return true
}

func runBinary(_ path: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    try? process.run()
    process.waitUntilExit()
}

func main() {
    let args = CommandLine.arguments

    if args.count < 3 {
        print("JibJab Language v1.0 (Swift)")
        print("Usage:")
        print("  jjswift run <file.jj>                - Run JJ program (interpreter)")
        print("  jjswift compile <file.jj> [output]   - Compile direct to native binary")
        print("  jjswift asm <file.jj> [output]       - Compile via asm transpiler + as/ld")
        print("  jjswift transpile <file.jj> <target> - Transpile to target language")
        print("  jjswift build <file.jj> <target> [output] - Transpile + compile")
        print("  jjswift exec <file.jj> <target>      - Transpile + compile + run")
        print("")
        print("Targets: py, js, c, cpp, asm, swift, applescript, objc, objcpp, go")
        exit(1)
    }

    let command = args[1]
    let filename = args[2]

    guard let source = try? String(contentsOfFile: filename, encoding: .utf8) else {
        print("Error: Could not read file '\(filename)'")
        exit(1)
    }

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
        do {
            try interpreter.run(program)
        } catch {
            print("Runtime error: \(error)")
            exit(1)
        }

    } else if command == "compile" {
        let outputPath = args.count > 3 ? args[3] : "a.out"
        let compiler = NativeCompiler()
        do {
            try compiler.compile(program, outputPath: outputPath)
            print("Compiled: \(outputPath)")
        } catch {
            print("Compilation error: \(error)")
            exit(1)
        }

    } else if command == "asm" {
        let outputPath = args.count > 3 ? args[3] : "a.out"
        guard let code = transpileCode("asm", program) else { exit(1) }
        let basename = (outputPath as NSString).lastPathComponent
        let srcFile = "/tmp/\(basename).s"
        try? code.write(toFile: srcFile, atomically: true, encoding: .utf8)
        if compileSrc("asm", srcFile, outputPath) {
            print("Compiled: \(outputPath)")
        } else {
            print("Assembly failed")
            exit(1)
        }

    } else if command == "transpile" {
        let target = args.count > 3 ? args[3] : "py"
        guard let code = transpileCode(target, program) else { exit(1) }
        print(code)

    } else if command == "build" {
        let target = args.count > 3 ? args[3] : "c"
        let basename = (filename as NSString).lastPathComponent.replacingOccurrences(of: ".jj", with: "")
        let output = args.count > 4 ? args[4] : "\(basename)_\(target)"

        guard let code = transpileCode(target, program) else { exit(1) }
        let srcFile = writeSrc(code, basename, target)

        guard let cfg = loadTarget(target) else {
            print("Error: could not load config for target '\(target)'")
            exit(1)
        }
        let hasCompiler = cfg.compile != nil

        if hasCompiler || target == "asm" {
            if compileSrc(target, srcFile, output) {
                print("Built: \(output)")
            } else {
                print("Build failed for target: \(target)")
                exit(1)
            }
        } else if cfg.run != nil {
            print("Built: \(srcFile) (interpreted)")
        } else {
            print("No compiler for target: \(target)")
            exit(1)
        }

    } else if command == "exec" {
        let target = args.count > 3 ? args[3] : "c"
        let basename = (filename as NSString).lastPathComponent.replacingOccurrences(of: ".jj", with: "")
        let output = "/tmp/\(basename)_\(target)"

        guard let code = transpileCode(target, program) else { exit(1) }
        let srcFile = writeSrc(code, basename, target)

        guard let cfg = loadTarget(target) else {
            print("Error: could not load config for target '\(target)'")
            exit(1)
        }
        let hasCompiler = cfg.compile != nil
        let hasRunner = cfg.run != nil

        if hasCompiler && hasRunner {
            if compileSrc(target, srcFile, output) {
                if target == "applescript" {
                    _ = runSrc(target, output)
                } else {
                    runBinary(output)
                }
            } else {
                print("Build failed for target: \(target)")
                exit(1)
            }
        } else if hasCompiler {
            if compileSrc(target, srcFile, output) {
                runBinary(output)
            } else {
                print("Build failed for target: \(target)")
                exit(1)
            }
        } else if hasRunner {
            _ = runSrc(target, srcFile)
        } else if target == "asm" {
            if compileSrc("asm", srcFile, output) {
                runBinary(output)
            } else {
                print("Build failed for asm")
                exit(1)
            }
        } else {
            print("No compiler or runner for target: \(target)")
            exit(1)
        }

    } else {
        print("Unknown command: \(command)")
        exit(1)
    }
}

main()
