import AppKit

class LineNumberRulerView: NSRulerView {
    private var textView: NSTextView? { clientView as? NSTextView }
    private let gutterFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private var textObserver: NSObjectProtocol?

    init?(textView: NSTextView) {
        guard let scrollView = textView.enclosingScrollView else { return nil }
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        ruleThickness = 36

        textObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView, queue: .main
        ) { [weak self] _ in self?.needsDisplay = true }
    }

    required init(coder: NSCoder) { fatalError() }

    deinit {
        if let obs = textObserver { NotificationCenter.default.removeObserver(obs) }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let bgColor = isDark
            ? NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1.0)
            : NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
        let numColor = isDark
            ? NSColor(red: 0.45, green: 0.45, blue: 0.50, alpha: 1.0)
            : NSColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1.0)

        bgColor.setFill()
        rect.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: gutterFont,
            .foregroundColor: numColor
        ]

        let text = tv.string as NSString
        guard let sv = scrollView else { return }
        let visibleRect = sv.contentView.bounds
        let textContainerInset = tv.textContainerInset

        // Handle empty text - still show line number 1
        guard text.length > 0 else {
            let numStr = "1" as NSString
            let strSize = numStr.size(withAttributes: attrs)
            let x = ruleThickness - strSize.width - 6
            let lineHeight = lm.defaultLineHeight(for: gutterFont)
            let y = textContainerInset.height - visibleRect.origin.y + (lineHeight - strSize.height) / 2.0 + 2.0
            numStr.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
            return
        }

        let visibleGlyphRange = lm.glyphRange(forBoundingRect: visibleRect, in: tc)
        let visibleCharRange = lm.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        // Count lines up to visible range start
        var lineNumber = 1
        var idx = 0
        while idx < visibleCharRange.location {
            let lineRange = text.lineRange(for: NSRange(location: idx, length: 0))
            lineNumber += 1
            idx = NSMaxRange(lineRange)
        }

        // Draw line numbers for visible lines
        idx = visibleCharRange.location
        while idx <= NSMaxRange(visibleCharRange) {
            let lineRange = text.lineRange(for: NSRange(location: idx, length: 0))
            let glyphIdx = lm.glyphIndexForCharacter(at: idx)
            var lineRect = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            lineRect.origin.y += textContainerInset.height
            lineRect.origin.y -= visibleRect.origin.y

            let numStr = "\(lineNumber)" as NSString
            let strSize = numStr.size(withAttributes: attrs)
            let x = ruleThickness - strSize.width - 6
            let y = lineRect.origin.y + (lineRect.height - strSize.height) / 2.0
            numStr.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)

            lineNumber += 1
            idx = NSMaxRange(lineRange)
            if idx >= text.length { break }
        }
    }
}
