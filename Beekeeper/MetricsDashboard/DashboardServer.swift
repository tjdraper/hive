import Foundation
import HiveKit

/// A server as its card on the dashboard shows it: Hive's summary, with the newer of its own figures and
/// the live ones.
struct DashboardServer: Identifiable {
    let source: MetricsSource
    let summary: ServerMetricsSummary
    let latest: ServerMetricsLatest?
    let reporting: MetricsReporting
    /// Hive's open alerts about its figures. Those about whether it's reporting show as `reporting`.
    let figureAlerts: [MetricAlert]

    var id: UUID {
        summary.serverID
    }

    init(source: MetricsSource, summary: ServerMetricsSummary, live: ServerMetricsLatest?) {
        self.source = source
        self.summary = summary
        let liveIsNewer = live.map { $0.takenAt > summary.latest?.takenAt ?? .min } ?? false
        latest = liveIsNewer ? live : summary.latest
        // Hive counts a server stopped only for having sent nothing, so newer figures mean it's back.
        reporting = liveIsNewer && [.stopped, .waiting].contains(summary.reporting) ? .reporting : summary.reporting
        // In the order the card shows the figures.
        figureAlerts = summary.alerts.filter(\.isAboutFigures).sorted { $0.figureOrder < $1.figureOrder }
    }

    /// Hive found other servers stopped at the same time, which usually means its own connection.
    var stoppedWithOthers: Bool {
        reporting == .stopped && summary.alerts.contains { alert in
            if case .stoppedReporting(_, withOthers: true) = alert { true } else { false }
        }
    }

    /// Servers that stopped reporting or whose figures are refused first, then those with an alert about
    /// their figures, then the rest, each with the Hive Mac first and the servers by name.
    static func arranged(
        _ summaries: [ServerMetricsSummary],
        source: (UUID) -> MetricsSource?,
        live: [UUID: ServerMetricsLatest]
    ) -> [DashboardServer] {
        summaries
            .compactMap { summary in
                source(summary.serverID).map { DashboardServer(source: $0, summary: summary, live: live[summary.serverID]) }
            }
            .sorted { first, second in
                if first.rank != second.rank { return first.rank < second.rank }
                if first.source.isHiveMac != second.source.isHiveMac { return first.source.isHiveMac }
                return first.source.name.localizedStandardCompare(second.source.name) == .orderedAscending
            }
    }

    private var rank: Int {
        switch reporting {
        case .stopped, .clockAhead, .refused: 0
        case .reporting, .waiting: figureAlerts.isEmpty ? 2 : 1
        }
    }
}
