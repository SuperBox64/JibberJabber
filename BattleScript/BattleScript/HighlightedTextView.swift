import SwiftUI
import AppKit

struct HighlightedTextView: NSViewRepresentable {
    @Binding var text: String
    let language: String

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
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.font = SyntaxTheme.font
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.delegate = context.coordinator
        textView.string = text
        context.coordinator.setTextView(textView)

        if let ts = textView.textStorage {
            context.coordinator.applyHighlighting(ts)
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

        // Update language if tab changed
        context.coordinator.updateLanguage(language)

        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            if let ts = textView.textStorage {
                context.coordinator.applyHighlighting(ts)
            }
            let safeSel = NSRange(
                location: min(sel.location, textView.string.count),
                length: 0
            )
            textView.setSelectedRange(safeSel)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightedTextView
        private var currentLanguage: String
        private var highlighter: SyntaxHighlighting?
        private var appearanceObservation: NSKeyValueObservation?
        private weak var observedTextView: NSTextView?

        init(_ parent: HighlightedTextView) {
            self.parent = parent
            self.currentLanguage = parent.language
            self.highlighter = SyntaxHighlighterFactory.highlighter(for: parent.language)
            super.init()
            appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { self?.rehighlight() }
            }
        }

        deinit { appearanceObservation?.invalidate() }

        func setTextView(_ tv: NSTextView) { observedTextView = tv }

        private func rehighlight() {
            guard let tv = observedTextView, let ts = tv.textStorage else { return }
            applyHighlighting(ts)
        }

        func updateLanguage(_ language: String) {
            if language != currentLanguage {
                currentLanguage = language
                highlighter = SyntaxHighlighterFactory.highlighter(for: language)
            }
        }

        func applyHighlighting(_ textStorage: NSTextStorage) {
            highlighter?.highlight(textStorage)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string

            if let ts = textView.textStorage {
                applyHighlighting(ts)
            }
        }
    }
}
