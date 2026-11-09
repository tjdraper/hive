import SwiftUI

/// A form row with its label above what it labels, as Locus Calendar and Locus ToDo have them. Beside
/// it, the Mac's grouped form pushes a field into a narrow space at the right, with its text against
/// the label's far edge.
struct StackedRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.72))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

extension View {
    /// A text field as a stacked row shows it: plain and from the leading edge, named by the row's title.
    func stackedField(_ title: String) -> some View {
        labelsHidden()
            .textFieldStyle(.plain)
            .multilineTextAlignment(.leading)
            .accessibilityLabel(Text(title))
    }
}
