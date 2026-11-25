#if os(iOS)
import HiveKit
import SwiftUI

/// One server on the dashboard at iPhone width: its card's figures in a row, without the sparkline,
/// which its page has room for.
struct ServerMetricsRow: View {
    let server: DashboardServer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                MetricsSourceLabel(source: server.source)
                    .font(.headline)
                Spacer(minLength: 0)
                ReportingBadge(reporting: server.reporting)
            }
            if let problem = ServerMetricsCard.problem(of: server) {
                Text(problem)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FigureAlertsLine(alerts: server.figureAlerts)
                .font(.subheadline)
            if let latest = server.latest, server.reporting != .waiting {
                figures(latest)
                    // Figures from before it stopped are still worth seeing, but aren't current.
                    .opacity(server.reporting == .reporting ? 1 : 0.6)
            }
        }
        .padding(.vertical, 4)
    }

    private func figures(_ latest: ServerMetricsLatest) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RowFigure(
                title: "CPU",
                value: latest.cpu.map { ServerMetricsCard.percent($0.busy) },
                hasAlert: server.figureAlerts.contains(.cpuBusy)
            )
            RowFigure(
                title: "Memory",
                value: latest.memory.map { ServerMetricsCard.percent($0.usedShare) },
                hasAlert: server.figureAlerts.contains(.memoryShort)
            )
            RowFigure(
                title: "Swap",
                value: latest.memory.map { $0.swapTotalBytes == 0 ? "None" : ServerMetricsCard.percent($0.swapUsedShare) },
                hasAlert: false
            )
            RowFigure(
                title: "Fullest disk",
                value: latest.fullestFilesystem.map { ServerMetricsCard.percent($0.usedShare) },
                hasAlert: server.isFillingFullest
            )
        }
    }
}

private struct RowFigure: View {
    let title: String
    let value: String?
    let hasAlert: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 3) {
                Text(value ?? "—")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                if hasAlert {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Alert")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
#endif
