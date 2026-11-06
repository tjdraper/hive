import SwiftUI

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

    var systemImage: String {
        switch self {
        case .overview: "house"
        case .devices: "laptopcomputer.and.iphone"
        case .auditLog: "list.bullet.rectangle"
        case .settings: "gearshape"
        }
    }
}

struct SidebarItem: Hashable {
    let hiveID: UUID
    let page: HivePage
}

struct MainWindow: View {
    /// Often enough that the sidebar notices a Hive going offline or coming back without a click.
    private static let refreshInterval = Duration.seconds(30)

    @Environment(HiveListStore.self) private var store
    @State private var selection: SidebarItem?

    var body: some View {
        NavigationSplitView {
            HiveSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            detail
        }
        // A floor for the window, so no page's content can make its smallest size larger than the screen.
        .frame(minWidth: 640, minHeight: 400)
        .task {
            while !Task.isCancelled {
                await store.refreshAll()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
        .onAppear {
            if selection == nil, let first = store.hives.first {
                selection = SidebarItem(hiveID: first.id, page: .overview)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let selection, let hive = store.hive(selection.hiveID), let link = store.link(for: hive.id) {
            HiveDetail(hive: hive, link: link, page: selection.page)
        } else if store.hives.isEmpty {
            EmptyHiveList { hiveID in
                selection = SidebarItem(hiveID: hiveID, page: .overview)
            }
        } else {
            ContentUnavailableView("Choose a Hive", systemImage: "hexagon")
        }
    }
}
