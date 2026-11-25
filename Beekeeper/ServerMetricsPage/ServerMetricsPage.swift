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
    let onShowPage: (FigurePage) -> Void

    @State private var range = MetricsRange.hour
    @State private var state: ServerMetricsState?
    @State private var history: ServerHistory?
    @State private var cgroups: CgroupHistory?
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
        .navigationTitle(name)
        .locationPath([
            LocationPath.Part(title: hive.name, systemImage: "hexagon", action: onShowHive),
            LocationPath.Part(title: "Metrics", systemImage: "chart.xyaxis.line", action: onShowDashboard),
            LocationPath.Part(title: name, systemImage: "server.rack"),
        ])
        .metricsRangeToolbar($range)
        .onChange(of: range) { moment.chosen = nil }
        .inspector(isPresented: isShowingProcesses) {
            processes
                .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
                #if os(iOS)
                // At iPhone width the inspector is a sheet, which leaves the chart above it to choose
                // another moment on.
                .presentationDetents([.fraction(0.45), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
                #endif
        }
    }

    private var name: String {
        servers.server(serverID)?.name ?? "Server"
    }

    @ViewBuilder private var content: some View {
        if let history, let scout = state?.scout {
            #if os(iOS)
            if sizeClass == .compact {
                compactPage(history, scout: scout)
            } else {
                page(history, scout: scout)
            }
            #else
            page(history, scout: scout)
            #endif
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ServerFacts(scout: scout, history: history, serverNow: serverNow)
                hint
                LazyVGrid(columns: MetricsChart.columns, spacing: 16) {
                    ForEach(charts(history)) { $0 }
                }
            }
            .padding()
        }
    }

    #if os(iOS)
    /// The chart first, high enough on the screen that the moment's sheet leaves it in view.
    private func compactPage(_ history: ServerHistory, scout: ScoutState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MetricsRangePicker(range: $range)
                    .padding(.horizontal)
                MetricsChartPager(charts: charts(history), shown: $shownChart)
                    .frame(height: 320)
                VStack(alignment: .leading, spacing: 16) {
                    hint
                    ServerFacts(scout: scout, history: history, serverNow: serverNow)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
    #endif

    private var hint: some View {
        #if os(macOS)
        let text = "Click a chart to see the processes at that moment."
        #else
        let text = "Tap a chart to see the processes at that moment, or touch and hold to move along it."
        #endif
        return Text(moment.chosen == nil ? text : " ")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func charts(_ history: ServerHistory) -> [MetricsChart] {
        let timeline = MetricsTimeline(history: history)
        var charts = [
            MetricsChart(title: "CPU", lines: history.cpu, format: .share, timeline: timeline, yDomain: 0 ... 1, links: [processesLink]),
            MetricsChart(title: "Load", lines: history.load, format: .load, timeline: timeline),
            MetricsChart(
                title: "Memory",
                lines: history.memory,
                format: .bytes,
                timeline: timeline,
                yDomain: history.memoryTotal.map { 0 ... max($0, 1) },
                links: [processesLink]
            ),
        ]
        if let swapTotal = history.swapTotal {
            charts.append(MetricsChart(title: "Swap", lines: history.swap, format: .bytes, timeline: timeline, yDomain: 0 ... swapTotal))
            charts.append(MetricsChart(title: "Swapping, pages", lines: history.swapping, format: .perSecond, timeline: timeline))
        }
        if !history.pressure.isEmpty {
            charts.append(MetricsChart(title: "Pressure, time stalled", lines: history.pressure, format: .share, timeline: timeline))
        }
        if !history.filesystems.isEmpty {
            charts.append(MetricsChart(
                title: "Disk space used",
                lines: history.diskSpace,
                format: .share,
                timeline: timeline,
                yDomain: 0 ... 1,
                links: history.filesystems.compactMap(\.name).map { mountPoint in
                    MetricsChartLink(title: mountPoint) { onShowPage(.filesystem(mountPoint: mountPoint)) }
                }
            ))
        }
        if let cgroups {
            charts += containerCharts(cgroups, timeline: timeline.with(bucketSeconds: cgroups.bucketSeconds))
        }
        charts += history.disks.map { disk in
            MetricsChart(title: "Disk \(disk.name ?? "")", lines: history.activity(of: disk), format: .bytesPerSecond, timeline: timeline)
        }
        charts += history.interfaces.map { interface in
            MetricsChart(
                title: "Network \(interface.name ?? "")",
                lines: history.traffic(of: interface),
                format: .bytesPerSecond,
                timeline: timeline
            )
        }
        return charts
    }

    /// Containers by service, and systemd services, whose CPU counts work too brief for the process lists.
    private func containerCharts(_ cgroups: CgroupHistory, timeline: MetricsTimeline) -> [MetricsChart] {
        var charts: [MetricsChart] = []
        if !cgroups.containers.isEmpty {
            charts.append(MetricsChart(
                title: "Containers, CPU",
                lines: cgroups.cpu(of: cgroups.containers),
                format: .share,
                timeline: timeline,
                links: [MetricsChartLink(title: "Containers") { onShowPage(.cgroups(.containers)) }]
            ))
        }
        if !cgroups.services.isEmpty {
            charts.append(MetricsChart(
                title: "Services, CPU",
                lines: cgroups.cpu(of: cgroups.services),
                format: .share,
                timeline: timeline,
                links: [MetricsChartLink(title: "Services") { onShowPage(.cgroups(.services)) }]
            ))
        }
        return charts
    }

    private var processesLink: MetricsChartLink {
        MetricsChartLink(title: "Processes") { onShowPage(.processes) }
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
            let read = try await ServerHistory.read(ServerHistory.figures, over: range, ofServer: serverID, from: link)
            let cgroups = try await CgroupHistory.read(over: read.history.range, ofServer: serverID, from: link)
            state = read.state
            history = read.history
            self.cgroups = cgroups
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            // The charts already showing stay, rather than giving way to a passing failure.
            if history == nil { failure = HiveLink.message(for: error) }
        }
    }
}
