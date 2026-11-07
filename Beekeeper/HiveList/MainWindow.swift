import SwiftUI

/// A Hive's own pages, switched in the toolbar when the Hive is selected in the sidebar.
enum HivePage: String, CaseIterable, Identifiable {
    case overview
    case devices
    case auditLog
    case settings

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .devices: "Devices"
        case .auditLog: "Audit Log"
        case .settings: "Settings"
        }
    }
}

enum SidebarItem: Hashable {
    case hive(UUID)
    case server(hiveID: UUID, serverID: UUID)

    var hiveID: UUID {
        switch self {
        case .hive(let id), .server(let id, _): id
        }
    }
}

struct MainWindow: View {
    /// Often enough that the sidebar notices a Hive going offline or coming back without a click.
    private static let refreshInterval = Duration.seconds(30)

    @Environment(HiveListStore.self) private var store
    @State private var selection: SidebarItem?
    @State private var page = HivePage.overview
    @State private var addingServer: AddServerRequest?

    var body: some View {
        NavigationSplitView {
            HiveSidebar(selection: $selection, onAddServer: addServer)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            detail
        }
        // A floor for the window, so no page's content can make its smallest size larger than the screen.
        .frame(minWidth: 640, minHeight: 400)
        .sheet(item: $addingServer) { request in
            if let link = store.link(for: request.hiveID), let servers = store.servers(for: request.hiveID) {
                AddServerSheet(link: link, servers: servers) { serverID in
                    selection = .server(hiveID: request.hiveID, serverID: serverID)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await store.refreshAll()
                try? await Task.sleep(for: Self.refreshInterval)
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
           let servers = store.servers(for: hive.id) {
            switch selection {
            case .hive:
                HiveDetail(hive: hive, link: link, servers: servers, page: $page, selection: $selection) {
                    addServer(to: hive.id)
                }
            case .server(_, let serverID):
                ServerDetail(hive: hive, link: link, servers: servers, serverID: serverID) {
                    self.selection = .hive(hive.id)
                }
                .id(serverID)
            }
        } else if store.hives.isEmpty {
            EmptyHiveList { hiveID in
                selection = .hive(hiveID)
            }
        } else {
            ContentUnavailableView("Choose a Hive", systemImage: "hexagon")
        }
    }

    private func addServer(to hiveID: UUID) {
        addingServer = AddServerRequest(hiveID: hiveID)
    }
}

/// Which Hive the Add Server sheet adds to.
struct AddServerRequest: Identifiable {
    let hiveID: UUID

    var id: UUID {
        hiveID
    }
}
