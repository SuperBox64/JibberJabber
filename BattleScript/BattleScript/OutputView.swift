import SwiftUI
import AppKit

/// NSTextView wrapper for easy text selection like a terminal
struct OutputTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.4)
        textView.textColor = NSColor.labelColor
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.4)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let wasAtBottom = scrollView.contentView.bounds.origin.y >=
            (textView.bounds.height - scrollView.contentView.bounds.height - 20)
        textView.string = text
        // Auto-scroll to bottom if was already at bottom
        if wasAtBottom {
            textView.scrollToEndOfDocument(nil)
        }
    }
}

struct OutputView: View {
    let output: String
    let isRunning: Bool
    var waitingForInput: Bool = false
    var inputPrompt: String = ""
    var onInputSubmit: ((String) -> Void)? = nil

    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color(nsColor: .separatorColor)
                .frame(height: 1)
            HStack {
                Text("Output")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))

            Divider()

            OutputTextView(text: output.isEmpty ? (waitingForInput ? "Input below >" : (isRunning ? "Running..." : "Press Run to execute...")) : output)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                if isRunning && !waitingForInput {
                    ProgressView()
                        .scaleEffect(0.5)
                        .padding(8)
                }
            }

            // Input field when waiting for input
            if waitingForInput {
                Divider()
                HStack(spacing: 8) {
                    Text(inputPrompt.isEmpty ? "Input:" : inputPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    TextField("Type here and press Enter...", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .focused($inputFocused)
                        .onSubmit {
                            onInputSubmit?(inputText)
                            inputText = ""
                        }
                    Button("Send") {
                        onInputSubmit?(inputText)
                        inputText = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .onChange(of: waitingForInput) { _, waiting in
            if waiting {
                inputFocused = true
            }
        }
    }
}
