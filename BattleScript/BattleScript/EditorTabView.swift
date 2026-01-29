import SwiftUI
import AppKit

/// NSViewRepresentable wrapping NSTextView with smart quotes disabled
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
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
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
            textView.setSelectedRange(sel)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

struct EditorTabView: View {
    @Binding var selectedTab: String
    let targets: [String]
    @Binding var sourceCode: String
    let transpiledOutputs: [String: String]
    let onRun: () -> Void

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
            if selectedTab == "jj" {
                CodeEditor(text: $sourceCode)
            } else {
                ScrollView {
                    Text(transpiledOutputs[selectedTab] ?? "// No output")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(tabColors[selectedTab] ?? .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }
}
