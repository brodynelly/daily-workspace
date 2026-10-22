import SwiftUI
import AppKit
import DailyCore

/// Styles Markdown by changing attributes only. The text itself is never altered.
enum MarkdownStyler {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let heading = regex(#"^(#{1,6})[ \t]+.*$"#)
    private static let bold = regex(#"\*\*[^*\n]+\*\*"#)
    private static let code = regex(#"`[^`\n]+`"#)
    private static let wikilink = regex(#"!?\[\[[^\]\n]+\]\]"#)
    private static let mdLink = regex(#"\[[^\]\n]+\]\([^)\n]+\)"#)
    private static let openTask = regex(#"^[ \t]*[-*] \[ \]"#)
    private static let doneTask = regex(#"^[ \t]*[-*] \[[xX]\].*$"#)
    private static let frontmatter = regex(#"\A---\n[\s\S]*?\n---(?=\n|\z)"#)

    static let baseFont = NSFont.systemFont(ofSize: 15)
    static let monoFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    static var paragraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 4
        return p
    }

    static func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage, !textView.hasMarkedText() else { return }
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)

        storage.beginEditing()
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ], range: full)

        heading.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            let level = m.range(at: 1).length
            let size = max(15, 26 - CGFloat(level) * 2.5)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .bold), range: m.range)
        }
        bold.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 15, weight: .bold), range: m.range)
        }
        code.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttributes([.font: monoFont, .foregroundColor: NSColor.systemPink], range: m.range)
        }
        wikilink.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: m.range)
        }
        mdLink.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: m.range)
        }
        openTask.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: m.range)
        }
        doneTask.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            ], range: m.range)
        }
        frontmatter.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttributes([.font: monoFont, .foregroundColor: NSColor.secondaryLabelColor], range: m.range)
        }
        storage.endEditing()

        textView.typingAttributes = [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
    }
}

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    /// Identifies the open document so undo history resets when a different note loads.
    var documentID: URL?
    var preset: CaretPreset
    var reduceMotion: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        // Built from parts so the subclass uses a designated initialiser (TextKit 2).
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.textContainer = container
        let tv = CaretTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 400), textContainer: container)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainerInset = NSSize(width: 24, height: 20)

        // Notes must be preserved byte for byte: no smart substitutions, no rich text.
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.drawsBackground = false
        tv.setAccessibilityLabel("Note editor")

        tv.delegate = context.coordinator
        scroll.documentView = tv
        tv.installOverlay()

        tv.caretPreset = preset
        tv.systemReduceMotion = reduceMotion
        tv.string = text
        MarkdownStyler.apply(to: tv)

        context.coordinator.textView = tv
        context.coordinator.documentID = documentID
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        context.coordinator.parent = self
        tv.caretPreset = preset
        tv.systemReduceMotion = reduceMotion

        let switchedDocument = context.coordinator.documentID != documentID
        if switchedDocument || (tv.string != text && !context.coordinator.isEditing) {
            let selection = tv.selectedRange()
            tv.string = text
            if switchedDocument {
                tv.undoManager?.removeAllActions()
                tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            } else {
                let length = (text as NSString).length
                tv.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            }
            context.coordinator.documentID = documentID
            MarkdownStyler.apply(to: tv)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: CaretTextView?
        var documentID: URL?
        var isEditing = false

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            isEditing = true
            parent.text = tv.string
            isEditing = false
            MarkdownStyler.apply(to: tv)
        }
    }
}
