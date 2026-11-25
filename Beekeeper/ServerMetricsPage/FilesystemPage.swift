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

    var body: some View {
        HiveConnectionGate(hive: hive, link: link) {
            content
                .task(id: range) {
                    while !Task.isCancelled {
                        await load()
                        try? await Task.sleep(for: range.refreshInterval)
                    }
                }
        }
        .environment(moment)
        .navigationTitle(mountPoint)
        .locationPath(path.parts(mountPoint, systemImage: "internaldrive"))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Range", selection: $range) {
                    ForEach(MetricsRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .onChange(of: range) { moment.chosen = nil }
    }

    @ViewBuilder private var content: some View {
        if let history, let filesystem = history.filesystems.first(where: { $0.name == mountPoint }) {
            page(history, filesystem: filesystem)
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
        let timeline = MetricsTimeline(history: history)
        let used = filesystem.newest(.filesystemUsed)
        let available = filesystem.newest(.filesystemAvailable)
        let usable = (used ?? 0) + (available ?? 0)
        let disk = history.disk(holding: filesystem)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 24) {
                    fact("Device", filesystem.device ?? "—")
                    fact("Type", filesystem.filesystemType ?? "—")
                    fact("Size", bytes(filesystem.newest(.filesystemSize)))
                    fact("Used", bytes(used))
                    fact("Available", bytes(available))
                    if let inodesFree = filesystem.newest(.filesystemInodesFree) {
                        fact("Inodes free", Int64(inodesFree.rounded()).formatted())
                    }
                }
                forecastLabel
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 16, alignment: .top)], spacing: 16) {
                    MetricsChart(
                        title: "Space used",
                        lines: history.space(of: filesystem),
                        format: .bytes,
                        timeline: timeline,
                        yDomain: 0 ... max(usable, 1)
                    )
                    let inodes = history.inodes(of: filesystem)
                    if !inodes.isEmpty {
                        MetricsChart(title: "Inodes used", lines: inodes, format: .share, timeline: timeline, yDomain: 0 ... 1)
                    }
                    if let disk {
                        MetricsChart(
                            title: "Disk \(disk.name ?? "") activity",
                            lines: history.activity(of: disk),
                            format: .bytesPerSecond,
                            timeline: timeline
                        )
                        MetricsChart(
                            title: "Disk \(disk.name ?? "") busy",
                            lines: history.busy(of: disk),
                            format: .share,
                            timeline: timeline,
                            yDomain: 0 ... 1
                        )
                    }
                }
            }
            .padding()
        }
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
