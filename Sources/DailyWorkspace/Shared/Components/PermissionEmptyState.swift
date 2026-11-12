import SwiftUI

extension PermissionStatus {
    /// The tone of an access state. Green is earned: only access macOS has granted is success.
    var tone: Tone {
        switch self {
        case .authorized: return .success
        case .denied: return .danger
        case .notRequested: return .attention
        case .restricted, .unavailable: return .neutral
        }
    }
}

/// Luuna's connect page as an empty state, for a source macOS has not opened to the app: what is missing as a
/// plain fact, why it matters, and the one control that fixes it (ask, or open System Settings) as the
/// primary. Nothing is offered when no control can help.
struct PermissionEmptyState: View {
    let kind: PermissionPrompt.Kind
    let status: PermissionStatus
    let request: () async -> Void

    var body: some View {
        EmptyState(title, description: description, systemImage: symbol, boxed: true) {
            switch status {
            case .notRequested:
                Button("Allow \(kind.name) Access…") { Task { await request() } }
                    .buttonStyle(.primary)
            case .denied, .restricted:
                Button("Open System Settings") { kind.pane.open() }
                    .buttonStyle(.primary)
            case .authorized, .unavailable:
                EmptyView()
            }
        }
    }

    private var symbol: String { kind == .calendar ? "calendar" : "checklist" }

    private var title: String {
        switch status {
        case .notRequested: return "\(kind.name) is not connected yet"
        case .authorized: return "\(kind.name) is connected"
        case .denied: return "\(kind.name) access is off"
        case .restricted: return "\(kind.name) access is restricted on this Mac"
        case .unavailable: return "\(kind.name) is unavailable right now"
        }
    }

    private var description: String {
        switch status {
        case .notRequested, .authorized: return kind.purpose
        case .denied:
            return "Turn it on in System Settings › Privacy & Security › \(kind.name). Notes and tasks still work."
        case .restricted, .unavailable: return "Notes and tasks still work."
        }
    }
}
