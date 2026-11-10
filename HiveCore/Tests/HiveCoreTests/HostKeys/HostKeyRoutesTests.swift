import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

struct HostKeyRoutesTests {
    private let fixture: APIFixture

    init() throws {
        fixture = try APIFixture()
    }

    private func scan(_ server: Server, finding key: OpenSSHPublicKey = ConfigurationSamples.hostKey) async throws -> APIAnswer {
        fixture.ssh.setScan(.found(key))
        return try await fixture.send(.post, HiveEndpoint.hostKeyScan(onServer: server.id))
    }

    private func confirm(
        _ server: Server,
        fingerprint: String = ConfigurationSamples.hostKey.fingerprint,
        confirmed: Bool = false
    ) async throws -> APIAnswer {
        let confirmation = HostKeyConfirmation(fingerprint: fingerprint)
        let path = HiveEndpoint.hostKey(onServer: server.id)
        return try await confirmed ? fixture.sendConfirmed(.put, path, json: confirmation) : fixture.send(.put, path, json: confirmation)
    }

    private func storedHostKey(of server: Server) throws -> String? {
        try fixture.signIn.database.writer.read { try ServerRecord.fetchOne($0, key: server.id) }?.hostKey
    }

    @Test("Scanning answers with the key's fingerprint and records nothing")
    func scanRecordsNothing() async throws {
        // Arrange
        let server = try await fixture.addServer()
        let entries = try fixture.auditEvents().count

        // Act
        let answer = try await scan(server)

        // Assert
        #expect(answer.status == .ok)
        #expect(try answer.decoded(as: HostKeyScanResult.self) == .found(key: ConfigurationSamples.hostKey.hostKeyFingerprint))
        #expect(fixture.ssh.scanned == [server.connection])
        #expect(try storedHostKey(of: server) == nil)
        #expect(try fixture.servers.server(id: server.id)?.confirmedHostKey == nil)
        #expect(try fixture.auditEvents().count == entries)
    }

    @Test("Confirming the scanned fingerprint records the key, with an audit entry")
    func confirmRecords() async throws {
        // Arrange
        let server = try await fixture.addServer()
        _ = try await scan(server)

        // Act
        let answer = try await confirm(server)

        // Assert
        #expect(answer.status == .ok)
        #expect(try answer.decoded(as: Server.self).confirmedHostKey == ConfigurationSamples.hostKey.hostKeyFingerprint)
        #expect(try storedHostKey(of: server) == ConfigurationSamples.hostKey.line)
        #expect(try fixture.auditEvents().first == .server(
            serverID: server.id,
            serverName: server.name,
            change: .hostKeyConfirmed(old: nil, new: ConfigurationSamples.hostKey.hostKeyFingerprint)
        ))
    }

    @Test("A confirmation without a scan is refused, and records nothing")
    func confirmWithoutScan() async throws {
        // Arrange
        let server = try await fixture.addServer()

        // Act
        let answer = try await confirm(server)

        // Assert
        #expect(answer.status == .conflict)
        #expect(try answer.decoded(as: HostKeyConfirmationRefusal.self).reason == .noScan)
        #expect(try storedHostKey(of: server) == nil)
    }

    @Test("A fingerprint other than the scanned one is refused, and records nothing")
    func confirmWrongFingerprint() async throws {
        // Arrange
        let server = try await fixture.addServer()
        _ = try await scan(server)

        // Act
        let answer = try await confirm(server, fingerprint: SSHKeyPair().publicKey.fingerprint)

        // Assert
        #expect(answer.status == .conflict)
        #expect(try answer.decoded(as: HostKeyConfirmationRefusal.self).reason == .fingerprintMismatch)
        #expect(try storedHostKey(of: server) == nil)
    }

    @Test("A scan made before the server's connection changed can't be confirmed")
    func confirmAfterConnectionChange() async throws {
        // Arrange
        let server = try await fixture.addServer()
        _ = try await scan(server)
        var draft = server.draft
        draft.connection.host = "elsewhere.example.com"
        _ = try await fixture.sendConfirmed(.put, HiveEndpoint.server(server.id), json: draft)

        // Act
        let answer = try await confirm(server)

        // Assert
        #expect(answer.status == .conflict)
        #expect(try answer.decoded(as: HostKeyConfirmationRefusal.self).reason == .noScan)
        #expect(try storedHostKey(of: server) == nil)
    }

    @Test("A scan too old to confirm is refused")
    func confirmExpiredScan() async throws {
        // Arrange
        let server = try await fixture.addServer()
        _ = try await scan(server)
        fixture.signIn.clock.advance(by: PendingHostKeyScans.lifetime + 1)

        // Act
        let answer = try await confirm(server)

        // Assert
        #expect(answer.status == .conflict)
        #expect(try storedHostKey(of: server) == nil)
    }

    @Test("A scan is confirmed once, and a second confirmation needs a new scan")
    func scanUsedOnce() async throws {
        // Arrange
        let server = try await fixture.addServer()
        _ = try await scan(server)
        _ = try await confirm(server)

        // Act
        let again = try await confirm(server)

        // Assert
        #expect(again.status == .conflict)
    }

    @Test("Confirming a new key replaces the old one, recording both fingerprints")
    func replacesKey() async throws {
        // Arrange
        let server = try await fixture.addServer()
        try await fixture.confirmHostKey(of: server)
        let newKey = SSHKeyPair().publicKey
        _ = try await scan(server, finding: newKey)

        // Act
        let answer = try await confirm(server, fingerprint: newKey.fingerprint, confirmed: true)

        // Assert
        #expect(answer.status == .ok)
        #expect(try storedHostKey(of: server) == newKey.line)
        #expect(try fixture.auditEvents().first == .server(
            serverID: server.id,
            serverName: server.name,
            change: .hostKeyConfirmed(old: ConfigurationSamples.hostKey.hostKeyFingerprint, new: newKey.hostKeyFingerprint)
        ))
    }

    @Test("A new key that's scanned but not confirmed is never used to connect")
    func unconfirmedKeyNeverUsed() async throws {
        // Arrange
        let server = try await fixture.addServer()
        try await fixture.confirmHostKey(of: server)
        _ = try await scan(server, finding: SSHKeyPair().publicKey)

        // Act
        _ = try await fixture.send(.post, HiveEndpoint.connectionTest(onServer: server.id))

        // Assert
        let target = try #require(fixture.ssh.ran.first?.target)
        #expect(target.hostKey == ConfigurationSamples.hostKey)
        #expect(KnownHostsFile.contents(for: target).contains(ConfigurationSamples.hostKey.line))
    }

    @Test("A failed scan answers why, and records nothing")
    func failedScan() async throws {
        // Arrange
        let server = try await fixture.addServer()
        fixture.ssh.setScan(.failed(.unreachable))

        // Act
        let answer = try await fixture.send(.post, HiveEndpoint.hostKeyScan(onServer: server.id))
        let confirmation = try await confirm(server)

        // Assert
        #expect(try answer.decoded(as: HostKeyScanResult.self) == .failed(reason: .unreachable))
        #expect(confirmation.status == .conflict)
    }

    @Test("An unknown server is not found")
    func unknownServer() async throws {
        // Act
        let scanned = try await fixture.send(.post, HiveEndpoint.hostKeyScan(onServer: UUID()))
        let confirmed = try await fixture.send(
            .put,
            HiveEndpoint.hostKey(onServer: UUID()),
            json: HostKeyConfirmation(fingerprint: ConfigurationSamples.hostKey.fingerprint)
        )

        // Assert
        #expect(scanned.status == .notFound)
        #expect(confirmed.status == .notFound)
        #expect(fixture.ssh.scanned.isEmpty)
    }
}
