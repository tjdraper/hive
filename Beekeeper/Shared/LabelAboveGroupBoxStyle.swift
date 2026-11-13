import SwiftUI

/// The Mac's group box on iPad and iPhone: the label above a softly filled box. iOS's own puts the label
/// inside the box with wide padding, which reads as a card rather than a group.
struct LabelAboveGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            configuration.label
                .font(.subheadline)
                .padding(.leading, 4)
            configuration.content
                .padding(10)
                .background(.fill.quaternary, in: .rect(cornerRadius: 10))
        }
    }
}
