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
        textView.string = text
    }
}

struct OutputView: View {
    let output: String
    let isRunning: Bool

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

            OutputTextView(text: output.isEmpty ? (isRunning ? "Running..." : "Press Run to execute...") : output)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.5)
                        .padding(8)
                }
            }
        }
    }
}
