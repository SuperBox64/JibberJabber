import SwiftUI
@preconcurrency import JJLib

struct ContentView: View {
    @State private var sourceCode = ""
    @State private var selectedExample = "hello"
    @State private var selectedTab = "jj"
    @State private var transpiledOutputs: [String: String] = [:]
    @State private var runOutputs: [String: String] = [:]
    @State private var runningTabs: Set<String> = []  // Per-tab running state
    @State private var userHasEdited = false
    @AppStorage("editMode") private var editMode = false
    @State private var transpileWork: DispatchWorkItem?
    @State private var runWork: DispatchWorkItem?
    @State private var showDependencyCheck = true
    @State private var dependencyStatus: DependencyStatus?
    @State private var waitingForInputTabs: Set<String> = []  // Per-tab input state
    @State private var inputPrompts: [String: String] = [:]  // Per-tab prompts
    @State private var inputContinuations: [String: CheckedContinuation<String?, Never>] = [:]  // Per-tab continuations

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
                    isRunning: runningTabs.contains(selectedTab),
                    onRun: runCurrentTab,
                    onStop: stopRunning
                )
            } bottom: {
                // Bottom: output pane with input support
                OutputView(
                    output: runOutputs[selectedTab] ?? "",
                    isRunning: runningTabs.contains(selectedTab),
                    waitingForInput: waitingForInputTabs.contains(selectedTab),
                    inputPrompt: inputPrompts[selectedTab] ?? "",
                    onInputSubmit: { input in
                        inputContinuations[selectedTab]?.resume(returning: input)
                        inputContinuations[selectedTab] = nil
                        // Keep waitingForInput true - it will be set false when process ends
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
        let tab = selectedTab
        runWork?.cancel()
        runWork = nil
        JJEngine.stopRunning()
        runningTabs.remove(tab)
        waitingForInputTabs.remove(tab)
        inputContinuations[tab] = nil
        runOutputs[tab] = "Stopped"
    }

    private func runCurrentTab() {
        let tab = selectedTab
        runningTabs.insert(tab)
        runOutputs[tab] = ""
        let code: String
        if tab == "jj" {
            code = sourceCode
        } else {
            code = transpiledOutputs[tab] ?? ""
        }

        // For JJ tab, use async interpreter with terminal-style input
        if tab == "jj" {
            Task {
                do {
                    let program = try JJEngine.parse(code)
                    let result = await JJEngine.interpretAsync(program,
                        outputCallback: { output in
                            self.runOutputs[tab] = output
                        },
                        inputCallback: { prompt in
                            self.inputPrompts[tab] = prompt
                            self.waitingForInputTabs.insert(tab)
                            return await withCheckedContinuation { continuation in
                                self.inputContinuations[tab] = continuation
                            }
                        }
                    )
                    await MainActor.run {
                        self.runOutputs[tab] = result
                        self.runningTabs.remove(tab)
                        self.waitingForInputTabs.remove(tab)
                        updateTranspilation()
                    }
                } catch {
                    await MainActor.run {
                        self.runOutputs[tab] = "Error: \(error)"
                        self.runningTabs.remove(tab)
                        self.waitingForInputTabs.remove(tab)
                    }
                }
            }
            return
        }

        // Check if code uses input - use async version for interactive programs
        if JJEngine.usesInput(code) {
            // Don't show input field yet - wait for prompt from program
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
                        promptCallback: { prompt in
                            // Program is requesting input with this prompt
                            self.inputPrompts[tab] = prompt
                            self.waitingForInputTabs.insert(tab)
                        },
                        inputCallback: {
                            // Wait for user input
                            return await withCheckedContinuation { continuation in
                                self.inputContinuations[tab] = continuation
                            }
                        }
                    )
                }
                await MainActor.run {
                    self.runOutputs[tab] = result
                    self.runningTabs.remove(tab)
                    self.waitingForInputTabs.remove(tab)
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
                    runningTabs.remove(tab)
                }
            }
        }
        runWork = work
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }
}
