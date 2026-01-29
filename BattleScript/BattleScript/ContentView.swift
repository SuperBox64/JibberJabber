import SwiftUI
import JJLib

/// Reads the size of a view and writes it to a binding
struct SizeReader: View {
    let onChange: (CGSize) -> Void
    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(key: SizeKey.self, value: geo.size)
        }
        .onPreferenceChange(SizeKey.self) { onChange($0) }
    }
    private struct SizeKey: PreferenceKey {
        static var defaultValue = CGSize.zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
    }
}

struct ContentView: View {
    @State private var sourceCode = ""
    @State private var selectedExample = ""
    @State private var selectedTab = "jj"
    @State private var transpiledOutputs: [String: String] = [:]
    @State private var runOutput = ""
    @State private var isRunning = false
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 180
    @AppStorage("editorHeight") private var editorHeight: Double = 400

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
            .frame(width: sidebarWidth)
            .background(SizeReader { size in
                if size.width > 0 && abs(size.width - sidebarWidth) > 1 {
                    sidebarWidth = size.width
                }
            })

            // Main content
            VSplitView {
                // Top: editor + transpiled tabs
                EditorTabView(
                    selectedTab: $selectedTab,
                    targets: targets,
                    sourceCode: $sourceCode,
                    transpiledOutputs: $transpiledOutputs,
                    onRun: runCurrentTab
                )
                .frame(height: editorHeight)
                .background(SizeReader { size in
                    if size.height > 0 && abs(size.height - editorHeight) > 1 {
                        editorHeight = size.height
                    }
                })

                // Bottom: output pane
                OutputView(output: runOutput, isRunning: isRunning)
                    .frame(minHeight: 80)
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

        let tab = selectedTab
        let code: String
        if tab == "jj" {
            code = sourceCode
        } else {
            code = transpiledOutputs[tab] ?? ""
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result: String
            if tab == "jj" {
                do {
                    let program = try JJEngine.parse(code)
                    result = JJEngine.interpret(program)
                } catch {
                    result = "Parse error: \(error)"
                }
                DispatchQueue.main.async {
                    updateTranspilation()
                }
            } else {
                if code.isEmpty {
                    result = "No code to run for target: \(tab)"
                } else {
                    result = JJEngine.compileAndRun(code, target: tab)
                    // Reverse transpile back to JJ on successful run
                    if !result.contains("error") && !result.contains("Error") && !result.contains("failed"),
                       let reverser = ReverseTranspilerFactory.transpiler(for: tab),
                       let jjCode = reverser.reverseTranspile(code) {
                        DispatchQueue.main.async {
                            sourceCode = jjCode
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                runOutput = result
                isRunning = false
            }
        }
    }
}
