import HiveKit
import SwiftUI

/// One server: where Hive connects, its keys, a connection test, and editing or removing it.
struct ServerDetail: View {
    let hive: KnownHive
    let link: HiveLink
    let servers: ServerList
    let serverID: UUID
    /// Selects the server's Hive, such as from the path or once the server is removed.
    let onShowHive: () -> Void

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

    private func page(_ server: Server) -> some View {
        Form {
            Section("Connection") {
                LabeledContent("Host", value: server.connection.host)
                LabeledContent("Port", value: String(server.connection.port))
                LabeledContent("SSH user", value: server.connection.user)
            }
            // A new identity, so a changed connection starts the checks over rather than showing an old result.
            Group {
                HostKeyCheck(link: link, servers: servers, server: server)
                AuthorizedKeySetup(link: link, server: server)
                ConnectionTestCheck(link: link, server: server)
            }
            .id(server.connection)
        }
        .formStyle(.grouped)
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
}
