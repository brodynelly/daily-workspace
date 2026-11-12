import SwiftUI

/// The project's latest reviewed restart record. A placeholder: the Assistant's restart panel replaces this view.
struct ProjectRestartSection: View {
    let slug: String

    var body: some View {
        Panel("Resume", variant: .subpanel) {
            EmptyState(
                "No restart record yet",
                description: "A reviewed restart record for \(slug) will appear here, with its sources and next action."
            )
        }
    }
}
