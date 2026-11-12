import SwiftUI

struct PermissionsSettingsView: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var reminders: RemindersService

    var body: some View {
        Form {
            Section("Calendar") {
                LabeledContent("Status") { Text(calendar.status.label) }
                PermissionPrompt(kind: .calendar, status: calendar.status) { await calendar.requestAccess() }
            }
            Section("Reminders") {
                LabeledContent("Status") { Text(reminders.status.label) }
                PermissionPrompt(kind: .reminders, status: reminders.status) { await reminders.requestAccess() }
            }
            Text("Denying either permission never blocks notes or tasks.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear {
            calendar.updateStatus()
            reminders.updateStatus()
        }
    }
}
