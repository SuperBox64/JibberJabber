import SwiftUI
import JJLib

struct ContentView: View {
    @State private var sourceCode = ""
    @State private var selectedExample = ""
    @State private var selectedTab = "jj"
    @State private var transpiledOutputs: [String: String] = [:]
    @State private var runOutput = ""
    @State private var isRunning = false

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
        HSplitView {
            // Left sidebar - example selector
            VStack(alignment: .leading, spacing: 0) {
                Text("Examples")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                List(examples, id: \.file, selection: $selectedExample) { example in
                    Text(example.name)
                        .tag(example.file)
                }
                .listStyle(.sidebar)
                .onChange(of: selectedExample) { _, newValue in
                    loadExample(newValue)
                }
            }
            .frame(minWidth: 150, idealWidth: 180, maxWidth: 220)

            // Main content
            VSplitView {
                // Top: editor + transpiled tabs
                VStack(spacing: 0) {
                    EditorTabView(
                        selectedTab: $selectedTab,
                        targets: targets,
                        sourceCode: $sourceCode,
                        transpiledOutputs: transpiledOutputs,
                        onRun: runCurrentTab
                    )
                }
                .frame(minHeight: 300)

                // Bottom: output pane
                OutputView(output: runOutput, isRunning: isRunning)
                    .frame(minHeight: 120, idealHeight: 180)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
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
        guard !sourceCode.isEmpty else {
            transpiledOutputs = [:]
            return
        }
        do {
            let program = try JJEngine.parse(sourceCode)
            var outputs: [String: String] = [:]
            for target in targets where target != "jj" {
                outputs[target] = JJEngine.transpile(program, target: target) ?? "// Transpilation failed"
            }
            transpiledOutputs = outputs
        } catch {
            for target in targets where target != "jj" {
                transpiledOutputs[target] = "// Parse error: \(error)"
            }
        }
    }

    private func runCurrentTab() {
        isRunning = true
        runOutput = ""

        DispatchQueue.global(qos: .userInitiated).async {
            let result: String
            do {
                let program = try JJEngine.parse(sourceCode)
                if selectedTab == "jj" {
                    result = JJEngine.interpret(program)
                } else {
                    guard let code = JJEngine.transpile(program, target: selectedTab) else {
                        result = "Transpilation failed for target: \(selectedTab)"
                        DispatchQueue.main.async {
                            runOutput = result
                            isRunning = false
                        }
                        return
                    }
                    result = JJEngine.compileAndRun(code, target: selectedTab)
                }
            } catch {
                result = "Parse error: \(error)"
            }
            DispatchQueue.main.async {
                runOutput = result
                isRunning = false
            }
        }
    }
}
