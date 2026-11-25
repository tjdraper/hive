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
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

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
                .reloading(every: range.refreshInterval, id: range) { await load() }
                // A chosen moment's figures don't change. The newest do, with every sample.
                .reloading(every: moment.chosen == nil ? .seconds(10) : nil, id: moment.chosen) { await loadFigures() }
        }
        .environment(moment)
        .navigationTitle(kind.rawValue)
        .locationPath(path.parts("Containers and Services", systemImage: "shippingbox"))
        .metricsRangeToolbar($range)
        .onChange(of: range) { moment.chosen = nil }
        .onChange(of: kind) { selection = nil }
        .onChange(of: grouping) { selection = nil }
    }

    @ViewBuilder private var content: some View {
        if let history, let cgroups {
            #if os(iOS)
            if sizeClass == .compact {
                compactPage(history, cgroups: cgroups)
            } else {
                page(history, cgroups: cgroups)
            }
            #else
            page(history, cgroups: cgroups)
            #endif
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

    private func page(_ history: ServerHistory, cgroups: CgroupHistory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            kindPicker
                .fixedSize()
            HStack(alignment: .top, spacing: 16) {
                ForEach(charts(history, cgroups: cgroups)) { $0 }
            }
            caption
            list(cgroups)
        }
        .padding()
    }

    private var kindPicker: some View {
        Picker("Show", selection: $kind) {
            ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// Memory is left out where the server doesn't account for it, as on cgroup v1 without its controller.
    private func charts(_ history: ServerHistory, cgroups: CgroupHistory) -> [MetricsChart] {
        let timeline = MetricsTimeline(history: history).with(bucketSeconds: cgroups.bucketSeconds)
        let groups = kind == .containers ? cgroups.containers : cgroups.services
        let memory = cgroups.memory(of: groups)
        var charts = [MetricsChart(title: "CPU", lines: cgroups.cpu(of: groups), format: .share, timeline: timeline)]
        if !memory.isEmpty {
            charts.append(MetricsChart(title: "Memory", lines: memory, format: .bytes, timeline: timeline))
        }
        return charts
    }

    #if os(iOS)
    private func compactPage(_ history: ServerHistory, cgroups: CgroupHistory) -> some View {
        CompactContainersPage(
            kind: $kind,
            range: $range,
            grouping: $grouping,
            selection: $selection,
            charts: charts(history, cgroups: cgroups),
            when: when,
            note: note,
            rows: rows.isEmpty || isEachContainerAfterADay ? nil : rows,
            cgroups: cgroups,
            processes: processes.map(ProcessRow.rows) ?? []
        ) {
            list(cgroups)
        }
    }
    #endif

    private var groupingPicker: some View {
        Picker("Grouping", selection: $grouping) {
            ForEach(ContainerGrouping.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
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
                groupingPicker
            }
            if moment.chosen != nil {
                Button("Show Live") { moment.chosen = nil }
            } else {
                Text(MetricsMoment.hint)
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

    private var rows: [CgroupRow] {
        (figures?.rows(of: kind, eachContainer: grouping == .eachContainer) ?? []).sorted(using: sortOrder)
    }

    private var note: String {
        figures?.note(of: kind) ?? " "
    }

    /// Hive keeps each container only with its sample, for a day.
    private var isEachContainerAfterADay: Bool {
        if case .hour = figures, kind == .containers, grouping == .eachContainer { return true }
        return false
    }

    @ViewBuilder private func list(_ cgroups: CgroupHistory) -> some View {
        switch figures {
        case .sample, .hour:
            if isEachContainerAfterADay {
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
enum ContainerGrouping: String, CaseIterable, Identifiable {
    case byService = "By Service"
    case eachContainer = "Each Container"

    var id: Self {
        self
    }
}
