import HiveKit
import SwiftUI

/// A server's containers, grouped by service, and its systemd services: their CPU and memory over the
/// range, and a list live, or at a moment chosen on the charts, with the processes of the one selected.
struct ContainersPage: View {
    enum Kind: String, CaseIterable, Identifiable {
        case containers = "Containers"
        case services = "Services"

        var id: Self {
            self
        }
    }

    let hive: KnownHive
    let link: HiveLink
    let serverID: UUID
    let path: MetricsPagePath

    @State private var kind: Kind
    @State private var grouping = ContainerGrouping.byService
    @State private var range = MetricsRange.hour
    @State private var state: ServerMetricsState?
    @State private var history: ServerHistory?
    @State private var cgroups: CgroupHistory?
    @State private var failure: String?
    @State private var figures: CgroupMoment?
    @State private var processes: ProcessMoment?
    @State private var figuresFailure: String?
    @State private var moment = MetricsMoment()
    @State private var selection: CgroupRow.ID?
    @State private var sortOrder = [KeyPathComparator(\CgroupRow.cpuOrder, order: .reverse)]

    init(hive: KnownHive, link: HiveLink, serverID: UUID, kind: Kind, path: MetricsPagePath) {
        self.hive = hive
        self.link = link
        self.serverID = serverID
        self.path = path
        _kind = State(initialValue: kind)
    }

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
                    // A chosen moment's figures don't change. The newest do, with every sample.
                    while !Task.isCancelled {
                        await loadFigures()
                        guard moment.chosen == nil else { return }
                        try? await Task.sleep(for: .seconds(10))
                    }
                }
        }
        .environment(moment)
        .navigationTitle(kind.rawValue)
        .locationPath(path.parts("Containers and Services", systemImage: "shippingbox"))
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
        .onChange(of: kind) { selection = nil }
        .onChange(of: grouping) { selection = nil }
    }

    @ViewBuilder private var content: some View {
        if let history, let cgroups {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Show", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                charts(cgroups, timeline: MetricsTimeline(history: history).with(bucketSeconds: cgroups.bucketSeconds))
                caption
                list(cgroups)
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

    private func charts(_ cgroups: CgroupHistory, timeline: MetricsTimeline) -> some View {
        let groups = kind == .containers ? cgroups.containers : cgroups.services
        let memory = cgroups.memory(of: groups)
        return HStack(alignment: .top, spacing: 16) {
            MetricsChart(title: "CPU", lines: cgroups.cpu(of: groups), format: .share, timeline: timeline)
            if !memory.isEmpty {
                MetricsChart(title: "Memory", lines: memory, format: .bytes, timeline: timeline)
            }
        }
    }

    private var caption: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(when)
                    .font(.headline)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if kind == .containers {
                Picker("Grouping", selection: $grouping) {
                    ForEach(ContainerGrouping.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
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
        return switch figures {
        case .sample(let takenAt, _, _, _, _):
            "\(live)\(ProcessRow.time(takenAt))"
        case .hour(let startsAt, _, _):
            "The busiest over the hour from \(ProcessRow.time(startsAt)), on average, with their highest"
        case .notKept, nil:
            moment.chosen == nil ? "Live" : kind.rawValue
        }
    }

    /// Scout sends only the busiest, so a group holds only those of its containers among them.
    private var note: String {
        switch (figures, kind) {
        case (.sample(_, let containerCount, _, let containers, _), .containers):
            let shown = containers.reduce(0) { $0 + $1.containerCount }
            guard shown < containerCount else { return "\(containerCount) running." }
            return "\(containerCount) running. Scout sends the busiest \(shown), so a group counts only those of its containers."
        case (.sample(_, _, let serviceCount, _, let services), .services):
            let shown = services.count < serviceCount
                ? "\(serviceCount) running, the busiest \(services.count) shown. "
                : "\(serviceCount) running. "
            return shown + "A service's CPU includes work that started and finished between samples, such as cron jobs."
        case (.hour, _):
            return "Single samples are kept for a day, and each hour's busiest for 90 days."
        default:
            return " "
        }
    }

    private var rows: [CgroupRow] {
        let rows: [CgroupRow] = switch (figures, kind, grouping) {
        case (.sample(_, _, _, let containers, _), .containers, .eachContainer): CgroupRow.containers(containers)
        case (.sample(_, _, _, let containers, _), .containers, .byService), (.hour(_, let containers, _), .containers, _):
            CgroupRow.groups(containers)
        case (.sample(_, _, _, _, let services), .services, _), (.hour(_, _, let services), .services, _):
            CgroupRow.services(services)
        case (.notKept, _, _), (nil, _, _):
            []
        }
        return rows.sorted(using: sortOrder)
    }

    @ViewBuilder private func list(_ cgroups: CgroupHistory) -> some View {
        switch figures {
        case .sample, .hour:
            if case .hour = figures, kind == .containers, grouping == .eachContainer {
                ContentUnavailableView(
                    "Each Container Kept for a Day",
                    systemImage: "shippingbox",
                    description: Text("After a day, Hive keeps each hour's busiest groups.")
                )
            } else if rows.isEmpty {
                ContentUnavailableView(
                    kind == .containers ? "No Containers" : "No Services",
                    systemImage: "shippingbox",
                    description: Text("Scout didn't report any at this moment.")
                )
            } else {
                HStack(alignment: .top, spacing: 12) {
                    CgroupTable(rows: rows, kind: kind, cgroups: cgroups, selection: $selection, sortOrder: $sortOrder)
                    if let selected = rows.first(where: { $0.id == selection }) {
                        CgroupProcesses(cgroup: selected, processes: processes.map(ProcessRow.rows) ?? [])
                            .frame(width: 300)
                    }
                }
            }
        case .notKept:
            ContentUnavailableView(
                "Nothing Kept",
                systemImage: "shippingbox",
                description: Text("Containers and services are kept for 90 days, and only while Scout reported.")
            )
        case nil:
            if let figuresFailure {
                ContentUnavailableView(
                    "Couldn't Read \(kind.rawValue)",
                    systemImage: "exclamationmark.triangle",
                    description: Text(figuresFailure)
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Ranges are on the server's clock, which Hive knows the offset of.
    private var serverNow: Int64 {
        Int64(Date.now.timeIntervalSince1970.rounded(.down)) + Int64(state?.scout?.clockOffsetSeconds ?? 0)
    }

    private func load() async {
        do {
            let read = try await ServerHistory.read([.cores], over: range, ofServer: serverID, from: link)
            let cgroups = try await CgroupHistory.read(over: read.history.range, ofServer: serverID, from: link)
            state = read.state
            history = read.history
            self.cgroups = cgroups
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            if history == nil { failure = HiveLink.message(for: error) }
        }
    }

    private func loadFigures() async {
        let second = moment.chosen.map(MetricsTimeline.second) ?? serverNow
        do {
            let figures = try await link.perform {
                try await $0.get(HiveEndpoint.containers(ofServer: serverID, at: second), as: CgroupMoment.self)
            }
            processes = try await link.perform {
                try await $0.get(HiveEndpoint.processes(ofServer: serverID, at: second), as: ProcessMoment.self)
            }
            self.figures = figures
            figuresFailure = nil
        } catch is CancellationError {
            return
        } catch {
            figures = nil
            processes = nil
            figuresFailure = HiveLink.message(for: error)
        }
    }
}

/// Whether the containers list shows each group, as the charts do, or each container in it.
private enum ContainerGrouping: String, CaseIterable, Identifiable {
    case byService = "By Service"
    case eachContainer = "Each Container"

    var id: Self {
        self
    }
}
