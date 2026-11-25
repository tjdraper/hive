import HiveKit
import SwiftUI

/// One of a server's filesystems: its space and inodes over the range, the activity of the disk it's
/// on, and when it fills at the rate it filled over the last week.
struct FilesystemPage: View {
    let hive: KnownHive
    let link: HiveLink
    let serverID: UUID
    let mountPoint: String
    let path: MetricsPagePath

    private static let figures: [MetricsFigure] = [
        .filesystemSize, .filesystemUsed, .filesystemAvailable, .filesystemInodesUsed, .filesystemInodesFree,
        .diskReadBytes, .diskWrittenBytes, .diskBusy,
    ]

    @State private var range = MetricsRange.day
    @State private var history: ServerHistory?
    @State private var forecast: FilesystemForecast?
    @State private var failure: String?
    @State private var moment = MetricsMoment()
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var shownChart: MetricsChart.ID?
    #endif

    var body: some View {
        HiveConnectionGate(hive: hive, link: link) {
            content
                .reloading(every: range.refreshInterval, id: range) { await load() }
        }
        .environment(moment)
        .navigationTitle(mountPoint)
        .locationPath(path.parts(mountPoint, systemImage: "internaldrive"))
        .metricsRangeToolbar($range)
        .onChange(of: range) { moment.chosen = nil }
    }

    @ViewBuilder private var content: some View {
        if let history, let filesystem = history.filesystems.first(where: { $0.name == mountPoint }) {
            #if os(iOS)
            if sizeClass == .compact {
                compactPage(history, filesystem: filesystem)
            } else {
                page(history, filesystem: filesystem)
            }
            #else
            page(history, filesystem: filesystem)
            #endif
        } else if let failure {
            ContentUnavailableView {
                Label("Couldn't Read Metrics", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        } else if history != nil {
            ContentUnavailableView(
                "Nothing Kept",
                systemImage: "internaldrive",
                description: Text("Scout didn't report \(mountPoint) in this range.")
            )
        } else {
            ProgressView()
        }
    }

    private func page(_ history: ServerHistory, filesystem: SubjectFigures) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                facts(filesystem)
                forecastLabel
                LazyVGrid(columns: MetricsChart.columns, spacing: 16) {
                    ForEach(charts(history, filesystem: filesystem)) { $0 }
                }
            }
            .padding()
        }
    }

    #if os(iOS)
    private func compactPage(_ history: ServerHistory, filesystem: SubjectFigures) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MetricsRangePicker(range: $range)
                    .padding(.horizontal)
                MetricsChartPager(charts: charts(history, filesystem: filesystem), shown: $shownChart)
                    .frame(height: 320)
                VStack(alignment: .leading, spacing: 16) {
                    forecastLabel
                    facts(filesystem)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
    #endif

    /// In a row where they fit, and otherwise in two columns.
    private func facts(_ filesystem: SubjectFigures) -> some View {
        let facts = [
            ("Device", filesystem.device ?? "—"),
            ("Type", filesystem.filesystemType ?? "—"),
            ("Size", bytes(filesystem.newest(.filesystemSize))),
            ("Used", bytes(filesystem.newest(.filesystemUsed))),
            ("Available", bytes(filesystem.newest(.filesystemAvailable))),
        ] + (filesystem.newest(.filesystemInodesFree).map { [("Inodes free", Int64($0.rounded()).formatted())] } ?? [])
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                ForEach(facts, id: \.0) { fact($0.0, $0.1) }
            }
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                ForEach(Array(stride(from: 0, to: facts.count, by: 2)), id: \.self) { index in
                    GridRow {
                        ForEach(facts[index ..< min(index + 2, facts.count)], id: \.0) { fact($0.0, $0.1) }
                    }
                }
            }
        }
    }

    private func charts(_ history: ServerHistory, filesystem: SubjectFigures) -> [MetricsChart] {
        let timeline = MetricsTimeline(history: history)
        let usable = (filesystem.newest(.filesystemUsed) ?? 0) + (filesystem.newest(.filesystemAvailable) ?? 0)
        var charts = [
            MetricsChart(
                title: "Space used",
                lines: history.space(of: filesystem),
                format: .bytes,
                timeline: timeline,
                yDomain: 0 ... max(usable, 1)
            ),
        ]
        let inodes = history.inodes(of: filesystem)
        if !inodes.isEmpty {
            charts.append(MetricsChart(title: "Inodes used", lines: inodes, format: .share, timeline: timeline, yDomain: 0 ... 1))
        }
        if let disk = history.disk(holding: filesystem) {
            charts.append(MetricsChart(
                title: "Disk \(disk.name ?? "") activity",
                lines: history.activity(of: disk),
                format: .bytesPerSecond,
                timeline: timeline
            ))
            charts.append(MetricsChart(
                title: "Disk \(disk.name ?? "") busy",
                lines: history.busy(of: disk),
                format: .share,
                timeline: timeline,
                yDomain: 0 ... 1
            ))
        }
        return charts
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var forecastLabel: some View {
        if let forecast {
            if let fillsAt = forecast.fillsAt, let growth = forecast.growthBytesPerDay {
                let date = MetricsTimeline.date(fillsAt)
                Label(
                    "Fills \(date.formatted(.relative(presentation: .named))), "
                        + "around \(date.formatted(date: .abbreviated, time: .shortened)), "
                        + "at the \(bytes(growth)) a day it grew over the last week.",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                .foregroundStyle(fillsAt - Int64(Date.now.timeIntervalSince1970) < 7 * 86_400 ? .orange : .primary)
            } else if let growth = forecast.growthBytesPerDay {
                Label(
                    growth > 0
                        ? "Growing \(bytes(growth)) a day over the last week, so not full within a year."
                        : "Not filling: steady or shrinking over the last week.",
                    systemImage: "chart.line.flattrend.xyaxis"
                )
                .foregroundStyle(.secondary)
            } else {
                Label("No forecast until there are 6 hours of figures.", systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bytes(_ value: Double?) -> String {
        value.map { Int64($0.rounded()).formatted(.byteCount(style: .memory)) } ?? "—"
    }

    private func load() async {
        do {
            let read = try await ServerHistory.read(Self.figures, over: range, ofServer: serverID, from: link)
            let forecasts = try await link.perform {
                try await $0.get(HiveEndpoint.filesystemForecasts(ofServer: serverID), as: [FilesystemForecast].self)
            }
            history = read.history
            forecast = forecasts.first { $0.mountPoint == mountPoint }
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            if history == nil { failure = HiveLink.message(for: error) }
        }
    }
}
