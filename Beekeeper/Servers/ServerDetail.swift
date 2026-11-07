import HiveKit
import SwiftUI

/// One server: where Hive connects, its keys, a connection test, and editing or removing it.
struct ServerDetail: View {
    let hive: KnownHive
    let link: HiveLink
    let servers: ServerList
    let serverID: UUID
    let onRemoved: () -> Void

    @State private var isEditing = false
    @State private var isConfirmingRemoval = false
    @State private var failure: String?

    var body: some View {
        HiveConnectionGate(hive: hive, link: link) {
            if let server = servers.server(serverID) {
                page(server)
            } else {
                ContentUnavailableView("Server Not Found", systemImage: "server.rack", description: Text("It may have been removed."))
            }
        }
        .navigationTitle(servers.server(serverID)?.name ?? "Server")
        #if os(macOS)
        .navigationSubtitle(hive.name)
        #endif
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
            Section {
                HStack {
                    if let failure {
                        Text(failure)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button("Remove Server…", role: .destructive) { isConfirmingRemoval = true }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            Button("Edit…") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            EditServerSheet(servers: servers, server: server)
        }
        .confirmationDialog("Remove “\(server.name)”?", isPresented: $isConfirmingRemoval) {
            Button("Remove Server", role: .destructive) { Task { await remove(server) } }
        } message: {
            Text("Its backup jobs are removed with it. Their snapshots stay on the backup drive.")
        }
    }

    private func remove(_ server: Server) async {
        do {
            try await servers.remove(server.id)
            onRemoved()
        } catch {
            failure = HiveLink.message(for: error)
        }
    }
}
