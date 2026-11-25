import SwiftUI

/// The range's choice: in the toolbar's middle on the Mac and iPad, and at iPhone width in the page,
/// where the toolbar holds the page's title.
struct MetricsRangePicker: View {
    @Binding var range: MetricsRange

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        Picker("Range", selection: $range) {
            ForEach(MetricsRange.allCases) { range in
                Text(isCompact ? range.shortTitle : range.title)
                    .accessibilityLabel(range.title)
                    .tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }
}

private extension MetricsRange {
    /// Six full titles don't fit across an iPhone.
    var shortTitle: String {
        switch self {
        case .hour: "1H"
        case .sixHours: "6H"
        case .day: "1D"
        case .week: "1W"
        case .month: "1M"
        case .year: "1Y"
        }
    }
}

extension View {
    /// The range's picker in the toolbar's middle, except at iPhone width, where the page shows it.
    func metricsRangeToolbar(_ range: Binding<MetricsRange>) -> some View {
        modifier(MetricsRangeToolbar(range: range))
    }
}

private struct MetricsRangeToolbar: ViewModifier {
    @Binding var range: MetricsRange

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        if sizeClass == .compact {
            content
        } else {
            withPicker(content)
        }
        #else
        withPicker(content)
        #endif
    }

    private func withPicker(_ content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .principal) {
                MetricsRangePicker(range: $range)
            }
        }
    }
}
