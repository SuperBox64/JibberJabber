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

        // Apply initial highlighting
        if let ts = textView.textStorage {
            context.coordinator.highlighter.highlight(ts)
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
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

        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string

            // Apply syntax highlighting after text changes
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
                            .background(selectedTab == target ? (tabColors[target] ?? .gray).opacity(0.2) : Color.clear)
                            .foregroundColor(selectedTab == target ? (tabColors[target] ?? .primary) : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Picker("", selection: $highlighterStyle) {
                    ForEach(HighlighterStyle.allCases, id: \.rawValue) { style in
                        Text(style.rawValue).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .onChange(of: highlighterStyle) { _, _ in
                    refreshID = UUID()
                }
                .padding(.trailing, 4)
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
        }
    }
}
