import Foundation
import JJLib

struct JJEngine {
    static func parse(_ source: String) throws -> Program {
        let lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        let parser = Parser(tokens: tokens)
        return try parser.parse()
    }

    static func transpile(_ program: Program, target: String) -> String? {
        guard let t = getTranspiler(target) else { return nil }
        if let cfamily = t as? CFamilyTranspiler { return cfamily.transpile(program) }
        if let py = t as? PythonTranspiler { return py.transpile(program) }
        if let js = t as? JavaScriptTranspiler { return js.transpile(program) }
        if let sw = t as? SwiftTranspiler { return sw.transpile(program) }
        if let asm = t as? AssemblyTranspiler { return asm.transpile(program) }
        if let apple = t as? AppleScriptTranspiler { return apple.transpile(program) }
        return nil
    }

    static func interpret(_ program: Program) -> String {
        let pipe = Pipe()
        let original = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        let interpreter = Interpreter()
        interpreter.run(program)
        fflush(stdout)
        dup2(original, STDOUT_FILENO)
        close(original)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func compileAndRun(_ code: String, target: String) -> String {
        let cfg = loadTarget(target)
        let basename = "battlescript_\(target)"
        let ext = cfg.ext
        let srcFile = "/tmp/\(basename)\(ext)"
        let outFile = "/tmp/\(basename)_out"

        do {
            try code.write(toFile: srcFile, atomically: true, encoding: .utf8)
        } catch {
            return "Error writing source: \(error)"
        }

        if target == "asm" {
            return compileAndRunAsm(srcFile, outFile)
        }

        if let compileCmd = cfg.compile {
            let cmd = compileCmd.map {
                $0.replacingOccurrences(of: "{src}", with: srcFile)
                  .replacingOccurrences(of: "{out}", with: outFile)
            }
            let (ok, err) = runProcess(cmd)
            if !ok { return "Compile error:\n\(err)" }

            if target == "applescript" {
                if let runCmd = cfg.run {
                    let rCmd = runCmd.map { $0.replacingOccurrences(of: "{src}", with: outFile) }
                    let (_, output) = runProcess(rCmd)
                    return output
                }
            }
            return runBinary(outFile)
        } else if let runCmd = cfg.run {
            let cmd = runCmd.map { $0.replacingOccurrences(of: "{src}", with: srcFile) }
            let (_, output) = runProcess(cmd)
            return output
        }
        return "No compiler or runner for target: \(target)"
    }

    private static func compileAndRunAsm(_ srcFile: String, _ outFile: String) -> String {
        let objFile = srcFile.replacingOccurrences(of: ".s", with: ".o")
        let (asOk, asErr) = runProcess(["/usr/bin/as", "-o", objFile, srcFile])
        if !asOk { return "Assembly error:\n\(asErr)" }

        let (sdkOk, sdkOut) = runProcess(["/usr/bin/xcrun", "-sdk", "macosx", "--show-sdk-path"])
        if !sdkOk { return "SDK error:\n\(sdkOut)" }
        let sdkPath = sdkOut.trimmingCharacters(in: .whitespacesAndNewlines)

        let (ldOk, ldErr) = runProcess(["/usr/bin/ld", "-o", outFile, objFile, "-lSystem", "-syslibroot", sdkPath, "-e", "_main", "-arch", "arm64"])
        if !ldOk { return "Link error:\n\(ldErr)" }

        return runBinary(outFile)
    }

    private static func runBinary(_ path: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "Run error: \(error)"
        }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out + (err.isEmpty ? "" : "\nstderr: \(err)")
    }

    private static func runProcess(_ args: [String]) -> (Bool, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, "Process error: \(error)")
        }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let ok = process.terminationStatus == 0
        return (ok, ok ? out : (err + out))
    }

    private static func getTranspiler(_ target: String) -> Any? {
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
}
