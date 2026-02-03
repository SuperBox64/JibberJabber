import Foundation
import JJLib

struct JJEngine {
    static var runningProcess: Process?
    private static let processLock = NSLock()

    static func stopRunning() {
        processLock.lock()
        defer { processLock.unlock() }
        if let p = runningProcess, p.isRunning {
            p.terminate()
        }
        runningProcess = nil
    }

    static func parse(_ source: String) throws -> Program {
        let lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        let parser = Parser(tokens: tokens)
        return try parser.parse()
    }

    static func transpile(_ program: Program, target: String) -> String? {
        guard let t = getTranspiler(target) as? Transpiling else { return nil }
        return t.transpile(program)
    }

    static func interpret(_ program: Program) -> String {
        let pipe = Pipe()
        let original = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        let interpreter = Interpreter()
        var errorMsg: String?
        do {
            try interpreter.run(program)
        } catch {
            errorMsg = "Runtime error: \(error)"
        }
        fflush(stdout)
        dup2(original, STDOUT_FILENO)
        close(original)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if let errorMsg = errorMsg {
            return output.isEmpty ? errorMsg : output + "\n" + errorMsg
        }
        return output
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
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            processLock.lock()
            runningProcess = process
            processLock.unlock()
            try process.run()
        } catch {
            processLock.lock()
            runningProcess = nil
            processLock.unlock()
            return "Run error: \(error)"
        }
        // Read both pipes concurrently to avoid deadlock when output exceeds pipe buffer
        var errData = Data()
        let errQueue = DispatchQueue(label: "stderr-reader")
        errQueue.async { errData = errPipe.fileHandleForReading.readDataToEndOfFile() }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        errQueue.sync {} // wait for stderr read to finish
        process.waitUntilExit()
        processLock.lock()
        runningProcess = nil
        processLock.unlock()
        if process.terminationReason == .uncaughtSignal {
            return "Stopped"
        }
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return (out + err).trimmingCharacters(in: .newlines)
    }

    private static func runProcess(_ args: [String]) -> (Bool, String) {
        let process = Process()
        // If the first arg is already an absolute path, use it directly.
        // Otherwise use /usr/bin/env to resolve it (like the CLI does).
        if args[0].hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: args[0])
            process.arguments = Array(args.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = args
        }
        // Augment PATH so tools (qjsc, go, etc.) are found from Xcode
        var env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        let extra = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/go/bin",
            "\(home)/go/bin",
            "/opt/local/bin",
        ].joined(separator: ":")
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        do {
            processLock.lock()
            runningProcess = process
            processLock.unlock()
            try process.run()
        } catch {
            processLock.lock()
            runningProcess = nil
            processLock.unlock()
            return (false, "Process error: \(error)")
        }
        // Read both pipes concurrently to avoid deadlock when output exceeds pipe buffer
        var errData = Data()
        let errQueue = DispatchQueue(label: "stderr-reader")
        errQueue.async { errData = errPipe.fileHandleForReading.readDataToEndOfFile() }
        let outData = pipe.fileHandleForReading.readDataToEndOfFile()
        errQueue.sync {} // wait for stderr read to finish
        process.waitUntilExit()
        processLock.lock()
        runningProcess = nil
        processLock.unlock()
        if process.terminationReason == .uncaughtSignal {
            return (false, "Stopped")
        }
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        let ok = process.terminationStatus == 0
        let combined = (out + err).trimmingCharacters(in: .whitespacesAndNewlines)
        return (ok, ok ? (combined.isEmpty ? out : combined) : (err + out))
    }

    private static let transpilerRegistry: [String: () -> Any] = [
        "py": { PythonTranspiler() },
        "js": { JavaScriptTranspiler() },
        "c": { CTranspiler() },
        "cpp": { CppTranspiler() },
        "swift": { SwiftTranspiler() },
        "objc": { ObjCTranspiler() },
        "objcpp": { ObjCppTranspiler() },
        "asm": { AssemblyTranspiler() },
        "applescript": { AppleScriptTranspiler() },
        "go": { GoTranspiler() },
    ]

    private static func getTranspiler(_ target: String) -> Any? {
        transpilerRegistry[target]?()
    }
}
