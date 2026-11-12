import SwiftUI

/// Open Loops: one list across the owners (local tasks, Org, Seeds, Reminders), each row with its source and
/// the owner's own status. A placeholder until the source adapters land (SYSTEM-INVENTORY §3, Increment 1);
/// Tasks and Reminders keep their views in `Features/Tasks` and `Features/Reminders` until then.
struct OpenLoopsView: View {
    var body: some View {
        Page {
            PageHeader(title: AppSection.openLoops.title, description: AppSection.openLoops.description)
            EmptyState(
                "Open Loops is not built yet",
                description:
                    "It will bring local tasks, Org, Seeds and Reminders into one list. Each item stays with its owner.",
                systemImage: AppSection.openLoops.symbol,
                boxed: true
            )
        }
        .navigationTitle(AppSection.openLoops.title)
    }
}
