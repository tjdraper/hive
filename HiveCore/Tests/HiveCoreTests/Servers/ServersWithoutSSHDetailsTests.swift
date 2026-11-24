import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct ServersWithoutSSHDetailsTests {
    private static let nameOnly = ServerDraft(name: "Metrics Only", connection: nil, quotaBytes: nil)
    private static let connectionMissing = [ConfigurationProblem(field: .connection, reason: .missing)]

    private let fixture: APIFixture

    init() throws {
        fixture = try APIFixture()
    }

    @Test("A server can be added by name only, with no SSH key of Hive's")
    func addsByNameOnly() async throws {
        // Act
        let server = try await fixture.addServer(Self.nameOnly)

        // Assert
        #expect(server.connection == nil)
        #expect(server.sshKeyFingerprint == nil)
        #expect(try fixture.servers.server(id: server.id) == server)
        #expect(try fixture.auditEvents().first == .server(
            serverID: server.id,
            serverName: "Metrics Only",
            change: .added(connection: nil)
        ))
    }

    @Test("A server's first SSH details need no confirmation, and give it an SSH key of Hive's")
    func addsSSHDetails() async throws {
        // Arrange
        let server = try await fixture.addServer(Self.nameOnly)
        let connection = ServerConnection(host: "web.example.com", user: "backup")
        let draft = ServerDraft(name: server.name, connection: connection, quotaBytes: nil)

        // Act
        let answer = try await fixture.send(.put, HiveEndpoint.server(server.id), json: draft)

        // Assert
        #expect(answer.status == .ok)
        let changed = try answer.decoded(as: Server.self)
        #expect(changed.connection == connection)
        let key = try #require(try ServerSSHKeyStore(database: fixture.signIn.database).publicKey(forServer: server.id))
        #expect(changed.sshKeyFingerprint == key.fingerprint)
        #expect(try fixture.auditEvents().first == .server(
            serverID: server.id,
            serverName: server.name,
            change: .connection(old: nil, new: connection)
        ))
    }

    @Test("A server without SSH details can't get a backup job until it has them")
    func jobNeedsSSHDetails() async throws {
        // Arrange
        let server = try await fixture.addServer(Self.nameOnly)
        let before = try fixture.auditEvents()

        // Act
        let refused = try await fixture.send(.post, HiveEndpoint.jobs(onServer: server.id), json: ConfigurationSamples.job())
        var draft = server.draft
        draft.connection = ConfigurationSamples.server.connection
        _ = try await fixture.send(.put, HiveEndpoint.server(server.id), json: draft)
        let accepted = try await fixture.send(.post, HiveEndpoint.jobs(onServer: server.id), json: ConfigurationSamples.job())

        // Assert
        #expect(refused.status == .unprocessableContent)
        #expect(try refused.problems == Self.connectionMissing)
        #expect(accepted.status == .created)
        #expect(try fixture.jobs.jobs(onServer: server.id)?.count == 1)
        #expect(try fixture.auditEvents().count == before.count + 2)
    }

    @Test("A server's SSH details can't be taken away, even confirmed", arguments: [false, true])
    func keepsSSHDetails(withJob: Bool) async throws {
        // Arrange
        let server = try await fixture.addServer()
        if withJob { _ = try await fixture.addJob(to: server) }
        let before = try fixture.auditEvents()
        var draft = server.draft
        draft.connection = nil

        // Act
        let answer = try await fixture.sendConfirmed(.put, HiveEndpoint.server(server.id), json: draft)

        // Assert
        #expect(answer.status == .unprocessableContent)
        #expect(try answer.problems == Self.connectionMissing)
        #expect(try fixture.servers.server(id: server.id) == server)
        #expect(try fixture.auditEvents() == before)
    }

    @Test("Without SSH details, scanning, testing and making a key refuse, and Hive connects to nothing")
    func refusesToConnect() async throws {
        // Arrange
        let server = try await fixture.addServer(Self.nameOnly)
        let before = try fixture.auditEvents()

        // Act
        let scan = try await fixture.send(.post, HiveEndpoint.hostKeyScan(onServer: server.id))
        let test = try await fixture.send(.post, HiveEndpoint.connectionTest(onServer: server.id))
        let newKey = try await fixture.sendConfirmed(.post, HiveEndpoint.sshKey(onServer: server.id))
        let key = try await fixture.send(.get, HiveEndpoint.sshKey(onServer: server.id))

        // Assert
        #expect(try scan.decoded(as: HostKeyScanResult.self) == .failed(reason: .noSSHDetails))
        #expect(try test.decoded(as: ConnectionTestResult.self).failure == .noSSHDetails)
        #expect(newKey.status == .unprocessableContent)
        #expect(try newKey.problems == Self.connectionMissing)
        #expect(key.status == .notFound)
        #expect(fixture.ssh.scanned.isEmpty)
        #expect(fixture.ssh.ran.isEmpty)
        #expect(try fixture.servers.server(id: server.id) == server)
        #expect(try fixture.auditEvents() == before)
    }
}
