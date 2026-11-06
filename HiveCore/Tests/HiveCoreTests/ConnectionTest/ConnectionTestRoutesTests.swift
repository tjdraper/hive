import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

struct ConnectionTestRoutesTests {
    private let fixture: APIFixture

    init() throws {
        fixture = try APIFixture()
    }

    private func test(_ server: Server) async throws -> ConnectionTestResult {
        try await fixture.send(.post, HiveEndpoint.connectionTest(onServer: server.id)).decoded(as: ConnectionTestResult.self)
    }

    @Test("Without a confirmed host key, Hive doesn't try to connect")
    func needsConfirmedHostKey() async throws {
        // Arrange
        let server = try await fixture.addServer()

        // Act
        let result = try await test(server)

        // Assert
        #expect(result.failure == .noConfirmedHostKey)
        #expect(fixture.ssh.ran.isEmpty)
    }

    @Test("Without a key of Hive's, Hive doesn't try to connect")
    func needsSSHKey() async throws {
        // Arrange
        let server = try await fixture.addServer()
        try await fixture.confirmHostKey(of: server)
        try await fixture.signIn.database.writer.write { database in
            try database.execute(sql: "UPDATE server SET sealedSSHKey = NULL, sshPublicKey = NULL WHERE id = ?", arguments: [server.id])
        }

        // Act
        let result = try await test(server)

        // Assert
        #expect(result.failure == .noSSHKey)
        #expect(fixture.ssh.ran.isEmpty)
    }

    @Test("A test connects with the server's own key and confirmed host key, and runs a command that changes nothing")
    func connects() async throws {
        // Arrange
        let server = try await fixture.addServer()
        try await fixture.confirmHostKey(of: server)

        // Act
        let result = try await test(server)

        // Assert
        #expect(result.failure == nil)
        let ran = try #require(fixture.ssh.ran.first)
        #expect(fixture.ssh.ran.count == 1)
        #expect(ran.command == "true")
        #expect(ran.target.serverID == server.id)
        #expect(ran.target.connection == server.connection)
        #expect(ran.target.hostKey == ConfigurationSamples.hostKey)
        #expect(ran.target.key.publicKey.fingerprint == server.sshKeyFingerprint)
    }

    @Test("A changed host key is reported as one")
    func changedHostKey() async throws {
        // Arrange
        let server = try await fixture.addServer()
        try await fixture.confirmHostKey(of: server)
        fixture.ssh.setResult(status: 255, standardError: SSHFailureReaderTests.changedKey)

        // Act
        let result = try await test(server)

        // Assert
        #expect(result.failure == .hostKeyChanged)
    }

    @Test("A refused login is reported as one")
    func refusedLogin() async throws {
        // Arrange
        let server = try await fixture.addServer()
        try await fixture.confirmHostKey(of: server)
        fixture.ssh.setResult(status: 255, standardError: "root@web.example.com: Permission denied (publickey).\r\n")

        // Act
        let result = try await test(server)

        // Assert
        #expect(result.failure == .loginRefused)
    }

    @Test("An unknown server is not found")
    func unknownServer() async throws {
        // Act
        let answer = try await fixture.send(.post, HiveEndpoint.connectionTest(onServer: UUID()))

        // Assert
        #expect(answer.status == .notFound)
    }
}
