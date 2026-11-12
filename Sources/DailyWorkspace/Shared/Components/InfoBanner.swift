import SwiftUI

/// A one-line status message above a screen's content.
struct InfoBanner: View {
    let text: String

    var body: some View {
        HStack {
            Image(systemName: "info.circle")
            Text(text)
            Spacer()
        }
        .font(.callout)
        .padding(10)
        .background(.quaternary)
        .accessibilityElement(children: .combine)
    }
}
