import AppKit
import EventKit
import SwiftUI

/// Authorization state of an EventKit entity, shared by Calendar and Reminders.
enum PermissionStatus: Equatable {
    case notRequested, authorized, denied, restricted, unavailable

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notRequested
        case .fullAccess: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .writeOnly: self = .denied  // write-only access cannot read items
        @unknown default: self = .unavailable
        }
    }

    var label: String {
        switch self {
        case .notRequested: return "Not allowed yet"
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .unavailable: return "Unavailable"
        }
    }
}

/// Privacy panes in System Settings.
enum SystemSettingsPane {
    case calendars, reminders

    var url: URL? {
        switch self {
        case .calendars: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        case .reminders: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
        }
    }

    func open() {
        if let url { NSWorkspace.shared.open(url) }
    }
}

/// One permission flow for Calendar and Reminders: explain, request, or send the user to System Settings.
struct PermissionPrompt: View {
    enum Kind {
        case calendar, reminders

        var name: String { self == .calendar ? "Calendar" : "Reminders" }
        var pane: SystemSettingsPane { self == .calendar ? .calendars : .reminders }

        var purpose: String {
            switch self {
            case .calendar: return "See the day's events here, and add or edit events without leaving the app."
            case .reminders:
                return
                    "See incomplete Apple reminders, add to your default list, and mark items complete. Changes sync through your Apple account."
            }
        }
    }

    let kind: Kind
    let status: PermissionStatus
    let request: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(explanation).foregroundStyle(.secondary)
            switch status {
            case .notRequested:
                Button("Allow \(kind.name) Access…") { Task { await request() } }
            case .denied, .restricted:
                Button("Open System Settings") { kind.pane.open() }
            case .authorized, .unavailable:
                EmptyView()
            }
        }
    }

    private var explanation: String {
        switch status {
        case .notRequested, .authorized: return kind.purpose
        case .denied: return "\(kind.name) access is off. Notes and tasks still work."
        case .restricted: return "\(kind.name) access is restricted on this Mac. Notes and tasks still work."
        case .unavailable: return "\(kind.name) is unavailable right now."
        }
    }
}
