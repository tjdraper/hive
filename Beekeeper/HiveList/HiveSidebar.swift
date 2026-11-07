import HiveKit
import SwiftUI

/// Each Hive with its servers under it.
struct HiveSidebar: View {
    @Environment(HiveListStore.self) private var store
    @Binding var selection: SidebarItem?
    let onAddServer: (UUID) -> Void

    /// Hives are open until closed, so a new one shows its servers.
    @State private var collapsed: Set<UUID> = []

    var body: some View {
        List(selection: $selection) {
            ForEach(store.hives) { hive in
                DisclosureGroup(isExpanded: expanded(hive.id)) {
                    ForEach(store.servers(for: hive.id)?.servers ?? []) { server in
                        NavigationLink(value: SidebarItem.server(hiveID: hive.id, serverID: server.id)) {
                            ServerSidebarRow(server: server)
                        }
                    }
                } label: {
                    NavigationLink(value: SidebarItem.hive(hive.id)) {
                        HiveSidebarRow(hive: hive, status: store.link(for: hive.id)?.status ?? .notPaired)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button("Add Server", systemImage: "plus") {
                    if let hiveID = hiveToAddTo { onAddServer(hiveID) }
                }
                .disabled(hiveToAddTo.map { store.link(for: $0)?.status != .connected } ?? true)
                .help(hiveToAddTo == nil ? "Choose a Hive to add a server to." : "Add a server to this Hive.")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
    }

    /// The selected Hive, or the only one.
    private var hiveToAddTo: UUID? {
        selection?.hiveID ?? (store.hives.count == 1 ? store.hives.first?.id : nil)
    }

    private func expanded(_ id: UUID) -> Binding<Bool> {
        Binding {
            !collapsed.contains(id)
        } set: { isExpanded in
            if isExpanded { collapsed.remove(id) } else { collapsed.insert(id) }
        }
    }
}

private struct HiveSidebarRow: View {
    let hive: KnownHive
    let status: HiveLink.Status

    var body: some View {
        HStack(spacing: 6) {
            Label(hive.name, systemImage: "hexagon")
                .lineLimit(1)
            Spacer()
            HiveStatusBadge(status: status)
        }
    }
}

private struct ServerSidebarRow: View {
    let server: Server

    var body: some View {
        HStack(spacing: 6) {
            Label(server.name, systemImage: "server.rack")
                .lineLimit(1)
            Spacer()
            if !server.isSetUp {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                    .help("Not set up yet")
                    .accessibilityLabel("Not set up yet")
            }
        }
    }
}

/// A dot and a word for how the Hive's connection stands.
struct HiveStatusBadge: View {
    let status: HiveLink.Status

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch status {
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .offline: "Offline"
        case .identityChanged: "Identity changed"
        case .notRecognized, .notPaired: "Not paired"
        case .lockedOut: "Locked out"
        case .needsUpdate: "Needs update"
        case .failed: "Problem"
        }
    }

    private var color: Color {
        switch status {
        case .connected: .green
        case .connecting, .offline: .secondary
        case .identityChanged, .notRecognized, .failed: .red
        case .notPaired, .lockedOut, .needsUpdate: .orange
        }
    }
}
