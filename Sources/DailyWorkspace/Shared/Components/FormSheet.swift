import SwiftUI

/// The frame of every sheet: the section-title heading (with an optional one-line description and trailing
/// accessory), then the content, 24 pt padding on the overlay surface at one of three fixed widths. Sheets
/// end with a `FormFooter`: Cancel, then the one primary action on the right.
struct FormSheet<Accessory: View, Content: View>: View {
    /// Sheet widths: a short form (480), a review with editable fields (640), a side-by-side comparison (720).
    enum Width {
        case form, review, comparison

        var points: CGFloat {
            switch self {
            case .form: return Metrics.sheetFormWidth
            case .review: return Metrics.sheetReviewWidth
            case .comparison: return Metrics.sheetComparisonWidth
            }
        }
    }

    let title: String
    var description: String?
    var width: Width
    var spacing: CGFloat
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(
        _ title: String, description: String? = nil, width: Width = .form, spacing: CGFloat = Space.s4,
        @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.width = width
        self.spacing = spacing
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            SectionHeading(title, description: description) { accessory }
            content
        }
        .padding(Space.s6)
        .frame(width: width.points, alignment: .leading)
        .background(Theme.surfaceOverlay)
    }
}

extension FormSheet where Accessory == EmptyView {
    init(
        _ title: String, description: String? = nil, width: Width = .form, spacing: CGFloat = Space.s4,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title, description: description, width: width, spacing: spacing, accessory: { EmptyView() },
            content: content)
    }
}
