import SwiftUI

/// Three dots that signal work in progress (Luuna `StreamingDots`): decorative motion, never evidence. Each dot
/// steps its opacity in turn; under Reduce Motion they are still. Hidden from VoiceOver unless `label` is given.
struct StreamingDots: View {
    var label: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(label: String? = nil) {
        self.label = label
    }

    var body: some View {
        Group {
            if reduceMotion {
                dots(phase: nil)
            } else {
                TimelineView(.periodic(from: .now, by: 0.2)) { context in
                    dots(phase: Int(context.date.timeIntervalSinceReferenceDate / 0.2) % 3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(label == nil)
        .accessibilityLabel(Text(label ?? ""))
    }

    private func dots(phase: Int?) -> some View {
        HStack(spacing: Space.s1) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.info)
                    .frame(width: 5, height: 5)
                    .opacity(phase.map { $0 == index ? 1 : 0.35 } ?? 0.7)
            }
        }
    }
}
