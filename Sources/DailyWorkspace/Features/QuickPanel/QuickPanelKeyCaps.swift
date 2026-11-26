import AppKit
import SwiftUI

extension QuickPanelController {
    /// Sends the shared draft only on an explicit Return. No page focus is attached from the panel.
    func sendAssistantDraft() {
        guard let model else { return }
        model.assistant.send(model.navigation.assistantDraft)
        // Keep the draft when nothing was sent (Assistant off, no key, empty question).
        if model.assistant.isStreaming { model.navigation.assistantDraft = "" }
    }
}

/// Key strokes drawn as separate caps (`^B D` → ⌃B · D) with an optional label.
@MainActor
struct QuickPanelKeyCaps: View {
    let keys: String
    var label: String = ""
    private typealias Ink = QuickPanelPascalSkin.Ink

    static func strokes(_ keys: String) -> [String] {
        let trimmed = keys.trimmingCharacters(in: .whitespaces)
        // "j/k"-style alternatives and single glyphs stay together; spaces separate strokes.
        return trimmed.split(separator: " ").map { stroke in
            stroke.hasPrefix("^") && stroke.count > 1 ? "⌃" + stroke.dropFirst() : String(stroke)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(Array(Self.strokes(keys).enumerated()), id: \.offset) { _, stroke in
                    Text(stroke)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.gold)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 17)
                        .background(Ink.header.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Ink.idleRule.opacity(0.55), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            if !label.isEmpty {
                Text(label.trimmingCharacters(in: .whitespaces)).foregroundStyle(Ink.footer)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? keys : "\(keys) \(label)")
    }
}
