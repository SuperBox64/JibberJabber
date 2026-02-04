import Foundation
@preconcurrency import JJLib

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

    static func interpret(_ program: Program, outputCallback: ((String) -> Void)? = nil) -> String {
        let interpreter = Interpreter()
        var outputLines: [String] = []

        // Collect output and send to callback in real-time
        interpreter.outputHandler = { text in
            outputLines.append(text)
            outputCallback?(outputLines.joined(separator: "\n"))
        }

        // Use AppleScript dialogs for input (fallback)
        interpreter.inputProvider = { prompt in
            let escapedPrompt = prompt.replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
                display dialog "\(escapedPrompt)" default answer "" buttons {"Cancel", "OK"} default button "OK"
                text returned of result
                """
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                let result = scriptObject.executeAndReturnError(&error)
                if error == nil {
                    return result.stringValue
                }
            }
            return nil  // User cancelled or error
        }

        var errorMsg: String?
        do {
            try interpreter.run(program)
        } catch {
            errorMsg = "Runtime error: \(error)"
        }

        let output = outputLines.joined(separator: "\n")
        if let errorMsg = errorMsg {
            return output.isEmpty ? errorMsg : output + "\n" + errorMsg
        }
        return output
    }

    /// Async interpreter with terminal-style input using CheckedContinuation
    static func interpretAsync(
        _ program: Program,
        outputCallback: @escaping (String) -> Void,
        inputCallback: @escaping (String) async -> String?
    ) async -> String {
        return await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let interpreter = Interpreter()
                var outputLines: [String] = []

                // Real-time output
                interpreter.outputHandler = { text in
                    outputLines.append(text)
                    let output = outputLines.joined(separator: "\n")
                    DispatchQueue.main.async {
                        outputCallback(output)
                    }
                }

                // Async input bridged to sync callback using semaphore
                interpreter.inputProvider = { prompt in
                    let semaphore = DispatchSemaphore(value: 0)
                    var result: String? = nil

                    // Request input on main thread via async
                    Task { @MainActor in
                        result = await inputCallback(prompt)
                        semaphore.signal()
                    }

                    // Block this background thread until input arrives
                    semaphore.wait()
                    return result
                }

                var errorMsg: String?
                do {
                    try interpreter.run(program)
                } catch {
                    errorMsg = "Runtime error: \(error)"
                }

                let output = outputLines.joined(separator: "\n")
                let finalResult: String
                if let errorMsg = errorMsg {
                    finalResult = output.isEmpty ? errorMsg : output + "\n" + errorMsg
                } else {
                    finalResult = output
                }

                continuation.resume(returning: finalResult)
            }
        }
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
            return compileAndRunAsm(srcFile, outFile, interactive: false)
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
            return runBinary(outFile, interactive: false)
        } else if let runCmd = cfg.run {
            let cmd = runCmd.map { $0.replacingOccurrences(of: "{src}", with: srcFile) }
            let (_, output) = runProcess(cmd)
            return output
        }
        return "No compiler or runner for target: \(target)"
    }

    /// Async version of compileAndRun that supports UI-based input via stdin
    static func compileAndRunAsync(
        _ code: String,
        target: String,
        outputCallback: @escaping (String) -> Void,
        inputCallback: @escaping () async -> String?
    ) async -> String {
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

        // Compile if needed
        if let compileCmd = cfg.compile {
            let cmd = compileCmd.map {
                $0.replacingOccurrences(of: "{src}", with: srcFile)
                  .replacingOccurrences(of: "{out}", with: outFile)
            }
            let (ok, err) = runProcess(cmd)
            if !ok { return "Compile error:\n\(err)" }

            if target == "applescript" {
                // AppleScript uses its own dialogs
                if let runCmd = cfg.run {
                    let rCmd = runCmd.map { $0.replacingOccurrences(of: "{src}", with: outFile) }
                    let (_, output) = runProcess(rCmd)
                    return output
                }
            }
            return await runBinaryWithInput(outFile, outputCallback: outputCallback, inputCallback: inputCallback)
        } else if let runCmd = cfg.run {
            // Interpreted language - run with stdin support
            let cmd = runCmd.map { $0.replacingOccurrences(of: "{src}", with: srcFile) }
            return await runCommandWithInput(cmd, outputCallback: outputCallback, inputCallback: inputCallback)
        }
        return "No compiler or runner for target: \(target)"
    }

    /// Run a binary with stdin/stdout piped for interactive input
    private static func runBinaryWithInput(
        _ path: String,
        outputCallback: @escaping (String) -> Void,
        inputCallback: @escaping () async -> String?
    ) async -> String {
        return await runCommandWithInput([path], outputCallback: outputCallback, inputCallback: inputCallback)
    }

    /// Run a command with stdin/stdout piped for interactive input
    private static func runCommandWithInput(
        _ args: [String],
        outputCallback: @escaping (String) -> Void,
        inputCallback: @escaping () async -> String?
    ) async -> String {
        let process = Process()
        if args[0].hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: args[0])
            process.arguments = Array(args.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = args
        }

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/local/go/bin", "\(home)/go/bin"].joined(separator: ":")
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stdoutPipe

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

        var outputLines: [String] = []
        let outputHandle = stdoutPipe.fileHandleForReading
        let inputHandle = stdinPipe.fileHandleForWriting

        // Read output in background and show input field when needed
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = Data()
                while process.isRunning {
                    let available = outputHandle.availableData
                    if available.isEmpty {
                        // No output - might be waiting for input, give UI a chance
                        Thread.sleep(forTimeInterval: 0.1)
                        // Check if still no output after a bit - show input field
                        let moreData = outputHandle.availableData
                        if moreData.isEmpty && process.isRunning {
                            // Likely waiting for input - request it
                            Task { @MainActor in
                                if let input = await inputCallback() {
                                    let inputData = (input + "\n").data(using: .utf8) ?? Data()
                                    try? inputHandle.write(contentsOf: inputData)
                                }
                            }
                        } else {
                            buffer.append(moreData)
                        }
                    } else {
                        buffer.append(available)
                    }

                    if let text = String(data: buffer, encoding: .utf8) {
                        let lines = text.components(separatedBy: "\n")
                        outputLines = lines
                        DispatchQueue.main.async {
                            outputCallback(text)
                        }
                    }
                }

                // Read remaining output
                let remaining = outputHandle.readDataToEndOfFile()
                buffer.append(remaining)
                let finalOutput = String(data: buffer, encoding: .utf8) ?? ""

                processLock.lock()
                runningProcess = nil
                processLock.unlock()

                if process.terminationReason == .uncaughtSignal {
                    continuation.resume(returning: "Stopped")
                } else {
                    continuation.resume(returning: finalOutput.trimmingCharacters(in: .newlines))
                }
            }
        }
    }

    private static func compileAndRunAsm(_ srcFile: String, _ outFile: String, interactive: Bool = false) -> String {
        let objFile = srcFile.replacingOccurrences(of: ".s", with: ".o")
        let (asOk, asErr) = runProcess(["/usr/bin/as", "-o", objFile, srcFile])
        if !asOk { return "Assembly error:\n\(asErr)" }

        let (sdkOk, sdkOut) = runProcess(["/usr/bin/xcrun", "-sdk", "macosx", "--show-sdk-path"])
        if !sdkOk { return "SDK error:\n\(sdkOut)" }
        let sdkPath = sdkOut.trimmingCharacters(in: .whitespacesAndNewlines)

        let (ldOk, ldErr) = runProcess(["/usr/bin/ld", "-o", outFile, objFile, "-lSystem", "-syslibroot", sdkPath, "-e", "_main", "-arch", "arm64"])
        if !ldOk { return "Link error:\n\(ldErr)" }

        return runBinary(outFile, interactive: interactive)
    }

    /// Check if code uses input (for determining if we need interactive mode)
    static func usesInput(_ code: String) -> Bool {
        // Check for common input patterns across languages
        return code.contains("fgets(") ||           // C
               code.contains("std::getline(") ||    // C++
               code.contains("readLine()") ||       // Swift
               code.contains("fmt.Scanln") ||       // Go
               code.contains("input(") ||           // Python
               code.contains("prompt(") ||          // JavaScript
               code.contains("display dialog") ||   // AppleScript
               code.contains("~>slurp")             // JJ source
    }

    /// Run binary in Terminal.app for interactive programs
    static func runInTerminal(_ path: String) -> String {
        let script = """
            tell application "Terminal"
                activate
                do script "\(path); echo ''; echo 'Press Enter to close...'; read"
            end tell
            """
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
        }
        return "Running in Terminal...\n(Interactive programs run in Terminal for stdin support)"
    }

    private static func runBinary(_ path: String, interactive: Bool = false) -> String {
        if interactive {
            return runInTerminal(path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        // Ensure NSLog/os_log output reaches stderr even when not in a terminal
        var env = ProcessInfo.processInfo.environment
        env["OS_ACTIVITY_DT_MODE"] = "YES"
        env["CFLOG_FORCE_STDERR"] = "YES"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe  // merge stderr into stdout
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
        let outData = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        processLock.lock()
        runningProcess = nil
        processLock.unlock()
        if process.terminationReason == .uncaughtSignal {
            return "Stopped"
        }
        return (String(data: outData, encoding: .utf8) ?? "").trimmingCharacters(in: .newlines)
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
