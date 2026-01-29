import SwiftUI
import AppKit

/// NSViewRepresentable wrapping NSTextView with smart quotes disabled and JJ syntax highlighting
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.font = SyntaxTheme.font
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.string = text
        context.coordinator.setTextView(textView)

        // Apply initial highlighting
        if let ts = textView.textStorage {
            context.coordinator.highlighter.highlight(ts)
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        scrollView.drawsBackground = false

        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = UserDefaults.standard.bool(forKey: "showLineNumbers")

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let show = UserDefaults.standard.bool(forKey: "showLineNumbers")
        scrollView.rulersVisible = show
        scrollView.verticalRulerView?.needsDisplay = true
        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            if let ts = textView.textStorage {
                context.coordinator.highlighter.highlight(ts)
            }
            let safeSel = NSRange(
                location: min(sel.location, textView.string.count),
                length: 0
            )
            textView.setSelectedRange(safeSel)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        let highlighter = JJHighlighter()
        private var appearanceObservation: NSKeyValueObservation?
        private weak var observedTextView: NSTextView?

        init(_ parent: CodeEditor) {
            self.parent = parent
            super.init()
            appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { self?.rehighlight() }
            }
        }

        deinit { appearanceObservation?.invalidate() }

        func setTextView(_ tv: NSTextView) { observedTextView = tv }

        private func rehighlight() {
            guard let tv = observedTextView, let ts = tv.textStorage else { return }
            highlighter.highlight(ts)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string

            if let ts = textView.textStorage {
                highlighter.highlight(ts)
            }
        }
    }
}

struct EditorTabView: View {
    @Binding var selectedTab: String
    let targets: [String]
    @Binding var sourceCode: String
    @Binding var transpiledOutputs: [String: String]
    let onRun: () -> Void
    @AppStorage("highlighterStyle") private var highlighterStyle = "Xcode"
    @State private var refreshID = UUID()

    private let tabColors: [String: Color] = [
        "jj": .purple,
        "py": .blue,
        "js": .yellow,
        "c": .gray,
        "cpp": .teal,
        "swift": .orange,
        "objc": .mint,
        "objcpp": .yellow,
        "go": .cyan,
        "asm": .green,
        "applescript": .indigo,
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(targets, id: \.self) { target in
                    Button(action: { selectedTab = target }) {
                        Text(target.uppercased())
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(selectedTab == target ? .bold : .regular)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(selectedTab == target ? (tabColors[target] ?? .gray).opacity(0.3) : Color.clear)
                            .foregroundColor(selectedTab == target ? Color.white.opacity(0.85) : .secondary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(action: onRun) {
                    Label("Run", systemImage: "play.fill")
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content area
            Group {
                if selectedTab == "jj" {
                    CodeEditor(text: $sourceCode)
                } else {
                    HighlightedTextView(
                        text: Binding(
                            get: { transpiledOutputs[selectedTab] ?? "// No output" },
                            set: { transpiledOutputs[selectedTab] = $0 }
                        ),
                        language: selectedTab
                    )
                }
            }
            .id(refreshID)

            // Bottom bar with style picker
            HStack(spacing: 0) {
                Spacer()
                ForEach(HighlighterStyle.allCases, id: \.rawValue) { style in
                    Button(action: {
                        highlighterStyle = style.rawValue
                        refreshID = UUID()
                    }) {
                        Text(style.rawValue)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(highlighterStyle == style.rawValue ? .bold : .regular)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(highlighterStyle == style.rawValue ? Color.purple.opacity(0.3) : Color.clear)
                            .foregroundColor(highlighterStyle == style.rawValue ? Color.white.opacity(0.85) : .secondary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 4)
            }
            .padding(.vertical, 2)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}
