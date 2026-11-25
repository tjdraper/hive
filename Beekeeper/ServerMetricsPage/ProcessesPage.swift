import HiveKit
import SwiftUI

/// A server's processes, grouped by command and user as Scout sends them (§4): live, or at a moment
/// chosen on the charts of how busy the server was and how many processes it ran.
struct ProcessesPage: View {
    let hive: KnownHive
    let link: HiveLink
    let serverID: UUID
    let path: MetricsPagePath

    private static let figures: [MetricsFigure] = [.cpuUser, .cpuSystem, .cpuIOWait, .cpuSteal, .processes, .zombies]

    @State private var range = MetricsRange.hour
    @State private var state: ServerMetricsState?
    @State private var history: ServerHistory?
    @State private var failure: String?
    @State private var processes: ProcessMoment?
    @State private var processesFailure: String?
    @State private var moment = MetricsMoment()
    @State private var sortOrder = [KeyPathComparator(\ProcessRow.cpuOrder, order: .reverse)]

    var body: some View {
        HiveConnectionGate(hive: hive, link: link) {
            content
                .task(id: range) {
                    while !Task.isCancelled {
                        await load()
                        try? await Task.sleep(for: range.refreshInterval)
                    }
                }
                .task(id: moment.chosen) {
                    // A chosen moment's processes don't change. The newest do, with every sample.
                    while !Task.isCancelled {
                        await loadProcesses()
                        guard moment.chosen == nil else { return }
                        try? await Task.sleep(for: .seconds(10))
                    }
                }
        }
        .environment(moment)
        .navigationTitle("Processes")
        .locationPath(path.parts("Processes", systemImage: "list.bullet.rectangle"))
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
        if let history {
            VStack(alignment: .leading, spacing: 12) {
                let timeline = MetricsTimeline(history: history)
                HStack(alignment: .top, spacing: 16) {
                    MetricsChart(title: "CPU", lines: history.cpu, format: .share, timeline: timeline, yDomain: 0 ... 1)
                    MetricsChart(title: "Processes", lines: history.processCount, format: .count, timeline: timeline)
                }
                caption
                list
            }
            .padding()
        } else if let failure {
            ContentUnavailableView {
                Label("Couldn't Read Metrics", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        } else {
            ProgressView()
        }
    }

    private var caption: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(when)
                    .font(.headline)
                Text("Grouped by command and user. Memory is each group's own, without what it shares, so it's approximate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if moment.chosen != nil {
                Button("Show Live") { moment.chosen = nil }
            } else {
                Text("Click a chart to see another moment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// When the list's figures are from, since the nearest kept may be a little off the moment chosen.
    private var when: String {
        let live = moment.chosen == nil ? "Live: " : ""
        return switch processes {
        case .sample(let takenAt, _):
            "\(live)\(ProcessRow.time(takenAt))"
        case .hour(let startsAt, _):
            "The busiest over the hour from \(ProcessRow.time(startsAt)), on average, with their highest"
        case .notKept, nil:
            moment.chosen == nil ? "Live" : "Processes"
        }
    }

    @ViewBuilder private var list: some View {
        switch processes {
        case .sample, .hour:
            Table(sortedRows, sortOrder: $sortOrder) {
                TableColumn("Command", value: \.command) { row in
                    Text(row.name)
                        .truncationMode(.middle)
                }
                TableColumn("User", value: \.user)
                TableColumn("CPU", value: \.cpuOrder) { row in
                    Text(row.cpuText)
                        .monospacedDigit()
                }
                TableColumn("Memory", value: \.memoryBytes) { row in
                    Text(row.memoryText)
                        .monospacedDigit()
                }
            }
        case .notKept:
            ContentUnavailableView(
                "No Processes Kept",
                systemImage: "list.bullet.rectangle",
                description: Text(
                    state?.scout?.processesHidden == true
                        ? "The server hides other users' processes from Scout."
                        : "Processes are kept for 14 days, and only while Scout reported."
                )
            )
        case nil:
            if let processesFailure {
                ContentUnavailableView(
                    "Couldn't Read Processes",
                    systemImage: "exclamationmark.triangle",
                    description: Text(processesFailure)
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Scout sends the busiest by CPU and by memory, so either order's top is complete.
    private var sortedRows: [ProcessRow] {
        (processes.map(ProcessRow.rows) ?? []).sorted(using: sortOrder)
    }

    /// Ranges are on the server's clock, which Hive knows the offset of.
    private var serverNow: Int64 {
        Int64(Date.now.timeIntervalSince1970.rounded(.down)) + Int64(state?.scout?.clockOffsetSeconds ?? 0)
    }

    private func load() async {
        do {
            let read = try await ServerHistory.read(Self.figures, over: range, ofServer: serverID, from: link)
            state = read.state
            history = read.history
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            if history == nil { failure = HiveLink.message(for: error) }
        }
    }

    private func loadProcesses() async {
        let second = moment.chosen.map(MetricsTimeline.second) ?? serverNow
        do {
            processes = try await link.perform {
                try await $0.get(HiveEndpoint.processes(ofServer: serverID, at: second), as: ProcessMoment.self)
            }
            processesFailure = nil
        } catch is CancellationError {
            return
        } catch {
            processes = nil
            processesFailure = HiveLink.message(for: error)
        }
    }
}
