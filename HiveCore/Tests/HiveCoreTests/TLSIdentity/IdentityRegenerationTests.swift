import CryptoKit
import Foundation
@testable import HiveCore
import HiveKit
import Hummingbird
import HummingbirdTesting
import Testing

struct IdentityRegenerationTests {
    private let fixture: APIFixture

    init() throws {
        fixture = try APIFixture()
    }

    private func identityKey() throws -> Data {
        try #require(FileManager.default.contents(atPath: fixture.keyFolder.path(HiveKeyKind.identity.fileName)))
    }

    @Test("A new identity key replaces the old, every device is unpaired and signed out, and Hive restarts")
    func regenerates() async throws {
        // Arrange
        let old = try identityKey()
        let token = try fixture.token()

        // Act
        let answer = try await fixture.sendConfirmed(.post, HiveEndpoint.identityRegeneration)

        // Assert
        #expect(answer.status == .accepted)
        #expect(try identityKey() != old)
        #expect(try permissions(of: fixture.keyFolder.path(HiveKeyKind.identity.fileName)) == 0o600)
        #expect(try fixture.signIn.devices.all().isEmpty)
        #expect(fixture.restart.isRequested)
        let signedOut = try await fixture.application.test(.router) { client in
            try await client.execute(uri: HiveEndpoint.overview, method: .get, headers: fixture.headers(token: token)) { $0.status }
        }
        #expect(signedOut == .unauthorized)
        let entry = try #require(try fixture.auditLog.page(before: nil, limit: 1).entries.first)
        #expect(entry.event == .identityRegenerated)
        #expect(entry.deviceID == fixture.signIn.device.id)
    }

    @Test("The new key is the one Hive loads on its next start")
    func loadsNewKey() async throws {
        // Arrange
        let old = try fixture.identityKeys.loadOrCreate().identity.publicKey

        // Act
        _ = try await fixture.sendConfirmed(.post, HiveEndpoint.identityRegeneration)

        // Assert
        let loaded = try fixture.identityKeys.loadOrCreate()
        #expect(loaded.created.isEmpty)
        #expect(loaded.identity.publicKey.rawRepresentation != old.rawRepresentation)
    }

    @Test("When a new key can't be made, nothing changes")
    func failureChangesNothing() async throws {
        // Arrange
        let refusing = IdentityRegenerationWorkflow(
            keys: HiveKeyStore(directory: fixture.keyFolder.url, factory: SoftwareKeyFactory(refusesToMake: true), owner: getuid()),
            database: fixture.signIn.database,
            sessions: fixture.signIn.sessions,
            restart: fixture.restart,
            now: { Date() }
        )
        let old = try identityKey()

        // Act
        #expect(throws: HiveKeyStoreError.couldNotCreate(.identity)) {
            try refusing.regenerate(isConfirmed: true, by: fixture.signIn.device.id)
        }

        // Assert
        #expect(try identityKey() == old)
        #expect(try fixture.signIn.devices.all().count == 1)
        #expect(!fixture.restart.isRequested)
    }
}
