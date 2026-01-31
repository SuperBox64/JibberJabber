import SwiftUI
import JJLib

struct ContentView: View {
    @State private var sourceCode = ""
    @State private var selectedExample = ""
    @State private var selectedTab = "jj"
    @State private var transpiledOutputs: [String: String] = [:]
    @State private var runOutput = ""
    @State private var isRunning = false
    @State private var userHasEdited = false
    @State private var transpileWork: DispatchWorkItem?
    @State private var runWork: DispatchWorkItem?
    @State private var showDependencyCheck = true
    @State private var dependencyStatus: DependencyStatus?

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
    ]

    var body: some View {
        PersistentHSplitView(autosaveName: "MainHSplit", leftMinWidth: 115, leftMaxWidth: 220) {
            // Left sidebar - example selector
            VStack(alignment: .leading, spacing: 0) {
                Text("Examples")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 9)
                    .padding(.bottom, 9.5)
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
                // Bottom: output pane
                OutputView(output: runOutput, isRunning: isRunning)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .overlay {
            DependencyOverlay(status: dependencyStatus, isVisible: $showDependencyCheck)
        }
        .onAppear {
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
                    var outputs: [String: String] = [:]
                    for target in targets where target != "jj" {
                        outputs[target] = errorMsg
                    }
                    transpiledOutputs = outputs
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
        runOutput = "Stopped"
    }

    private func runCurrentTab() {
        isRunning = true
        runOutput = ""

        let tab = selectedTab
        let code: String
        if tab == "jj" {
            code = sourceCode
        } else {
            code = transpiledOutputs[tab] ?? ""
        }

        let work = DispatchWorkItem {
            let result: String
            if tab == "jj" {
                do {
                    let program = try JJEngine.parse(code)
                    result = JJEngine.interpret(program)
                    DispatchQueue.main.async {
                        updateTranspilation()
                    }
                } catch {
                    result = "Error: \(error)"
                }
            } else {
                if code.isEmpty {
                    result = "No code to run for target: \(tab)"
                } else if code.hasPrefix("// Parse error") || code.hasPrefix("// Transpilation failed") {
                    result = code.replacingOccurrences(of: "// ", with: "")
                } else {
                    result = JJEngine.compileAndRun(code, target: tab)
                    if userHasEdited,
                       !result.contains("error") && !result.contains("Error") && !result.contains("failed"),
                       let reverser = ReverseTranspilerFactory.transpiler(for: tab),
                       let jjCode = reverser.reverseTranspile(code) {
                        DispatchQueue.main.async {
                            userHasEdited = false
                            sourceCode = jjCode
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                if self.runWork?.isCancelled != true {
                    runOutput = result
                    isRunning = false
                }
            }
        }
        runWork = work
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }
}
