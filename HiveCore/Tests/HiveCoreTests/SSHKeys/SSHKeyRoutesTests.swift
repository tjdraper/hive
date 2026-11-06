import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

struct SSHKeyRoutesTests {
    private let fixture: APIFixture

    init() throws {
        fixture = try APIFixture()
    }

    private func storedKey(of server: Server) throws -> SSHKeyPair {
        let sealed = try #require(try fixture.signIn.database.writer.read { try ServerRecord.fetchOne($0, key: server.id) }?.sealedSSHKey)
        return try SSHKeyPair(seed: fixture.sealer.open(SealedSecret(data: sealed)))
    }

    @Test("A new server gets its own key, whose public half is shown with lines for authorized_keys")
    func newServerHasKey() async throws {
        // Arrange
        let server = try await fixture.addServer()

        // Act
        let answer = try await fixture.send(.get, HiveEndpoint.sshKey(onServer: server.id))

        // Assert
        let key = try answer.decoded(as: ServerSSHKey.self)
        let stored = try storedKey(of: server).publicKey
        #expect(key.publicKey == stored.line)
        #expect(key.fingerprint == stored.fingerprint)
        #expect(server.sshKeyFingerprint == stored.fingerprint)
        #expect(key.authorizedKeysLine == "restrict \(stored.line) Hive Test Hive")
        #expect(key.restrictedAuthorizedKeysLine == "restrict,from=\"100.64.0.7,192.168.1.20\" \(stored.line) Hive Test Hive")
    }

    @Test("Each server has a key of its own")
    func keysDiffer() async throws {
        // Arrange
        let first = try await fixture.addServer()
        var other = ConfigurationSamples.server
        other.name = "Mail"

        // Act
        let second = try await fixture.addServer(other)

        // Assert
        #expect(first.sshKeyFingerprint != second.sshKeyFingerprint)
    }

    @Test("With no address another machine could see, there's no restricted line")
    func noAddresses() async throws {
        // Arrange
        let server = try await fixture.addServer()
        fixture.addresses.set([])

        // Act
        let key = try await fixture.send(.get, HiveEndpoint.sshKey(onServer: server.id)).decoded(as: ServerSSHKey.self)

        // Assert
        #expect(key.restrictedAuthorizedKeysLine == nil)
    }

    @Test("Making a new key replaces the old one, with an audit entry naming both fingerprints")
    func makesNewKey() async throws {
        // Arrange
        let server = try await fixture.addServer()
        let old = try storedKey(of: server).publicKey

        // Act
        let answer = try await fixture.send(.post, HiveEndpoint.sshKey(onServer: server.id))

        // Assert
        #expect(answer.status == .created)
        let new = try storedKey(of: server).publicKey
        #expect(new != old)
        #expect(try answer.decoded(as: ServerSSHKey.self).publicKey == new.line)
        #expect(try fixture.auditEvents().first == .server(
            serverID: server.id,
            serverName: server.name,
            change: .newSSHKey(old: old.fingerprint, new: new.fingerprint)
        ))
    }

    @Test("The private key is stored sealed, and no answer or table holds it in the clear")
    func privateKeyNeverShown() async throws {
        // Arrange
        let server = try await fixture.addServer()
        var answers = [try await fixture.send(.get, HiveEndpoint.sshKey(onServer: server.id))]
        answers.append(try await fixture.send(.post, HiveEndpoint.sshKey(onServer: server.id)))
        answers.append(try await fixture.send(.get, HiveEndpoint.server(server.id)))
        answers.append(try await fixture.send(.get, HiveEndpoint.auditLog))

        // Act
        let key = try storedKey(of: server)
        let file = key.privateKeyFile(comment: "")

        // Assert
        for answer in answers {
            #expect(answer.body.range(of: key.seed) == nil)
            #expect(answer.body.range(of: Data(key.seed.base64EncodedString().utf8)) == nil)
            #expect(answer.body.range(of: file.prefix(40)) == nil)
        }
        let stored = try await fixture.signIn.database.writer.read { database in
            try Row.fetchAll(database, sql: "SELECT * FROM server").flatMap(\.databaseValues).compactMap { value -> Data? in
                switch value.storage {
                case .blob(let data): data
                case .string(let text): Data(text.utf8)
                default: nil
                }
            }
        }
        for value in stored {
            #expect(value.range(of: key.seed) == nil)
            #expect(value.range(of: Data(key.seed.base64EncodedString().utf8)) == nil)
        }
    }

    @Test("An unknown server is not found, and a server from before keys has none until one is made")
    func missingKeys() async throws {
        // Arrange
        let server = try await fixture.addServer()
        try await fixture.signIn.database.writer.write { database in
            try database.execute(sql: "UPDATE server SET sealedSSHKey = NULL, sshPublicKey = NULL WHERE id = ?", arguments: [server.id])
        }

        // Act
        let unknown = try await fixture.send(.get, HiveEndpoint.sshKey(onServer: UUID()))
        let missing = try await fixture.send(.get, HiveEndpoint.sshKey(onServer: server.id))
        let made = try await fixture.send(.post, HiveEndpoint.sshKey(onServer: server.id))
        let unknownMade = try await fixture.send(.post, HiveEndpoint.sshKey(onServer: UUID()))

        // Assert
        #expect(unknown.status == .notFound)
        #expect(missing.status == .notFound)
        #expect(made.status == .created)
        #expect(unknownMade.status == .notFound)
        #expect(try fixture.auditEvents().first == .server(
            serverID: server.id,
            serverName: server.name,
            change: .newSSHKey(old: nil, new: try storedKey(of: server).publicKey.fingerprint)
        ))
    }
}
