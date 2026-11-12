import SwiftUI

/// Six outcome tones, each carried by three channels: a colour family, a shape mark and the source's own
/// unchanged text. Colour is never the only signal, and no tone has two meanings.
/// - success: passed, durable evidence and a live connection. Green is earned: a finished or completed
///   item is not evidence and is never green.
/// - active: the source is working (info blue; told apart from the accent by its ring).
/// - danger: failed or blocked.
/// - attention: waiting on Brody.
/// - neutral: recorded, not evidence.
/// - interrupted: stopped by an outage or restart, recoverable. Never danger.
enum Tone: String, CaseIterable, Identifiable, Sendable {
    case success, active, danger, attention, neutral, interrupted

    var id: String { rawValue }

    /// The shape each tone draws, so a state survives without colour.
    enum Mark: CaseIterable, Sendable {
        case filledCircle, ring, diamond, triangle, bar, pauseBars
    }

    var mark: Mark {
        switch self {
        case .success: return .filledCircle
        case .active: return .ring
        case .danger: return .diamond
        case .attention: return .triangle
        case .neutral: return .bar
        case .interrupted: return .pauseBars
        }
    }

    /// Text in this tone (on its soft ground or the surface).
    var foreground: Color {
        switch self {
        case .success: return Theme.success
        case .active: return Theme.info
        case .danger: return Theme.danger
        case .attention: return Theme.warning
        case .neutral, .interrupted: return Theme.inkBody
        }
    }

    /// The tone's soft ground (badges, callouts).
    var background: Color {
        switch self {
        case .success: return Theme.successSoft
        case .active: return Theme.infoSoft
        case .danger: return Theme.dangerSoft
        case .attention: return Theme.warningSoft
        case .neutral, .interrupted: return Theme.fillStrong
        }
    }

    /// The mark's colour.
    var markColor: Color {
        switch self {
        case .success: return Theme.success
        case .active: return Theme.info
        case .danger: return Theme.danger
        case .attention: return Theme.warning
        case .neutral, .interrupted: return Theme.inkMuted
        }
    }

    /// The hex behind `foreground`, `background` and `markColor`, for contrast checks.
    var foregroundToken: ColorToken {
        switch self {
        case .success: return .success
        case .active: return .info
        case .danger: return .danger
        case .attention: return .warning
        case .neutral, .interrupted: return .inkBody
        }
    }

    var backgroundToken: ColorToken {
        switch self {
        case .success: return .successSoft
        case .active: return .infoSoft
        case .danger: return .dangerSoft
        case .attention: return .warningSoft
        case .neutral, .interrupted: return .fillStrong
        }
    }

    var markToken: ColorToken {
        switch self {
        case .success: return .success
        case .active: return .info
        case .danger: return .danger
        case .attention: return .warning
        case .neutral, .interrupted: return .inkMuted
        }
    }
}

/// A tone's shape on its own: an 8 pt mark for a status outside a badge (the vault status line).
/// Decorative; the word beside it carries the meaning for VoiceOver.
struct ToneMark: View {
    let tone: Tone
    var size: CGFloat = Metrics.markSize

    var body: some View {
        shape
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var shape: some View {
        let color = tone.markColor
        let stroke = Metrics.markStroke
        switch tone.mark {
        case .filledCircle:
            Circle().fill(color)
        case .ring:
            Circle().strokeBorder(color, lineWidth: stroke)
        case .diamond:
            Rectangle().fill(color).rotationEffect(.degrees(45)).scaleEffect(0.85)
        case .triangle:
            Triangle().fill(color)
        case .bar:
            Capsule().fill(color).frame(height: stroke)
        case .pauseBars:
            HStack(spacing: 0) {
                Rectangle().fill(color).frame(width: stroke)
                Spacer(minLength: 0)
                Rectangle().fill(color).frame(width: stroke)
            }
        }
    }
}

/// An upward triangle filling its frame: (50% 0, 100% 100%, 0 100%).
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
