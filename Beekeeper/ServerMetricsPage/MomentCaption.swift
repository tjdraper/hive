#if os(iOS)
import SwiftUI

/// At iPhone width, when a list's figures are from, and the way back to live ones once a moment's chosen.
struct MomentCaption: View {
    let when: String
    let isChosen: Bool
    let onShowLive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(when)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                if isChosen {
                    Button("Show Live", action: onShowLive)
                        .font(.subheadline)
                }
            }
            if !isChosen {
                Text(MetricsMoment.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
