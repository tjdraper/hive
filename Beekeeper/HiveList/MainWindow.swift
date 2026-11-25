import HiveKit
import SwiftUI

/// A Hive's own pages, switched in the toolbar when the Hive is selected in the sidebar.
enum HivePage: String, CaseIterable, Identifiable {
    case overview
    case jobLog
    case auditLog
    case devices
    case settings

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .jobLog: "Job Log"
        case .devices: "Devices"
        case .auditLog: "Audit Log"
        case .settings: "Settings"
        }
    }
}

enum SidebarItem: Hashable {
    case hive(UUID)
    /// The Hive's servers' metrics together.
    case dashboard(hiveID: UUID)
    case server(hiveID: UUID, serverID: UUID)
    /// A server's metrics page, reached from the dashboard and from the server's page.
    case serverMetrics(hiveID: UUID, serverID: UUID)
    /// One kind of a server's figures, reached from its metrics page.
    case figurePage(hiveID: UUID, serverID: UUID, page: FigurePage)
    case job(hiveID: UUID, serverID: UUID, jobID: UUID)

    var hiveID: UUID {
        switch self {
        case .hive(let id), .dashboard(let id), .server(let id, _), .serverMetrics(let id, _), .figurePage(let id, _, _),
             .job(let id, _, _): id
        }
    }

    var serverID: UUID? {
        switch self {
        case .hive, .dashboard: nil
        case .server(_, let id), .serverMetrics(_, let id), .figurePage(_, let id, _), .job(_, let id, _): id
        }
    }
}

struct MainWindow: View {
    /// Often enough that the sidebar notices a Hive going offline or coming back without a click.
    private static let refreshInterval = Duration.seconds(30)
    /// A Hive that didn't answer is often only starting, such as just after an update or a restart, so
    /// it's asked again soon, then less often while it stays away.
    private static let firstRetry = Duration.seconds(1)

    @Environment(HiveListStore.self) private var store
    @State private var selection: SidebarItem?
    @State private var page = HivePage.overview
    @State private var addingServer: AddServerRequest?
    @State private var addingJob: AddJobRequest?
    @State private var isAddingHive = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var windowWidth: CGFloat = 0
    @State private var detailWidth: CGFloat = 0
    #endif

    var body: some View {
        navigation
            #if os(macOS)
            // A floor for the window, so no page's content can make its smallest size larger than the screen.
            .frame(minWidth: 640, minHeight: 400)
            #else
            .groupBoxStyle(LabelAboveGroupBoxStyle())
            #endif
            .sheet(item: $addingServer) { request in
                if let link = store.link(for: request.hiveID), let servers = store.servers(for: request.hiveID) {
                    AddServerSheet(link: link, servers: servers, addingSSHDetailsTo: request.serverID.flatMap(servers.server)) { serverID in
                        selection = .server(hiveID: request.hiveID, serverID: serverID)
                    }
                }
            }
            .sheet(item: $addingJob) { request in
                if let servers = store.servers(for: request.hiveID) {
                    JobEditorSheet(jobs: servers.jobs, serverID: request.serverID, job: nil) { job in
                        selection = .job(hiveID: request.hiveID, serverID: job.serverID, jobID: job.id)
                    }
                }
            }
            .sheet(isPresented: $isAddingHive) {
                AddHiveSheet { hiveID in
                    selection = .hive(hiveID)
                }
            }
            .environment(\.addHive, addHive)
            .focusedSceneValue(\.addHive, addHive)
            .task {
                var retry = Self.firstRetry
                while !Task.isCancelled {
                    await store.refreshAll()
                    if store.hasOfflineHive {
                        try? await Task.sleep(for: retry)
                        retry = min(retry * 2, Self.refreshInterval)
                    } else {
                        retry = Self.firstRetry
                        try? await Task.sleep(for: Self.refreshInterval)
                    }
                }
            }
            .onAppear {
                // At iPhone width the list of Hives is the first page, and selecting one would leave it.
                if !isCompact, selection == nil, let first = store.hives.first {
                    selection = .hive(first.id)
                }
            }
    }

    @ViewBuilder private var navigation: some View {
        #if os(iOS)
        if isCompact {
            CompactNavigation(selection: $selection) { item in
                detail(for: item)
            }
        } else {
            splitView
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { windowWidth = $0 }
        }
        #else
        splitView
        #endif
    }

    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var splitView: some View {
        NavigationSplitView {
            HiveSidebar(selection: $selection, onAddServer: addServer, onAddJob: addJob)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
                #else
                // Wide enough for a server's name beside its status, which iPad's larger text needs more room for.
                .navigationSplitViewColumnWidth(min: 280, ideal: 320)
                #endif
                // Nothing in it takes typing, so a keyboard for the detail or a sheet leaves it alone.
                .ignoresSafeArea(.keyboard)
        } detail: {
            #if os(macOS)
            detail(for: selection)
            #else
            detail(for: selection)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { detailWidth = $0 }
                .environment(\.locationPathRoom, locationPathRoom)
            #endif
        }
    }

    @ViewBuilder
    private func detail(for item: SidebarItem?) -> some View {
        if let item, let hive = store.hive(item.hiveID), let link = store.link(for: hive.id),
           let servers = store.servers(for: hive.id), let recovery = store.recoveryCopies(for: hive.id) {
            switch item {
            case .hive:
                HiveDetail(hive: hive, link: link, servers: servers, recovery: recovery, page: $page, selection: $selection) {
                    addServer(to: hive.id)
                }
                // Otherwise another Hive's page keeps this one's state, and its loads stay on this Hive.
                .id(hive.id)
            case .dashboard, .serverMetrics, .figurePage:
                metricsDetail(for: item, hive: hive, link: link, servers: servers)
            case .server(_, let serverID):
                ServerDetail(
                    hive: hive,
                    link: link,
                    servers: servers,
                    serverID: serverID,
                    onShowHive: { self.selection = .hive(hive.id) },
                    onAddJob: { addJob(to: serverID, on: hive.id) },
                    onSelectJob: { self.selection = .job(hiveID: hive.id, serverID: serverID, jobID: $0) },
                    onShowMetrics: { self.selection = .serverMetrics(hiveID: hive.id, serverID: serverID) }
                )
                .id(serverID)
            case .job(_, let serverID, let jobID):
                JobDetail(
                    hive: hive,
                    link: link,
                    servers: servers,
                    jobID: jobID,
                    onShowHive: { self.selection = .hive(hive.id) },
                    onShowServer: { self.selection = .server(hiveID: hive.id, serverID: serverID) }
                )
                .id(jobID)
            }
        } else if store.hives.isEmpty {
            EmptyHiveList { hiveID in
                selection = .hive(hiveID)
            }
        } else {
            ContentUnavailableView("Choose a Hive", systemImage: "hexagon")
        }
    }

    @ViewBuilder
    private func metricsDetail(for item: SidebarItem, hive: KnownHive, link: HiveLink, servers: ServerList) -> some View {
        switch item {
        case .serverMetrics(_, let serverID):
            ServerMetricsPage(
                hive: hive,
                link: link,
                servers: servers,
                serverID: serverID,
                onShowHive: { self.selection = .hive(hive.id) },
                onShowDashboard: { self.selection = .dashboard(hiveID: hive.id) },
                onShowPage: { self.selection = .figurePage(hiveID: hive.id, serverID: serverID, page: $0) }
            )
            .id(serverID)
        case .figurePage(_, let serverID, let page):
            let path = MetricsPagePath(
                hiveName: hive.name,
                serverName: servers.server(serverID)?.name ?? "Server",
                onShowHive: { self.selection = .hive(hive.id) },
                onShowDashboard: { self.selection = .dashboard(hiveID: hive.id) },
                onShowServer: { self.selection = .serverMetrics(hiveID: hive.id, serverID: serverID) }
            )
            Group {
                switch page {
                case .processes:
                    ProcessesPage(hive: hive, link: link, serverID: serverID, path: path)
                case .cgroups(let kind):
                    ContainersPage(hive: hive, link: link, serverID: serverID, kind: kind, path: path)
                case .filesystem(let mountPoint):
                    FilesystemPage(hive: hive, link: link, serverID: serverID, mountPoint: mountPoint, path: path)
                }
            }
            .id(item)
        default:
            MetricsDashboard(
                hive: hive,
                link: link,
                servers: servers,
                live: store.liveMetrics(for: hive.id),
                onShowHive: { self.selection = .hive(hive.id) },
                onSelectServer: { self.selection = .serverMetrics(hiveID: hive.id, serverID: $0) }
            )
            .id(hive.id)
        }
    }

    #if os(iOS)
    /// The detail's toolbar, less what the page's buttons and the toolbar's margins take. With the sidebar
    /// hidden, the window's controls and the sidebar button are in it too. Measured on iPadOS 26.
    private var locationPathRoom: CGFloat? {
        guard detailWidth > 0 else { return nil }
        let pageButtonsAndMargins: CGFloat = 200
        let windowControls: CGFloat = windowWidth - detailWidth < 1 ? 130 : 0
        return detailWidth - pageButtonsAndMargins - windowControls
    }
    #endif

    private var addHive: AddHiveAction {
        AddHiveAction { isAddingHive = true }
    }

    private func addServer(to hiveID: UUID) {
        addingServer = AddServerRequest(hiveID: hiveID, serverID: nil)
    }

    /// A server without SSH details gets them first, since Hive can't back it up without them.
    private func addJob(to serverID: UUID, on hiveID: UUID) {
        if let server = store.servers(for: hiveID)?.server(serverID), server.connection == nil {
            addingServer = AddServerRequest(hiveID: hiveID, serverID: serverID)
        } else {
            addingJob = AddJobRequest(hiveID: hiveID, serverID: serverID)
        }
    }
}

/// Which server the job editor adds a job to.
struct AddJobRequest: Identifiable {
    let hiveID: UUID
    let serverID: UUID

    var id: UUID {
        serverID
    }
}

/// Which Hive the Add Server sheet adds to, or which server without SSH details it gives them to.
struct AddServerRequest: Identifiable {
    let hiveID: UUID
    let serverID: UUID?

    var id: UUID {
        serverID ?? hiveID
    }
}
