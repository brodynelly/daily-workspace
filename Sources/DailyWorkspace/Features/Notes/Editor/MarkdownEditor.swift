import AppKit
import DailyCore
import SwiftUI

/// Styles Markdown by changing attributes only. The text itself is never altered.
enum MarkdownStyler {
    /// Patterns are compile-time literals covered by the editor's behaviour; a typo should crash in development.
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let heading = regex(#"^(#{1,6})[ \t]+.*$"#)
    private static let bold = regex(#"\*\*[^*\n]+\*\*"#)
    private static let code = regex(#"`[^`\n]+`"#)
    private static let wikilink = regex(#"!?\[\[[^\]\n]+\]\]"#)
    private static let mdLink = regex(#"\[[^\]\n]+\]\([^)\n]+\)"#)
    private static let bullet = regex(#"^[ \t]*[-*](?= )"#)
    private static let openTask = regex(#"^[ \t]*[-*] \[ \]"#)
    private static let doneTask = regex(#"^[ \t]*[-*] \[[xX]\].*$"#)
    private static let frontmatter = regex(#"\A---\n[\s\S]*?\n---(?=\n|\z)"#)

    static let baseFont = NSFont.systemFont(ofSize: 18)
    static let monoFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)

    /// Luuna roles, resolved per appearance at draw time: body text in ink-body, code at full ink, links
    /// and list marks in the accent text, front matter and done tasks muted.
    static let inkBody = ColorToken.inkBody.nsColor
    static let ink = ColorToken.ink.nsColor
    static let inkMuted = ColorToken.inkMuted.nsColor
    static let accentText = ColorToken.accentText.nsColor

    static var paragraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 7
        p.paragraphSpacing = 8
        return p
    }

    static func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage, !textView.hasMarkedText() else { return }
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)

        storage.beginEditing()
        storage.setAttributes(
            [
                .font: baseFont,
                .foregroundColor: inkBody,
                .paragraphStyle: paragraph,
            ], range: full)

        heading.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            let level = m.range(at: 1).length
            let size = max(18, 30 - CGFloat(level) * 2.5)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .bold), range: m.range)
        }
        bold.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 18, weight: .semibold), range: m.range)
        }
        code.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttributes([.font: monoFont, .foregroundColor: ink], range: m.range)
        }
        wikilink.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.foregroundColor, value: accentText, range: m.range)
        }
        mdLink.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.foregroundColor, value: accentText, range: m.range)
        }
        bullet.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: accentText, range: match.range)
        }
        openTask.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.foregroundColor, value: accentText, range: m.range)
        }
        doneTask.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttributes(
                [
                    .foregroundColor: inkMuted,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                ], range: m.range)
        }
        frontmatter.enumerateMatches(in: storage.string, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttributes([.font: monoFont, .foregroundColor: inkMuted], range: m.range)
        }
        storage.endEditing()

        textView.typingAttributes = [
            .font: baseFont,
            .foregroundColor: inkBody,
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
        tv.textContainerInset = NSSize(width: 34, height: 30)

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
        tv.linkTextAttributes = [
            .foregroundColor: MarkdownStyler.accentText, .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        tv.setAccessibilityLabel("Note editor")

        tv.delegate = context.coordinator
        scroll.documentView = tv
        tv.installOverlay()

        tv.caretPreset = preset
        tv.systemReduceMotion = reduceMotion
        tv.string = text
        MarkdownStyler.apply(to: tv)

        context.coordinator.textView = tv
        context.coordinator.contentStorage = contentStorage  // the layout manager only holds it weakly
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
        var contentStorage: NSTextContentStorage?
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
