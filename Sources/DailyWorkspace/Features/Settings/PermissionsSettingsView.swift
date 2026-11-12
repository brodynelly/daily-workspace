import SwiftUI

/// Calendar and Reminders access: each as a settings row with its purpose, the state as a toned badge
/// (allowed is the only green), and the one control that can change it.
struct PermissionsSettingsView: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var reminders: RemindersService

    var body: some View {
        SettingsPage {
            SettingsGroup("Access", description: "What macOS lets the app read. Change it here or in System Settings.")
            {
                PermissionRow(kind: .calendar, status: calendar.status) { await calendar.requestAccess() }
                PermissionRow(kind: .reminders, status: reminders.status, divider: false) {
                    await reminders.requestAccess()
                }
                SettingsNote("Denying either permission never blocks notes or tasks.")
            }
        }
        .onAppear {
            calendar.updateStatus()
            reminders.updateStatus()
        }
    }
}

private struct PermissionRow: View {
    let kind: PermissionPrompt.Kind
    let status: PermissionStatus
    var divider = true
    let request: () async -> Void

    var body: some View {
        SettingsRow(kind.name, description: description, divider: divider) {
            switch status {
            case .notRequested:
                Button("Allow \(kind.name) Access…") { Task { await request() } }
                    .buttonStyle(.secondary)
            case .denied, .restricted:
                Button("Open System Settings") { kind.pane.open() }
                    .buttonStyle(.secondary)
            case .authorized, .unavailable:
                EmptyView()
            }
            StatusBadge(status.label, tone: status.tone)
        }
    }

    private var description: String {
        switch status {
        case .notRequested, .authorized: return kind.purpose
        case .denied: return "\(kind.name) access is off. Notes and tasks still work."
        case .restricted: return "\(kind.name) access is restricted on this Mac. Notes and tasks still work."
        case .unavailable: return "\(kind.name) is unavailable right now."
        }
    }
}
