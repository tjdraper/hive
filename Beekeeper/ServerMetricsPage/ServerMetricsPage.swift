import HiveKit
import SwiftUI

/// One server's metrics: what it is, and its figures over a range on charts sharing one time axis and
/// one chosen moment, whose processes show beside them. Read again while open, since every range ends now.
struct ServerMetricsPage: View {
    let hive: KnownHive
    let link: HiveLink
    let servers: ServerList
    let serverID: UUID
    let onShowHive: () -> Void
    let onShowDashboard: () -> Void

    @State private var range = MetricsRange.hour
    @State private var state: ServerMetricsState?
    @State private var history: ServerHistory?
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
        .navigationTitle(name)
        .locationPath([
            LocationPath.Part(title: hive.name, systemImage: "hexagon", action: onShowHive),
            LocationPath.Part(title: "Metrics", systemImage: "chart.xyaxis.line", action: onShowDashboard),
            LocationPath.Part(title: name, systemImage: "server.rack"),
        ])
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
        .inspector(isPresented: isShowingProcesses) {
            processes
                .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
        }
    }

    private var name: String {
        servers.server(serverID)?.name ?? "Server"
    }

    @ViewBuilder private var content: some View {
        if let history, let scout = state?.scout {
            page(history, scout: scout)
        } else if let failure {
            ContentUnavailableView {
                Label("Couldn't Read Metrics", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        } else if let state, state.scout == nil {
            ContentUnavailableView(
                "No Scout Enrolled",
                systemImage: "chart.xyaxis.line",
                description: Text("Add metrics to this server from its page.")
            )
        } else {
            ProgressView()
        }
    }

    private func page(_ history: ServerHistory, scout: ScoutState) -> some View {
        let timeline = MetricsTimeline(history: history)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ServerFacts(scout: scout, history: history, serverNow: serverNow)
                Text(moment.chosen == nil ? "Click a chart to see the processes at that moment." : " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 16, alignment: .top)], spacing: 16) {
                    charts(history, timeline: timeline)
                }
            }
            .padding()
        }
    }

    @ViewBuilder private func charts(_ history: ServerHistory, timeline: MetricsTimeline) -> some View {
        MetricsChart(title: "CPU", lines: history.cpu, format: .share, timeline: timeline, yDomain: 0 ... 1)
        MetricsChart(title: "Load", lines: history.load, format: .load, timeline: timeline)
        MetricsChart(
            title: "Memory",
            lines: history.memory,
            format: .bytes,
            timeline: timeline,
            yDomain: history.memoryTotal.map { 0 ... max($0, 1) }
        )
        if let swapTotal = history.swapTotal {
            MetricsChart(title: "Swap", lines: history.swap, format: .bytes, timeline: timeline, yDomain: 0 ... swapTotal)
            MetricsChart(title: "Swapping, pages", lines: history.swapping, format: .perSecond, timeline: timeline)
        }
        if !history.pressure.isEmpty {
            MetricsChart(title: "Pressure, time stalled", lines: history.pressure, format: .share, timeline: timeline)
        }
        if !history.filesystems.isEmpty {
            MetricsChart(title: "Disk space used", lines: history.diskSpace, format: .share, timeline: timeline, yDomain: 0 ... 1)
        }
        ForEach(history.disks) { disk in
            MetricsChart(title: "Disk \(disk.name ?? "")", lines: history.activity(of: disk), format: .bytesPerSecond, timeline: timeline)
        }
        ForEach(history.interfaces) { interface in
            MetricsChart(
                title: "Network \(interface.name ?? "")",
                lines: history.traffic(of: interface),
                format: .bytesPerSecond,
                timeline: timeline
            )
        }
    }

    @ViewBuilder private var processes: some View {
        if let chosen = moment.chosen {
            MomentProcesses(
                link: link,
                serverID: serverID,
                moment: chosen,
                processesHidden: state?.scout?.processesHidden == true
            ) { moment.chosen = nil }
        }
    }

    private var isShowingProcesses: Binding<Bool> {
        Binding { moment.chosen != nil } set: { if !$0 { moment.chosen = nil } }
    }

    /// Ranges are on the server's clock, which Hive knows the offset of.
    private var serverNow: Int64 {
        Int64(Date.now.timeIntervalSince1970.rounded(.down)) + Int64(state?.scout?.clockOffsetSeconds ?? 0)
    }

    private func load() async {
        do {
            let state = try await link.perform {
                try await $0.get(HiveEndpoint.metrics(ofServer: serverID), as: ServerMetricsState.self)
            }
            let end = Int64(Date.now.timeIntervalSince1970.rounded(.down)) + Int64(state.scout?.clockOffsetSeconds ?? 0)
            let span = end - range.seconds ..< end
            let seriesPath = HiveEndpoint.metricsSeries(
                ofServer: serverID,
                from: span.lowerBound,
                to: span.upperBound,
                figures: ServerHistory.figures
            )
            let series = try await link.perform { try await $0.get(seriesPath, as: MetricsSeries.self) }
            let runs = try await link.perform {
                try await $0.get(
                    HiveEndpoint.backupRunMarks(ofServer: serverID, from: span.lowerBound, to: span.upperBound),
                    as: [BackupRunMark].self
                )
            }
            self.state = state
            history = ServerHistory(series: series, range: span, backupRuns: runs)
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            // The charts already showing stay, rather than giving way to a passing failure.
            if history == nil { failure = HiveLink.message(for: error) }
        }
    }
}
