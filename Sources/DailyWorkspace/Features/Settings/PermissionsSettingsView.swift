import DailyCore
import SwiftUI

/// Access to macOS sources and the optional, read-only desktop integrations.
struct PermissionsSettingsView: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var reminders: RemindersService
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var openLoops: OpenLoopsStore

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
            SettingsGroup(
                "Mail.app",
                description: "Optional read-only access to flagged messages and unread messages in Important mailboxes."
            ) {
                SettingsRow(
                    "Enable Mail metadata",
                    description: "Mail Automation lets the app read message subjects, IDs and flagged/unread status. "
                        + "It never reads message bodies or gives Mail data to the Assistant."
                ) {
                    Toggle("Enable Mail metadata", isOn: $preferences.mailEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(
                    "Apple Mail Automation",
                    description: mailPermissionDescription
                ) {
                    StatusBadge(mailPermission.label, tone: mailPermission.tone)
                }
                SettingsRow(
                    "Mail source",
                    description: "A permitted read with no matching messages is different from blocked access.",
                    divider: false
                ) {
                    StatusBadge(mailSource.label, tone: mailSource.tone)
                }
                SettingsNote(
                    "macOS asks for Apple Mail Automation only after you enable Mail and a Mail read is requested. "
                        + "If access was denied, change it in System Settings → Privacy & Security → Automation."
                )
            }
            SettingsGroup("Quick Panel integrations", description: "Off until you turn each one on.") {
                SettingsRow(
                    "Clipboard change count",
                    description: "Use the clipboard change count for panel activity; do not read clipboard contents."
                ) {
                    Toggle("Enable clipboard change count", isOn: $preferences.quickPanelClipboardEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(
                    "Kitty window border",
                    description: "Allow the panel to change Kitty's window border; never read terminal content.",
                    divider: false
                ) {
                    Toggle("Enable Kitty window border", isOn: $preferences.quickPanelTerminalBorderEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
        .onAppear {
            calendar.updateStatus()
            reminders.updateStatus()
        }
    }

    private var mailPermission: (label: String, tone: Tone?) {
        guard preferences.mailEnabled, let observation = openLoops.observations[.mail] else {
            return ("Not checked", .neutral)
        }
        switch observation.state {
        case .empty, .populated, .partial: return ("Allowed", .success)
        case .unauthorized: return ("Not allowed", .attention)
        case .unsupported, .unavailable, .uninitialized, .refused: return ("Unknown", .neutral)
        }
    }

    private var mailPermissionDescription: String {
        guard preferences.mailEnabled else { return "Mail is off; no Automation permission is requested." }
        guard let observation = openLoops.observations[.mail] else {
            return "No Mail read has been requested yet; Automation access has not been checked."
        }
        switch observation.state {
        case .empty, .populated, .partial: return "macOS allowed this app to read Mail metadata."
        case .unauthorized: return "macOS has not allowed this app to read Mail."
        case .unsupported, .unavailable, .uninitialized, .refused:
            return "Mail could not be checked; its Automation permission is unknown."
        }
    }

    private var mailSource: (label: String, tone: Tone?) {
        guard preferences.mailEnabled else { return ("Off", .neutral) }
        guard let observation = openLoops.observations[.mail] else { return ("Not read", .neutral) }
        switch observation.state {
        case .empty: return ("No matching messages", .neutral)
        case .populated: return ("\(observation.value.count) messages", .neutral)
        case .partial: return ("Partial read", .attention)
        case .unauthorized: return ("Access not allowed", .attention)
        case .unsupported: return ("Unsupported", .neutral)
        case .unavailable: return ("Unavailable", .attention)
        case .uninitialized: return ("Not set up", .neutral)
        case .refused: return ("Not read", .neutral)
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
