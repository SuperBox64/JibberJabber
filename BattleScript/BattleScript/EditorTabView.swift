import SwiftUI
import AppKit

/// NSViewRepresentable wrapping NSTextView with smart quotes disabled and JJ syntax highlighting
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var showLineNumbers: Bool

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

        if let ruler = LineNumberRulerView(textView: textView) {
            ruler.clipsToBounds = true
            scrollView.verticalRulerView = ruler
        }
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = showLineNumbers

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if scrollView.rulersVisible != showLineNumbers {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                if let ruler = scrollView.verticalRulerView {
                    let targetWidth: CGFloat = showLineNumbers ? ruler.requiredThickness : 0
                    ruler.animator().frame.size.width = targetWidth
                }
            } completionHandler: {
                scrollView.rulersVisible = self.showLineNumbers
                scrollView.verticalRulerView?.needsDisplay = true
            }
            if showLineNumbers {
                scrollView.rulersVisible = true
            }
        }
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
    @Binding var userHasEdited: Bool
    @AppStorage("editMode") var editMode = false
    let isRunning: Bool
    let onRun: () -> Void
    let onStop: () -> Void
    @AppStorage("highlighterStyle") private var highlighterStyle = "Xcode"
    @AppStorage("showLineNumbers") var showLineNumbers = true
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
                Spacer().frame(width: 4)
                ForEach(targets, id: \.self) { target in
                    Button(action: { selectedTab = target }) {
                        Text(target.uppercased())
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(selectedTab == target ? .bold : .regular)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(selectedTab == target ? (tabColors[target] ?? .gray).opacity(0.3) : Color.clear)
                    .foregroundColor(selectedTab == target ? .primary : .secondary)
                    .cornerRadius(6)
                }
                Spacer(minLength: 0)
                if isRunning {
                    Button(action: onStop) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.system(.caption, design: .monospaced))
                            .fixedSize()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.2))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                } else {
                    Button(action: onRun) {
                        Label("Run", systemImage: "play.fill")
                            .font(.system(.caption, design: .monospaced))
                            .fixedSize()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }
            }
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content area
            Group {
                if selectedTab == "jj" {
                    CodeEditor(text: $sourceCode, showLineNumbers: showLineNumbers)
                } else {
                    HighlightedTextView(
                        text: Binding(
                            get: { transpiledOutputs[selectedTab] ?? "// No output" },
                            set: {
                                transpiledOutputs[selectedTab] = $0
                                userHasEdited = true
                            }
                        ),
                        language: selectedTab,
                        showLineNumbers: showLineNumbers
                    )
                }
            }
            .id(refreshID)

            // Bottom bar with line numbers toggle + style picker
            HStack(spacing: 0) {
                Button(action: {
                    showLineNumbers.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: showLineNumbers ? "number.square.fill" : "number.square")
                            .font(.system(.caption))
                        Text("Lines")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .background(showLineNumbers ? Color.blue.opacity(0.3) : Color.clear)
                    .foregroundColor(showLineNumbers ? .primary : .secondary)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
                Button(action: {
                    editMode.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: editMode ? "pencil.circle.fill" : "pencil.circle")
                            .font(.system(.caption))
                        Text("Edit")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .background(editMode ? Color.orange.opacity(0.3) : Color.clear)
                    .foregroundColor(editMode ? .primary : .secondary)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
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
                            .contentShape(Rectangle())
                            .background(highlighterStyle == style.rawValue ? Color.purple.opacity(0.3) : Color.clear)
                            .foregroundColor(Color.white.opacity(0.8))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 4)
            }
            .padding(.vertical, 2)
            .offset(y: 1)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        }
    }
}
