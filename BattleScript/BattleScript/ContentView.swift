import SwiftUI
import JJLib

struct ContentView: View {
    @State private var sourceCode = ""
    @State private var selectedExample = "hello"
    @State private var selectedTab = "jj"
    @State private var transpiledOutputs: [String: String] = [:]
    @State private var runOutputs: [String: String] = [:]
    @State private var isRunning = false
    @State private var userHasEdited = false
    @AppStorage("editMode") private var editMode = false
    @State private var transpileWork: DispatchWorkItem?
    @State private var runWork: DispatchWorkItem?
    @State private var showDependencyCheck = true
    @State private var dependencyStatus: DependencyStatus?
    @State private var waitingForInput = false
    @State private var inputPrompt = ""
    @State private var inputContinuation: CheckedContinuation<String?, Never>?

    private let targets = ["jj", "py", "js", "c", "cpp", "swift", "objc", "objcpp", "go", "asm", "applescript"]
    private let examples: [(name: String, file: String)] = [
        ("Hello World", "hello"),
        ("Variables", "variables"),
        ("FizzBuzz", "fizzbuzz"),
        ("Fibonacci", "fibonacci"),
        ("Arrays", "arrays"),
        ("Comparisons", "comparisons"),
        ("Dictionaries", "dictionaries"),
        ("Enums", "enums"),
        ("Numbers", "numbers"),
        ("Tuples", "tuples"),
        ("TryOops", "trycatch"),
        ("Logging", "logging"),
        ("Constants", "constants"),
        ("Numbers", "numbers"),
        ("Guessinggame", "guessinggame"),
        ("Input", "input"),
    ]

    var body: some View {
        PersistentHSplitView(autosaveName: "MainHSplit", leftMinWidth: 115, leftMaxWidth: 220) {
            // Left sidebar - example selector
            VStack(alignment: .leading, spacing: 0) {
                Text("Examples")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.top, 9)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                Color(nsColor: .separatorColor)
                    .frame(height: 1)
                List(examples, id: \.file, selection: $selectedExample) { example in
                    Text(example.name)
                        .padding(.leading, 4)
                        .tag(example.file)
                }
                .listStyle(.sidebar)
                .onChange(of: selectedExample) { _, newValue in
                    loadExample(newValue)
                }
            }
        } right: {
            // Main content
            PersistentVSplitView(autosaveName: "MainVSplit", topMinHeight: 150, bottomMinHeight: 80) {
                // Top: editor + transpiled tabs
                EditorTabView(
                    selectedTab: $selectedTab,
                    targets: targets,
                    sourceCode: $sourceCode,
                    transpiledOutputs: $transpiledOutputs,
                    userHasEdited: $userHasEdited,
                    isRunning: isRunning,
                    onRun: runCurrentTab,
                    onStop: stopRunning
                )
            } bottom: {
                // Bottom: output pane with input support
                OutputView(
                    output: runOutputs[selectedTab] ?? "",
                    isRunning: isRunning,
                    waitingForInput: waitingForInput,
                    inputPrompt: inputPrompt,
                    onInputSubmit: { input in
                        inputContinuation?.resume(returning: input)
                        inputContinuation = nil
                        waitingForInput = false
                        inputPrompt = ""
                    }
                )
            }
        }
        .frame(minWidth: 640, minHeight: 450)
        .overlay {
            DependencyOverlay(status: dependencyStatus, isVisible: $showDependencyCheck)
        }
        .onAppear {
            loadExample(selectedExample)
            DispatchQueue.global(qos: .userInitiated).async {
                let status = DependencyChecker.check()
                DispatchQueue.main.async {
                    dependencyStatus = status
                }
            }
        }
        .onChange(of: sourceCode) { _, _ in
            updateTranspilation()
        }
    }

    private func loadExample(_ name: String) {
        guard !name.isEmpty else { return }
        let basePath = Bundle.main.resourcePath ?? ""
        let path = basePath + "/examples/\(name).jj"
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            sourceCode = content
        }
    }

    private func updateTranspilation() {
        transpileWork?.cancel()
        guard !sourceCode.isEmpty else {
            transpiledOutputs = [:]
            return
        }
        let code = sourceCode
        let work = DispatchWorkItem {
            do {
                let program = try JJEngine.parse(code)
                var outputs: [String: String] = [:]
                for target in targets where target != "jj" {
                    outputs[target] = JJEngine.transpile(program, target: target) ?? "// Transpilation failed"
                }
                DispatchQueue.main.async {
                    transpiledOutputs = outputs
                }
            } catch {
                let errorMsg = "// Parse error: \(error)"
                DispatchQueue.main.async {
                    runOutputs["jj"] = errorMsg
                    selectedTab = "jj"
                }
            }
        }
        transpileWork = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func stopRunning() {
        runWork?.cancel()
        runWork = nil
        JJEngine.stopRunning()
        isRunning = false
        runOutputs[selectedTab] = "Stopped"
    }

    private func runCurrentTab() {
        let tab = selectedTab
        isRunning = true
        runOutputs[tab] = ""
        let code: String
        if tab == "jj" {
            code = sourceCode
        } else {
            code = transpiledOutputs[tab] ?? ""
        }

        // For JJ tab, use async interpreter with UI input
        if tab == "jj" {
            Task {
                do {
                    let program = try JJEngine.parse(code)
                    let result = await JJEngine.interpretAsync(program,
                        outputCallback: { output in
                            self.runOutputs[tab] = output
                        },
                        inputCallback: { prompt in
                            // Show input field and wait for user
                            self.inputPrompt = prompt
                            self.waitingForInput = true
                            return await withCheckedContinuation { continuation in
                                self.inputContinuation = continuation
                            }
                        }
                    )
                    await MainActor.run {
                        self.runOutputs[tab] = result
                        self.isRunning = false
                        updateTranspilation()
                    }
                } catch {
                    await MainActor.run {
                        self.runOutputs[tab] = "Error: \(error)"
                        self.isRunning = false
                    }
                }
            }
            return
        }

        // Check if code uses input - use async version for interactive programs
        if JJEngine.usesInput(code) {
            Task {
                let result: String
                if code.isEmpty {
                    result = "No code to run for target: \(tab)"
                } else if code.hasPrefix("// Parse error") || code.hasPrefix("// Transpilation failed") {
                    result = code.replacingOccurrences(of: "// ", with: "")
                } else {
                    result = await JJEngine.compileAndRunAsync(code, target: tab,
                        outputCallback: { output in
                            self.runOutputs[tab] = output
                        },
                        inputCallback: {
                            self.inputPrompt = "Input:"
                            self.waitingForInput = true
                            return await withCheckedContinuation { continuation in
                                self.inputContinuation = continuation
                            }
                        }
                    )
                }
                await MainActor.run {
                    self.runOutputs[tab] = result
                    self.isRunning = false
                }
            }
            return
        }

        let work = DispatchWorkItem {
            let result: String
            if code.isEmpty {
                result = "No code to run for target: \(tab)"
            } else if code.hasPrefix("// Parse error") || code.hasPrefix("// Transpilation failed") {
                result = code.replacingOccurrences(of: "// ", with: "")
            } else {
                result = JJEngine.compileAndRun(code, target: tab)
                if userHasEdited, !editMode,
                   !result.contains("error") && !result.contains("Error") && !result.contains("failed"),
                   let reverser = ReverseTranspilerFactory.transpiler(for: tab),
                   let jjCode = reverser.reverseTranspile(code) {
                    DispatchQueue.main.async {
                        userHasEdited = false
                        sourceCode = jjCode
                    }
                }
            }
            DispatchQueue.main.async {
                if self.runWork?.isCancelled != true {
                    runOutputs[tab] = result
                    isRunning = false
                }
            }
        }
        runWork = work
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }
}
