import HiveKit
import SwiftUI

/// Each Hive with its servers under it.
struct HiveSidebar: View {
    @Environment(HiveListStore.self) private var store
    @Binding var selection: SidebarItem?
    let onAddServer: (UUID) -> Void
    let onAddJob: (_ serverID: UUID, _ hiveID: UUID) -> Void

    /// Hives and servers are open until closed, so a new one shows what's under it.
    @State private var collapsed: Set<UUID> = []
    @State private var editRequest: ServerEditRequest?
    @State private var jobEditRequest: JobEditRequest?
    @State private var removing: KnownHive?

    var body: some View {
        List(selection: $selection) {
            ForEach(store.hives) { hive in
                DisclosureGroup(isExpanded: expanded(hive.id)) {
                    if let servers = store.servers(for: hive.id) {
                        ForEach(servers.servers) { server in
                            serverRow(server, in: servers, hiveID: hive.id)
                        }
                    }
                } label: {
                    NavigationLink(value: SidebarItem.hive(hive.id)) {
                        HiveSidebarRow(hive: hive, status: store.link(for: hive.id)?.status ?? .notPaired)
                    }
                    .contextMenu {
                        Button("Remove from Beekeeper…", role: .destructive) { removing = hive }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .serverEditing($editRequest) { removed in
            if let selection, selection.serverID == removed.id { self.selection = .hive(selection.hiveID) }
        }
        .jobEditing($jobEditRequest) { removed in
            if case .job(let hiveID, let serverID, removed.id) = selection { selection = .server(hiveID: hiveID, serverID: serverID) }
        }
        .confirmationDialog(
            "Remove “\(removing?.name ?? "")” from Beekeeper?",
            isPresented: Binding { removing != nil } set: { if !$0 { removing = nil } },
            presenting: removing
        ) { hive in
            Button("Remove", role: .destructive) { Task { await remove(hive) } }
        } message: { hive in
            Text(removalMessage(for: hive))
        }
        .onChange(of: selection) { _, selected in
            if let selected, let serverID = selected.serverID {
                collapsed.remove(selected.hiveID)
                if case .job = selected { collapsed.remove(serverID) }
            }
        }
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

    @ViewBuilder
    private func serverRow(_ server: Server, in servers: ServerList, hiveID: UUID) -> some View {
        let jobs = servers.jobs.jobs(onServer: server.id)
        let link = NavigationLink(value: SidebarItem.server(hiveID: hiveID, serverID: server.id)) {
            ServerSidebarRow(server: server, health: JobHealth(jobs: jobs, in: servers.statuses))
        }
        .contextMenu {
            Button("Add Job…") { onAddJob(server.id, hiveID) }
            Divider()
            Button("Edit…") { editRequest = ServerEditRequest(action: .edit, server: server, servers: servers) }
            Button("Remove…", role: .destructive) {
                editRequest = ServerEditRequest(action: .remove, server: server, servers: servers)
            }
        }

        if jobs.isEmpty {
            link
        } else {
            DisclosureGroup(isExpanded: expanded(server: server.id, hiveID: hiveID)) {
                ForEach(jobs) { job in
                    NavigationLink(value: SidebarItem.job(hiveID: hiveID, serverID: server.id, jobID: job.id)) {
                        HStack(spacing: 6) {
                            Label(job.name, systemImage: "archivebox")
                                .lineLimit(1)
                            Spacer()
                            JobHealthBadge(health: JobHealth(servers.statuses.status(of: job.id)))
                        }
                    }
                    .contextMenu {
                        Button("Edit…") { jobEditRequest = JobEditRequest(action: .edit, job: job, jobs: servers.jobs) }
                        Button("Remove…", role: .destructive) {
                            jobEditRequest = JobEditRequest(action: .remove, job: job, jobs: servers.jobs)
                        }
                    }
                }
            } label: {
                link
            }
        }
    }

    private func remove(_ hive: KnownHive) async {
        if selection?.hiveID == hive.id { selection = nil }
        await store.removeRevokingThisDevice(hive.id)
        if selection == nil, let first = store.hives.first { selection = .hive(first.id) }
    }

    private func removalMessage(for hive: KnownHive) -> String {
        let again = hive.isOnThisMac
            ? "This Mac can pair with it again with no code."
            : "Pairing again takes a code from a device that's paired with it."
        if store.link(for: hive.id)?.status == .connected {
            return "Beekeeper revokes this device on the Hive, so it leaves the Hive's device list, and forgets its key. " + again
        }
        return "Beekeeper can't reach the Hive, so this device stays in the Hive's device list until it's revoked from another "
            + "device. Beekeeper forgets its key. " + again
    }

    /// The selected Hive, or the only one.
    private var hiveToAddTo: UUID? {
        selection?.hiveID ?? (store.hives.count == 1 ? store.hives.first?.id : nil)
    }

    private func expanded(_ id: UUID) -> Binding<Bool> {
        Binding {
            !collapsed.contains(id)
        } set: { isExpanded in
            if isExpanded {
                collapsed.remove(id)
            } else {
                collapsed.insert(id)
                // As in Finder, a selection that would be hidden moves up to what still shows.
                if let selection, selection != .hive(id), selection.hiveID == id { self.selection = .hive(id) }
            }
        }
    }

    private func expanded(server serverID: UUID, hiveID: UUID) -> Binding<Bool> {
        Binding {
            !collapsed.contains(serverID)
        } set: { isExpanded in
            if isExpanded {
                collapsed.remove(serverID)
            } else {
                collapsed.insert(serverID)
                if case .job(_, serverID, _) = selection { selection = .server(hiveID: hiveID, serverID: serverID) }
            }
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
    let health: JobHealth

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
            } else {
                JobHealthBadge(health: health)
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
        case .pairingAgain: "Pairing again"
        case .restarting: "Restarting"
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
        case .connecting, .pairingAgain, .restarting, .offline: .secondary
        case .identityChanged, .notRecognized, .failed: .red
        case .notPaired, .lockedOut, .needsUpdate: .orange
        }
    }
}
