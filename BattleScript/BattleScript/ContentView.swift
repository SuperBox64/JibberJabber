import SwiftUI
import JJLib

/// Finds and configures NSSplitView from within the view hierarchy
struct SplitViewConfigurator: NSViewRepresentable {
    let sidebarWidth: Double
    let editorHeight: Double
    let onSidebarResize: (Double) -> Void
    let onEditorResize: (Double) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.findAndConfigure(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSSplitViewDelegate {
        let parent: SplitViewConfigurator
        private weak var hSplit: NSSplitView?
        private weak var vSplit: NSSplitView?

        init(_ parent: SplitViewConfigurator) {
            self.parent = parent
        }

        func findAndConfigure(from view: NSView) {
            // Walk up to find the HSplitView (outermost)
            var splits: [NSSplitView] = []
            var current: NSView? = view
            while let next = current?.superview {
                if let sv = next as? NSSplitView {
                    splits.append(sv)
                }
                current = next
            }

            // outermost = HSplitView, inner = VSplitView
            for sv in splits {
                if sv.isVertical {
                    hSplit = sv
                    sv.delegate = self
                    if parent.sidebarWidth > 0 {
                        sv.setPosition(parent.sidebarWidth, ofDividerAt: 0)
                    }
                } else {
                    vSplit = sv
                    sv.delegate = self
                    if parent.editorHeight > 0 {
                        sv.setPosition(parent.editorHeight, ofDividerAt: 0)
                    }
                }
            }
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let sv = notification.object as? NSSplitView else { return }
            if sv === hSplit, sv.subviews.count > 0 {
                let w = sv.subviews[0].frame.width
                if w > 0 { parent.onSidebarResize(w) }
            } else if sv === vSplit, sv.subviews.count > 0 {
                let h = sv.subviews[0].frame.height
                if h > 0 { parent.onEditorResize(h) }
            }
        }
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
                SplitViewConfigurator(
                    sidebarWidth: sidebarWidth,
                    editorHeight: editorHeight,
                    onSidebarResize: { sidebarWidth = $0 },
                    onEditorResize: { editorHeight = $0 }
                )
                .frame(width: 0, height: 0)

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
            .frame(minWidth: 120, maxWidth: 300)

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
                .frame(minHeight: 150)

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
