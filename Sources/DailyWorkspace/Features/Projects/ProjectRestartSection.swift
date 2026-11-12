import SwiftUI

/// The project's latest reviewed restart record, ruled off inside the project detail card.
struct ProjectRestartSection: View {
    let slug: String

    var body: some View { RestartPanel(slug: slug, embedded: true) }
}
