#if os(iOS)
import HiveKit
import SwiftUI

/// The main window at iPhone width: the Hives, then one Hive, one server and one job, each pushed on the
/// last. The stack follows the selection, so anything that selects a Hive or server goes back to it.
struct CompactNavigation<Destination: View>: View {
    @Binding var selection: SidebarItem?
    @ViewBuilder let destination: (SidebarItem) -> Destination

    var body: some View {
        NavigationStack(path: path) {
            CompactHiveList { selection = .hive($0) }
                .navigationDestination(for: SidebarItem.self, destination: destination)
        }
    }

    private var path: Binding<[SidebarItem]> {
        Binding {
            selection?.ancestry ?? []
        } set: {
            selection = $0.last
        }
    }
}

private extension SidebarItem {
    var ancestry: [SidebarItem] {
        switch self {
        case .hive:
            [self]
        case .server(let hiveID, _):
            [.hive(hiveID), self]
        case .job(let hiveID, let serverID, _):
            [.hive(hiveID), .server(hiveID: hiveID, serverID: serverID), self]
        }
    }
}

/// Each Hive with how its connection and its jobs stand. Its servers are on its own page.
private struct CompactHiveList: View {
    let onPaired: (UUID) -> Void

    @Environment(HiveListStore.self) private var store
    @Environment(\.addHive) private var addHive
    @State private var removing: KnownHive?

    var body: some View {
        Group {
            if store.hives.isEmpty {
                EmptyHiveList(onPaired: onPaired)
            } else {
                List(store.hives) { hive in
                    NavigationLink(value: SidebarItem.hive(hive.id)) {
                        CompactHiveRow(hive: hive)
                    }
                    .swipeActions {
                        // Not the destructive role, which would take the row away before the removal is confirmed.
                        Button("Remove", systemImage: "trash") { removing = hive }
                            .tint(.red)
                    }
                    .contextMenu {
                        Button("Remove from Beekeeper…", systemImage: "trash", role: .destructive) { removing = hive }
                    }
                }
            }
        }
        .navigationTitle("Hives")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add a Hive", systemImage: "plus") { addHive?() }
            }
        }
        .hiveRemoval($removing) { await store.removeRevokingThisDevice($0.id) }
    }
}

private struct CompactHiveRow: View {
    let hive: KnownHive

    @Environment(HiveListStore.self) private var store

    var body: some View {
        let status = store.link(for: hive.id)?.status ?? .notPaired
        // The status's word gives way before the Hive's name does, leaving its dot.
        ViewThatFits(in: .horizontal) {
            row(status: status, showsStatusWord: true)
            row(status: status, showsStatusWord: false)
        }
    }

    private func row(status: HiveLink.Status, showsStatusWord: Bool) -> some View {
        HStack(spacing: 6) {
            Label(hive.name, systemImage: "hexagon")
                .lineLimit(1)
            Spacer()
            if status == .connected, let servers = store.servers(for: hive.id) {
                JobHealthBadge(health: JobHealth(jobs: servers.jobs.jobs, in: servers.statuses))
            }
            HiveStatusBadge(status: status, showsWord: showsStatusWord)
        }
    }
}
#endif
