import HiveKit
import SwiftUI

/// One server on the dashboard: whether it's reporting, its CPU, memory, swap and fullest disk, and its
/// last hour.
struct ServerMetricsCard: View {
    let server: DashboardServer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(server.name, systemImage: "server.rack")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                ReportingBadge(reporting: server.reporting)
            }
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let latest = server.latest, server.reporting != .waiting {
                figures(latest)
                    // Figures from before it stopped are still worth seeing, but aren't current.
                    .opacity(server.reporting == .reporting ? 1 : 0.6)
                MetricsSparkline(points: server.summary.lastHour, end: sparklineEnd(latest))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quinary, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(border, lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 12))
    }

    private var problem: LocalizedStringKey? {
        switch server.reporting {
        case .reporting:
            nil
        case .waiting:
            "Waiting for its Scout's first report."
        case .stopped:
            if let last = server.summary.lastReportAt {
                "Last report \(last.formatted(.relative(presentation: .named)))."
            } else {
                "No report for over 3 minutes."
            }
        case .clockAhead:
            "Its clock is ahead of the Hive's, so the Hive refuses its figures."
        case .refused:
            "The Hive refuses its figures. Its page says why."
        }
    }

    private var border: AnyShapeStyle {
        switch server.reporting {
        case .stopped, .refused: AnyShapeStyle(.red.opacity(0.7))
        case .clockAhead: AnyShapeStyle(.orange.opacity(0.8))
        case .reporting where !server.concerns.isEmpty: AnyShapeStyle(.orange.opacity(0.8))
        case .reporting, .waiting: AnyShapeStyle(.separator)
        }
    }

    private func figures(_ latest: ServerMetricsLatest) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                FigureCell(
                    title: "CPU",
                    value: latest.cpu.map { Self.percent($0.busy) },
                    detail: cpuDetail(latest),
                    isConcern: !server.concerns.isDisjoint(with: [.cpu, .load])
                )
                FigureCell(
                    title: "Memory",
                    value: latest.memory.map { Self.percent($0.usedShare) },
                    detail: latest.memory.map { "\(Self.bytes($0.usedBytes)) of \(Self.bytes($0.totalBytes))" },
                    isConcern: server.concerns.contains(.memory)
                )
            }
            GridRow {
                FigureCell(
                    title: "Swap",
                    value: latest.memory.map { $0.swapTotalBytes == 0 ? "None" : Self.percent($0.swapUsedShare) },
                    detail: latest.memory.flatMap { memory in
                        memory.swapTotalBytes == 0
                            ? nil
                            : "\(Self.bytes(memory.swapUsedBytes)) of \(Self.bytes(memory.swapTotalBytes))"
                    },
                    isConcern: false
                )
                FigureCell(
                    title: "Fullest disk",
                    value: latest.fullestFilesystem.map { Self.percent($0.usedShare) },
                    detail: latest.fullestFilesystem.map { "\($0.mountPoint), \(Self.bytes($0.availableBytes)) free" },
                    isConcern: server.concerns.contains(.disk)
                )
            }
        }
    }

    private func cpuDetail(_ latest: ServerMetricsLatest) -> String? {
        guard let load = latest.load else { return nil }
        let figure = load.oneMinute.formatted(.number.precision(.fractionLength(2)))
        guard let cores = latest.cores else { return "Load \(figure)" }
        return "Load \(figure) on \(cores) \(cores == 1 ? "core" : "cores")"
    }

    /// The sparkline's hour ends now, or at the server's newest figures when its clock is ahead.
    private func sparklineEnd(_ latest: ServerMetricsLatest) -> Date {
        max(.now, Date(timeIntervalSince1970: TimeInterval(latest.takenAt)))
    }

    private static func percent(_ share: Double) -> String {
        share.formatted(.percent.precision(.fractionLength(0)))
    }

    private static func bytes(_ count: UInt64) -> String {
        Int64(clamping: count).formatted(.byteCount(style: .memory))
    }
}

/// A figure's name, its value large, and what it's of.
private struct FigureCell: View {
    let title: String
    let value: String?
    let detail: String?
    let isConcern: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(value ?? "—")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                if isConcern {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Past its alert limit")
                        .accessibilityLabel("Past its alert limit")
                }
            }
            Text(detail ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// An icon and a word for whether the server is reporting, so it never rests on color alone.
private struct ReportingBadge: View {
    let reporting: MetricsReporting

    var body: some View {
        Label {
            Text(word)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }

    private var word: String {
        switch reporting {
        case .reporting: "Reporting"
        case .waiting: "Waiting"
        case .stopped: "Stopped"
        case .clockAhead: "Clock ahead"
        case .refused: "Refused"
        }
    }

    private var symbol: String {
        switch reporting {
        case .reporting: "checkmark.circle.fill"
        case .waiting: "hourglass"
        case .stopped: "exclamationmark.octagon.fill"
        case .clockAhead: "clock.badge.exclamationmark"
        case .refused: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch reporting {
        case .reporting: .green
        case .waiting: .secondary
        case .stopped, .refused: .red
        case .clockAhead: .orange
        }
    }
}

private extension CPUShares {
    var busy: Double {
        user + system + ioWait + steal
    }
}

private extension MemoryUse {
    var usedBytes: UInt64 {
        totalBytes > availableBytes ? totalBytes - availableBytes : 0
    }

    var usedShare: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }

    var swapUsedShare: Double {
        swapTotalBytes > 0 ? Double(swapUsedBytes) / Double(swapTotalBytes) : 0
    }
}
