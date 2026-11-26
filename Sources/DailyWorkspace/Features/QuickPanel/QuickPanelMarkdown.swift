import SwiftUI

/// Block-level Markdown for AI answers: headings, bullet and numbered lists, fenced code, quotes and rules,
/// with inline bold, italics, code and links. Unknown syntax falls back to plain text.
enum QuickPanelMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(indent: Int, text: String)
    case numbered(indent: Int, number: String, text: String)
    case code(language: String, text: String)
    case quote(String)
    case rule

    static func parse(_ markdown: String) -> [QuickPanelMarkdownBlock] {
        var blocks: [QuickPanelMarkdownBlock] = []
        var paragraph: [String] = []
        var code: (language: String, lines: [String])?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }

        for raw in markdown.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if var open = code {
                if line.hasPrefix("```") {
                    blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n")))
                    code = nil
                } else {
                    open.lines.append(raw)
                    code = open
                }
                continue
            }
            if line.hasPrefix("```") {
                flush()
                code = (String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces), [])
            } else if line.isEmpty {
                flush()
            } else if let block = Self.block(line, indent: raw.prefix { $0 == " " }.count / 2) {
                flush()
                blocks.append(block)
            } else {
                paragraph.append(line)
            }
        }
        if let open = code { blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    /// A single-line block, or nil when the line continues a paragraph.
    private static func block(_ line: String, indent: Int) -> QuickPanelMarkdownBlock? {
        if let heading = heading(line) { return heading }
        if ["---", "***", "___"].contains(line) { return .rule }
        if let rest = bullet(line) { return .bullet(indent: indent, text: rest) }
        if let (number, rest) = numbered(line) { return .numbered(indent: indent, number: number, text: rest) }
        if line.hasPrefix(">") { return .quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func heading(_ line: String) -> QuickPanelMarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return .heading(level: hashes, text: String(line.dropFirst(hashes + 1)))
    }

    private static func bullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func numbered(_ line: String) -> (String, String)? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (String(digits), String(rest.dropFirst(2)))
    }
}

/// Renders an answer with the panel's palette. `compact` tightens spacing for the sidebar.
struct QuickPanelMarkdownView: View {
    let text: String
    var compact = false
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            ForEach(Array(QuickPanelMarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func render(_ block: QuickPanelMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(.system(size: level == 1 ? 16 : level == 2 ? 14.5 : 13.5, weight: .semibold))
                .foregroundStyle(level <= 2 ? Ink.title : Ink.cyan)
                .padding(.top, compact ? 2 : 4)
        case .paragraph(let text):
            Text(Self.inline(text)).foregroundStyle(Ink.footer).lineSpacing(2)
        case .bullet(let indent, let text):
            row(marker: indent == 0 ? "•" : "◦", indent: indent, text: text)
        case .numbered(let indent, let number, let text):
            row(marker: "\(number).", indent: indent, text: text)
        case .code(let language, let text):
            VStack(alignment: .leading, spacing: 4) {
                if !language.isEmpty {
                    Text(language).font(.system(size: 10, weight: .medium)).foregroundStyle(Ink.meta)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Ink.primary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.header, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Ink.idleRule.opacity(0.35)))
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(Ink.gold.opacity(0.7)).frame(width: 2)
                Text(Self.inline(text)).foregroundStyle(Ink.meta).italic()
            }
            .fixedSize(horizontal: false, vertical: true)
        case .rule:
            Rectangle().fill(Ink.idleRule.opacity(0.4)).frame(height: 1).padding(.vertical, 2)
        }
    }

    private func row(marker: String, indent: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(marker).foregroundStyle(Ink.gold).frame(minWidth: 12, alignment: .trailing)
            Text(Self.inline(text)).foregroundStyle(Ink.footer).lineSpacing(2)
        }
        .padding(.leading, CGFloat(indent) * 14)
    }

    /// Inline Markdown with bold in the primary colour, code in cyan on a tint, links underlined.
    static func inline(_ text: String) -> AttributedString {
        var value =
            (try? AttributedString(
                markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        for run in value.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.code) {
                value[run.range].font = .system(size: 11.5, design: .monospaced)
                value[run.range].foregroundColor = Ink.cyan
                value[run.range].backgroundColor = Ink.header
            }
            if intent.contains(.stronglyEmphasized) {
                value[run.range].foregroundColor = Ink.primary
            }
        }
        for run in value.runs where run.link != nil {
            value[run.range].foregroundColor = Ink.cyan
            value[run.range].underlineStyle = .single
        }
        return value
    }
}
