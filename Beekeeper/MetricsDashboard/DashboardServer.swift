import Foundation
import HiveKit

/// A server as its card on the dashboard shows it: Hive's summary, with the newer of its own figures and
/// the live ones.
struct DashboardServer: Identifiable {
    let name: String
    let summary: ServerMetricsSummary
    let latest: ServerMetricsLatest?
    let reporting: MetricsReporting
    let concerns: Set<MetricsConcern>

    var id: UUID {
        summary.serverID
    }

    init(name: String, summary: ServerMetricsSummary, live: ServerMetricsLatest?) {
        self.name = name
        self.summary = summary
        let liveIsNewer = live.map { $0.takenAt > summary.latest?.takenAt ?? .min } ?? false
        latest = liveIsNewer ? live : summary.latest
        // Hive counts a server stopped only for having sent nothing, so newer figures mean it's back.
        reporting = liveIsNewer && [.stopped, .waiting].contains(summary.reporting) ? .reporting : summary.reporting
        concerns = reporting == .reporting ? MetricsConcern.concerns(in: latest, lastHour: summary.lastHour) : []
    }

    /// Servers that stopped reporting or whose figures are refused first, then those with a figure past
    /// its limit, each by name, then the rest by name.
    static func arranged(
        _ summaries: [ServerMetricsSummary],
        names: [UUID: String],
        live: [UUID: ServerMetricsLatest]
    ) -> [DashboardServer] {
        summaries
            .compactMap { summary in
                // A server removed since the summaries were read.
                names[summary.serverID].map { DashboardServer(name: $0, summary: summary, live: live[summary.serverID]) }
            }
            .sorted { first, second in
                if first.rank != second.rank { return first.rank < second.rank }
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            }
    }

    private var rank: Int {
        switch reporting {
        case .stopped, .clockAhead, .refused: 0
        case .reporting, .waiting: concerns.isEmpty ? 2 : 1
        }
    }
}
