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
    case server(hiveID: UUID, serverID: UUID)
    case job(hiveID: UUID, serverID: UUID, jobID: UUID)

    var hiveID: UUID {
        switch self {
        case .hive(let id), .server(let id, _), .job(let id, _, _): id
        }
    }

    var serverID: UUID? {
        switch self {
        case .hive: nil
        case .server(_, let id), .job(_, let id, _): id
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
    @State private var windowWidth: CGFloat = 0
    @State private var detailWidth: CGFloat = 0
    #endif

    var body: some View {
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
            detail
            #else
            detail
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { detailWidth = $0 }
                .environment(\.locationPathRoom, locationPathRoom)
            #endif
        }
        #if os(macOS)
        // A floor for the window, so no page's content can make its smallest size larger than the screen.
        .frame(minWidth: 640, minHeight: 400)
        #else
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { windowWidth = $0 }
        .groupBoxStyle(LabelAboveGroupBoxStyle())
        #endif
        .sheet(item: $addingServer) { request in
            if let link = store.link(for: request.hiveID), let servers = store.servers(for: request.hiveID) {
                AddServerSheet(link: link, servers: servers) { serverID in
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
            if selection == nil, let first = store.hives.first {
                selection = .hive(first.id)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let selection, let hive = store.hive(selection.hiveID), let link = store.link(for: hive.id),
           let servers = store.servers(for: hive.id), let recovery = store.recoveryCopies(for: hive.id) {
            switch selection {
            case .hive:
                HiveDetail(hive: hive, link: link, servers: servers, recovery: recovery, page: $page, selection: $selection) {
                    addServer(to: hive.id)
                }
            case .server(_, let serverID):
                ServerDetail(
                    hive: hive,
                    link: link,
                    servers: servers,
                    serverID: serverID,
                    onShowHive: { self.selection = .hive(hive.id) },
                    onAddJob: { addJob(to: serverID, on: hive.id) },
                    onSelectJob: { self.selection = .job(hiveID: hive.id, serverID: serverID, jobID: $0) }
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
        addingServer = AddServerRequest(hiveID: hiveID)
    }

    private func addJob(to serverID: UUID, on hiveID: UUID) {
        addingJob = AddJobRequest(hiveID: hiveID, serverID: serverID)
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

/// Which Hive the Add Server sheet adds to.
struct AddServerRequest: Identifiable {
    let hiveID: UUID

    var id: UUID {
        hiveID
    }
}
