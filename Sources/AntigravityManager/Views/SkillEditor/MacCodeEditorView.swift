import SwiftUI
import AppKit

public struct MacCodeEditorView: NSViewRepresentable {
    @Binding var text: String
    var isReadOnly: Bool

    public init(text: Binding<String>, isReadOnly: Bool = false) {
        self._text = text
        self.isReadOnly = isReadOnly
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainerInset = NSSize(width: 10, height: 10)

        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.drawsBackground = true
        textView.isEditable = !isReadOnly
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.delegate = context.coordinator

        // Setup vertical ruler with line numbers
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak ruler] _ in
            MainActor.assumeIsolated {
                ruler?.needsDisplay = true
            }
        }

        textView.string = text
        if let ts = textView.textStorage, ts.length > 0 {
            ts.addAttribute(.foregroundColor, value: NSColor.textColor, range: NSRange(location: 0, length: ts.length))
            ts.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: NSRange(location: 0, length: ts.length))
        }
        context.coordinator.isUpdating = false

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text && !context.coordinator.isUpdating {
            textView.string = text
            if let ts = textView.textStorage, ts.length > 0 {
                ts.addAttribute(.foregroundColor, value: NSColor.textColor, range: NSRange(location: 0, length: ts.length))
                ts.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: NSRange(location: 0, length: ts.length))
            }
            scrollView.verticalRulerView?.needsDisplay = true
        }
        textView.isEditable = !isReadOnly
    }

    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacCodeEditorView
        var isUpdating: Bool = false

        init(_ parent: MacCodeEditorView) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            parent.text = textView.string
            isUpdating = false
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
    }
}

@MainActor
public final class LineNumberRulerView: NSRulerView {
    public override var isFlipped: Bool { true }
    private weak var textView: NSTextView?

    public init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 42
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = self.textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        // Background - strictly within the ruler bounds so it never covers the text
        let rulerRect = NSRect(x: 0, y: rect.minY, width: ruleThickness, height: rect.height)
        NSColor.controlBackgroundColor.setFill()
        rulerRect.fill()

        // Separator line
        let separatorRect = NSRect(x: ruleThickness - 1, y: rect.minY, width: 1, height: rect.height)
        NSColor.separatorColor.setFill()
        separatorRect.fill()

        let visibleRect = textView.visibleRect
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let text = textView.string as NSString
        let textLength = text.length

        guard textLength > 0 else {
            drawLineNumber("1", at: convert(NSPoint(x: 0, y: 0), from: textView).y + 2)
            return
        }

        var lineNumber = 1
        var index = 0
        while index < visibleCharRange.location && index < textLength {
            var lineEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: nil, for: NSRange(location: index, length: 0))
            lineNumber += 1
            index = lineEnd
        }

        index = visibleCharRange.location
        while index < NSMaxRange(visibleCharRange) && index < textLength {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let y = convert(NSPoint(x: 0, y: lineRect.origin.y), from: textView).y

            drawLineNumber("\(lineNumber)", at: y + 2)

            var lineEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: nil, for: NSRange(location: index, length: 0))
            index = lineEnd
            lineNumber += 1
        }
    }

    private func drawLineNumber(_ string: String, at y: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let attrString = NSAttributedString(string: string, attributes: attrs)
        let size = attrString.size()
        let x = ruleThickness - size.width - 8
        attrString.draw(at: NSPoint(x: x, y: y))
    }
}
