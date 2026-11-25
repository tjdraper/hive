#if os(iOS)
import SwiftUI

/// The containers and services page at iPhone width: one chart at a time above the list, and a group's
/// processes in a sheet, since a table at iPhone width shows only its first column.
struct CompactContainersPage<Unavailable: View>: View {
    @Binding var kind: ContainersPage.Kind
    @Binding var range: MetricsRange
    @Binding var grouping: ContainerGrouping
    @Binding var selection: CgroupRow.ID?
    let charts: [MetricsChart]
    let when: String
    let note: String
    /// Nil shows `unavailable` in the list's place.
    let rows: [CgroupRow]?
    let cgroups: CgroupHistory
    let processes: [ProcessRow]
    @ViewBuilder let unavailable: () -> Unavailable

    @Environment(MetricsMoment.self) private var moment
    @State private var order = MomentProcesses.Order.cpu
    @State private var shownChart: MetricsChart.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                segmented("Show", selection: $kind, ContainersPage.Kind.allCases) { $0.rawValue }
                MetricsRangePicker(range: $range)
            }
            .padding(.horizontal)
            MetricsChartPager(charts: charts, shown: $shownChart)
                .frame(height: 240)
            VStack(alignment: .leading, spacing: 8) {
                MomentCaption(when: when, isChosen: moment.chosen != nil) { moment.chosen = nil }
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if kind == .containers {
                        segmented("Grouping", selection: $grouping, ContainerGrouping.allCases) { $0.rawValue }
                    }
                    segmented("Order", selection: $order, MomentProcesses.Order.allCases) { $0.rawValue }
                }
            }
            .padding(.horizontal)
            if let rows {
                CgroupList(rows: rows, cgroups: cgroups, processes: processes, order: order, selection: $selection)
            } else {
                unavailable()
            }
        }
        .padding(.top)
    }

    private func segmented<Choice: Hashable & Identifiable>(
        _ title: String,
        selection: Binding<Choice>,
        _ choices: [Choice],
        name: @escaping (Choice) -> String
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(choices) { Text(name($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
#endif
