import HiveKit
import SwiftUI

/// A card for each of the Hive's servers with metrics, problems first, moving with live updates.
struct MetricsDashboard: View {
    let hive: KnownHive
    let link: HiveLink
    let servers: ServerList
    let live: LiveServerMetrics?
    let onShowHive: () -> Void
    let onSelectServer: (UUID) -> Void

    /// Live updates carry only each server's newest figures, so the summaries are read again for whether
    /// each is still reporting and for its last hour, which gains a minute at a time.
    private static let refreshInterval = Duration.seconds(30)

    @State private var summaries: [ServerMetricsSummary]?
    @State private var failure: String?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        HiveConnectionGate(hive: hive, link: link) {
            content
                .reloading(every: Self.refreshInterval, id: hive.id) { await load() }
                .onChange(of: hasServerMissingFromSummaries) { _, missing in
                    if missing { Task { await load() } }
                }
        }
        .navigationTitle("Metrics")
        .locationPath([
            LocationPath.Part(title: hive.name, systemImage: "hexagon", action: onShowHive),
            LocationPath.Part(title: "Metrics", systemImage: "chart.xyaxis.line"),
        ])
    }

    @ViewBuilder private var content: some View {
        if let summaries {
            let arranged = DashboardServer.arranged(summaries, names: names, live: live?.latest ?? [:])
            if arranged.isEmpty {
                ContentUnavailableView(
                    "No Servers with Metrics",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Add metrics to a server from its page. It shows here once its Scout reports.")
                )
            } else {
                #if os(iOS)
                if sizeClass == .compact {
                    rows(arranged)
                } else {
                    cards(arranged)
                }
                #else
                cards(arranged)
                #endif
            }
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

    private func cards(_ arranged: [DashboardServer]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16, alignment: .top)], spacing: 16) {
                ForEach(arranged) { server in
                    Button { onSelectServer(server.id) } label: {
                        ServerMetricsCard(server: server)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .animation(.default, value: arranged.map(\.id))
        }
    }

    #if os(iOS)
    private func rows(_ arranged: [DashboardServer]) -> some View {
        List(arranged) { server in
            Button { onSelectServer(server.id) } label: {
                HStack {
                    ServerMetricsRow(server: server)
                    Image(systemName: "chevron.forward")
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .animation(.default, value: arranged.map(\.id))
    }
    #endif

    private var names: [UUID: String] {
        Dictionary(servers.servers.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// A server whose Scout has just enrolled reports live before the summaries list it.
    private var hasServerMissingFromSummaries: Bool {
        guard let summaries, let live else { return false }
        let listed = Set(summaries.map(\.serverID))
        return live.latest.keys.contains { !listed.contains($0) }
    }

    private func load() async {
        do {
            summaries = try await link.perform { try await $0.get(HiveEndpoint.metricsSummary) }
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            // The cards already showing stay, rather than giving way to a passing failure.
            if summaries == nil { failure = HiveLink.message(for: error) }
        }
    }
}
