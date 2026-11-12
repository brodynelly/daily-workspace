import SwiftUI

/// Projects: the hubs in `01-projects`, each with its purpose, decisions and latest restart record.
/// A placeholder until the project reader lands (SYSTEM-INVENTORY §3, Increment 1).
struct ProjectsView: View {
    var body: some View {
        Page {
            PageHeader(title: AppSection.projects.title, description: AppSection.projects.description)
            EmptyState(
                "Projects is not built yet",
                description:
                    "It will list the project hubs in 01-projects, read-only, with each project's latest restart record.",
                systemImage: AppSection.projects.symbol,
                boxed: true
            )
        }
        .navigationTitle(AppSection.projects.title)
    }
}
