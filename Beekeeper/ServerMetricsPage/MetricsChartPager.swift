#if os(iOS)
import SwiftUI

/// At iPhone width, a page's charts one at a time, swiped between or chosen from the toolbar. They share
/// the page's range and moment, so both stay as they are when another chart shows.
struct MetricsChartPager: View {
    let charts: [MetricsChart]
    @Binding var shown: MetricsChart.ID?

    var body: some View {
        TabView(selection: selection) {
            ForEach(charts) { chart in
                chart.filling()
                    .padding(.horizontal)
                    // Room for the page dots beneath the chart.
                    .padding(.bottom, 40)
                    .tag(chart.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .toolbar {
            if charts.count > 2 {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Chart", selection: selection) {
                            ForEach(charts) { Text($0.title).tag($0.id) }
                        }
                    } label: {
                        Label("Charts", systemImage: "chart.bar.doc.horizontal")
                    }
                }
            }
        }
    }

    /// The first chart until another is chosen, and again if the one chosen goes, such as a disk removed.
    private var selection: Binding<MetricsChart.ID> {
        Binding {
            if let shown, charts.contains(where: { $0.id == shown }) { return shown }
            return charts.first?.id ?? ""
        } set: {
            shown = $0
        }
    }
}

extension MetricsChart {
    /// The same chart, taking the height it's given.
    func filling() -> MetricsChart {
        var chart = self
        chart.height = nil
        return chart
    }
}
#endif
