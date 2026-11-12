import AppKit
import SwiftUI

/// A generated identity or hash by its short form: the first 8 hex digits (or `sha256:` and 12), with "…"
/// only when shortened. The whole value is the tooltip and the accessible name, and one click copies it,
/// so nobody retypes an id. Nothing truncates it visually.
struct ShortId: View {
    let value: String
    var kind = "id"

    @State private var copied = false
    @State private var hovered = false

    init(_ value: String, kind: String = "id") {
        self.value = value
        self.kind = kind
    }

    var body: some View {
        let shown = Self.shortForm(value)
        Button(action: copy) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                Text(verbatim: shown == value ? shown : shown + "…")
                    .font(.system(size: TextRole.caption.size, design: .monospaced))
                    .foregroundStyle(hovered ? Theme.accentText : Theme.inkBody)
                    .padding(.horizontal, Space.s1Half)
                    .padding(.vertical, Space.sHalf)
                    .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Theme.fill))
                if copied {
                    Text("copied").textRole(.caption, lineBox: false).foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("\(value) · click to copy")
        .accessibilityLabel(Text("Copy \(kind) \(value)"))
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    /// The short form: the first 8 hex digits of a UUID inside the value (`ticket-…`, a bare UUID), `sha256:`
    /// plus 12 digits of a content hash, the first 8 of a longer hex string (a commit), else the value.
    static func shortForm(_ value: String) -> String {
        let uuid = #/(?:^|-)([0-9a-fA-F]{8})-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/#
        if let match = value.firstMatch(of: uuid) { return String(match.1).lowercased() }
        if value.hasPrefix("sha256:"), value.count > 19, value.dropFirst(7).allSatisfy(\.isHexDigit) {
            return String(value.prefix(19))
        }
        if value.count > 8, value.allSatisfy(\.isHexDigit) { return String(value.prefix(8)) }
        return value
    }
}
