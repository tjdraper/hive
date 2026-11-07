import Foundation
import HiveKit
import Observation

/// One Hive's servers, as it last listed them, kept in step with what this device changes.
@Observable
final class ServerList {
    private(set) var servers: [Server] = []
    private let link: HiveLink

    init(link: HiveLink) {
        self.link = link
    }

    func server(_ id: UUID) -> Server? {
        servers.first { $0.id == id }
    }

    /// Keeps the last list when the Hive can't be reached, so the sidebar doesn't empty while it's offline.
    func refresh() async {
        guard let listed: [Server] = try? await link.perform({ try await $0.get(HiveEndpoint.servers) }) else { return }
        servers = Self.sorted(listed)
    }

    func add(_ draft: ServerDraft) async throws -> Server {
        let server: Server = try await link.perform { try await $0.post(HiveEndpoint.servers, body: draft) }
        update(server)
        return server
    }

    func change(_ id: UUID, to draft: ServerDraft) async throws -> Server {
        let server: Server = try await link.perform { try await $0.put(HiveEndpoint.server(id), body: draft) }
        update(server)
        return server
    }

    func remove(_ id: UUID) async throws {
        try await link.perform { try await $0.delete(HiveEndpoint.server(id)) }
        servers.removeAll { $0.id == id }
    }

    /// Takes a server as Hive last sent it, such as after its host key was confirmed.
    func update(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        servers = Self.sorted(servers + [server])
    }

    private static func sorted(_ servers: [Server]) -> [Server] {
        servers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

extension Server {
    /// Hive won't connect until its host key is confirmed, and a server from before Hive made keys has none.
    var isSetUp: Bool {
        confirmedHostKey != nil && sshKeyFingerprint != nil
    }
}
