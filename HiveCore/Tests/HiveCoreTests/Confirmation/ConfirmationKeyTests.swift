import CryptoKit
import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird
import Testing

struct ConfirmationKeyTests {
    private let fixture: APIFixture
    private let newKey = P256.Signing.PrivateKey()

    init() async throws {
        fixture = try APIFixture()
        try await fixture.signIn.database.writer.write { database in
            try database.execute(sql: "UPDATE device SET confirmationPublicKey = NULL")
        }
    }

    private var body: Data {
        get throws { try JSONEncoder().encode(ConfirmationKeyRegistration(publicKey: newKey.publicKey.x963Representation)) }
    }

    /// Signed by the device's sign-in key unless `key` is given.
    private func register(key: P256.Signing.PrivateKey? = nil, body: Data? = nil) async throws -> APIAnswer {
        let body = try body ?? self.body
        let confirmation = try fixture.confirmation(.put, HiveEndpoint.confirmationKey, body: body, key: key ?? fixture.signIn.deviceKey)
        return try await fixture.send(.put, HiveEndpoint.confirmationKey, body: body, confirmation: confirmation)
    }

    private func storedKey() throws -> Data? {
        try ConfirmationKeyStore(database: fixture.signIn.database).key(ofDevice: fixture.signIn.device.id)
    }

    @Test("A device registers its confirmation key with its sign-in key, recorded in the audit log")
    func registers() async throws {
        // Act
        let answer = try await register()

        // Assert
        #expect(answer.status == .noContent)
        #expect(try storedKey() == newKey.publicKey.x963Representation)
        #expect(try fixture.auditEvents().first == .confirmationKeyRegistered)
    }

    @Test("A session alone, or a signature by the key being registered, can't register one")
    func refusesWithoutSignInKey() async throws {
        // Act
        let unsigned = try await fixture.send(.put, HiveEndpoint.confirmationKey, body: body)
        let selfSigned = try await register(key: newKey)

        // Assert
        #expect(unsigned.status == .forbidden)
        #expect(selfSigned.status == .forbidden)
        #expect(try selfSigned.confirmationRefusal == .badSignature)
        #expect(try storedKey() == nil)
    }

    @Test("Registering the same key again changes nothing, and another key is refused")
    func refusesReplacement() async throws {
        // Arrange
        _ = try await register()
        let before = try fixture.auditEvents()
        let other = try JSONEncoder().encode(ConfirmationKeyRegistration(publicKey: P256.Signing.PrivateKey().publicKey.x963Representation))

        // Act
        let same = try await register()
        let replacing = try await register(body: other)

        // Assert
        #expect(same.status == .noContent)
        #expect(replacing.status == .forbidden)
        #expect(try replacing.confirmationRefusal == .keyAlreadyRegistered)
        #expect(try storedKey() == newKey.publicKey.x963Representation)
        #expect(try fixture.auditEvents() == before)
    }

    @Test("A registration that isn't a P-256 key is refused")
    func refusesBadKey() async throws {
        // Act
        let answer = try await register(body: JSONEncoder().encode(ConfirmationKeyRegistration(publicKey: Data([4, 1, 2]))))

        // Assert
        #expect(answer.status == .badRequest)
        #expect(try storedKey() == nil)
    }

    @Test("Revoking a device takes its confirmation key with it")
    func revokingRemovesKey() async throws {
        // Arrange
        _ = try await register()

        // Act
        try await fixture.signIn.database.writer.write { try $0.execute(sql: "DELETE FROM device") }

        // Assert
        #expect(try storedKey() == nil)
    }
}
