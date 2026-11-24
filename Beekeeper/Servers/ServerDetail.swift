import HiveKit
import SwiftUI

/// One server: its backup jobs, where Hive connects, its keys, a connection test, its metrics, and editing
/// or removing it.
/// A server without SSH details has none of those until they're added.
struct ServerDetail: View {
    let hive: KnownHive
    let link: HiveLink
    let servers: ServerList
    let serverID: UUID
    /// Selects the server's Hive, such as from the path or once the server is removed.
    let onShowHive: () -> Void
    /// Asks for SSH details instead when the server has none.
    let onAddJob: () -> Void
    let onSelectJob: (UUID) -> Void

    @State private var editRequest: ServerEditRequest?

    var body: some View {
        HiveConnectionGate(hive: hive, link: link) {
            if let server = servers.server(serverID) {
                page(server)
            } else {
                ContentUnavailableView("Server Not Found", systemImage: "server.rack", description: Text("It may have been removed."))
            }
        }
        .navigationTitle(servers.server(serverID)?.name ?? "Server")
        .locationPath([
            LocationPath.Part(title: hive.name, systemImage: "hexagon", action: onShowHive),
            LocationPath.Part(title: servers.server(serverID)?.name ?? "Server", systemImage: "server.rack"),
        ])
    }

    /// When any of the server's jobs last failed because the server showed another host key.
    private func hostKeyChange(of server: Server) -> HostKeyChange? {
        let statuses = servers.jobs.jobs(onServer: server.id).compactMap { servers.statuses.status(of: $0.id) }
        guard statuses.contains(where: { $0.lastRun?.run.failure == .hostKeyChanged }) else { return nil }
        return HostKeyChange(lastBackup: statuses.compactMap(\.lastSnapshotAt).max())
    }

    private func page(_ server: Server) -> some View {
        Form {
            if let connection = server.connection {
                backups(server, connection: connection)
            } else {
                Section("Backups") {
                    Text("Hive has no SSH details for this server, so it can't back it up.")
                        .foregroundStyle(.secondary)
                    Button("Add SSH Details…", systemImage: "plus", action: onAddJob)
                }
            }
            ServerMetricsSection(link: link, server: server)
        }
        .formStyle(.grouped)
        .hostsFormSheets()
        .toolbar {
            ToolbarSpacer(.flexible)
            ToolbarItemGroup {
                Button("Edit…") { editRequest = ServerEditRequest(action: .edit, server: server, servers: servers) }
                Button("Remove…", systemImage: "trash", role: .destructive) {
                    editRequest = ServerEditRequest(action: .remove, server: server, servers: servers)
                }
                .help("Remove this server")
            }
        }
        .serverEditing($editRequest) { _ in onShowHive() }
    }

    @ViewBuilder private func backups(_ server: Server, connection: ServerConnection) -> some View {
        ServerJobsSection(
            jobs: servers.jobs.jobs(onServer: server.id),
            statuses: servers.statuses,
            onAddJob: onAddJob,
            onSelectJob: onSelectJob
        )
        Section("Connection") {
            LabeledContent("Host", value: connection.host)
            LabeledContent("Port", value: String(connection.port))
            LabeledContent("SSH user", value: connection.user)
        }
        ServerQuotaSection(link: link, servers: servers, server: server)
        // A new identity, so a changed connection starts the checks over rather than showing an old result.
        Group {
            HostKeyCheck(link: link, servers: servers, server: server, change: hostKeyChange(of: server))
            AuthorizedKeySetup(link: link, server: server)
            ConnectionTestCheck(link: link, server: server)
        }
        .id(connection)
    }
}
