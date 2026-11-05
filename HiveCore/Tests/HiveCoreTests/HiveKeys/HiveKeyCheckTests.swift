import CryptoKit
import Darwin
import Foundation
@testable import HiveCore
import Testing

struct HiveKeyCheckTests {
    private let temporary: TemporaryDirectory
    private let store: HiveKeyStore
    private let check: HiveKeyCheck

    init() throws {
        temporary = try TemporaryDirectory()
        store = HiveKeyStore(directory: temporary.url, factory: SoftwareKeyFactory(), owner: getuid())
        check = HiveKeyCheck(directory: temporary.url, owner: getuid())
    }

    @Test("A secret sealed on one start opens on the next")
    func opensAcrossStarts() throws {
        // Arrange
        try check.run(try store.loadOrCreate())
        let sealed = FileManager.default.contents(atPath: temporary.path("key-check.sealed"))

        // Act
        try check.run(try store.loadOrCreate())

        // Assert
        #expect(sealed != nil)
        #expect(FileManager.default.contents(atPath: temporary.path("key-check.sealed")) == sealed)
        #expect(try permissions(of: temporary.path("key-check.sealed")) == 0o600)
    }

    @Test("Fails when the secret from an earlier start won't open with the saved storage key")
    func failsWithChangedStorageKey() throws {
        // Arrange
        try check.run(try store.loadOrCreate())
        let otherStorageKey = P256.KeyAgreement.PrivateKey()
        try FileManager.default.removeItem(atPath: temporary.path("storage.key"))
        FileManager.default.createFile(
            atPath: temporary.path("storage.key"),
            contents: otherStorageKey.rawRepresentation,
            attributes: [.posixPermissions: 0o600]
        )

        // Act / Assert
        #expect(throws: HiveKeyCheckError.earlierSecretUnreadable) { try check.run(try store.loadOrCreate()) }
    }

    @Test("Seals a new secret when the storage key was just created")
    func resealsForNewStorageKey() throws {
        // Arrange
        try check.run(try store.loadOrCreate())
        let sealed = FileManager.default.contents(atPath: temporary.path("key-check.sealed"))
        try FileManager.default.removeItem(atPath: temporary.path("storage.key"))

        // Act
        try check.run(try store.loadOrCreate())

        // Assert
        #expect(FileManager.default.contents(atPath: temporary.path("key-check.sealed")) != sealed)
        try check.run(try store.loadOrCreate())
    }

    @Test("Fails when the identity key's signatures don't verify")
    func failsWithBrokenIdentityKey() throws {
        // Arrange
        let keys = try store.loadOrCreate()
        let broken = HiveKeys(identity: MismatchedIdentityKey(), storage: keys.storage, created: [])

        // Act / Assert
        #expect(throws: HiveKeyCheckError.identityKeyCouldNotSign) { try check.run(broken) }
    }
}

private struct MismatchedIdentityKey: IdentitySigningKey {
    let publicKey = P256.Signing.PrivateKey().publicKey

    func signature<D: DataProtocol>(for data: D) throws -> P256.Signing.ECDSASignature {
        try P256.Signing.PrivateKey().signature(for: data)
    }
}
