import CryptoKit
import Foundation
@testable import HiveCore
import Testing
import X509

struct IdentityCertificateStoreTests {
    private let temporary: TemporaryDirectory
    private let store: IdentityCertificateStore
    private let key = P256.Signing.PrivateKey()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        temporary = try TemporaryDirectory()
        store = IdentityCertificateStore(directory: temporary.url)
    }

    @Test("The first start issues a self-signed certificate for the identity key, valid for 10 years")
    func issuesCertificate() throws {
        // Act
        let certificate = try store.loadOrIssue(for: key, at: start)

        // Assert
        #expect(certificate.publicKey == Certificate.PublicKey(key.publicKey))
        #expect(certificate.issuer == certificate.subject)
        #expect(certificate.publicKey.isValidSignature(certificate.signature, for: certificate))
        #expect(certificate.notValidBefore == start)
        #expect(certificate.notValidAfter == start.addingTimeInterval(3652 * 24 * 60 * 60))
        #expect(try permissions(of: temporary.path(IdentityCertificateStore.fileName)) == 0o600)
    }

    @Test("A later start loads the saved certificate")
    func loadsSavedCertificate() throws {
        // Arrange
        let issued = try store.loadOrIssue(for: key, at: start)

        // Act
        let loaded = try store.loadOrIssue(for: key, at: start.addingTimeInterval(30 * 24 * 60 * 60))

        // Assert
        #expect(loaded == issued)
    }

    @Test("A certificate for another key is replaced with one for the identity key")
    func reissuesForAnotherKey() throws {
        // Arrange
        let other = P256.Signing.PrivateKey()
        _ = try store.loadOrIssue(for: other, at: start)

        // Act
        let certificate = try store.loadOrIssue(for: key, at: start)

        // Assert
        #expect(certificate.publicKey == Certificate.PublicKey(key.publicKey))
        #expect(try store.loadOrIssue(for: key, at: start) == certificate)
    }

    @Test("A certificate with less than a year left is reissued for the same key")
    func reissuesNearExpiry() throws {
        // Arrange
        let issued = try store.loadOrIssue(for: key, at: start)
        let nineAndAHalfYears = start.addingTimeInterval(3470 * 24 * 60 * 60)

        // Act
        let reissued = try store.loadOrIssue(for: key, at: nineAndAHalfYears)

        // Assert
        #expect(reissued.serialNumber != issued.serialNumber)
        #expect(reissued.publicKey == issued.publicKey)
        #expect(reissued.notValidBefore == nineAndAHalfYears)
    }

    @Test("An unreadable certificate is reissued")
    func reissuesUnreadable() throws {
        // Arrange
        let path = temporary.path(IdentityCertificateStore.fileName)
        let created = FileManager.default.createFile(
            atPath: path,
            contents: Data("not a certificate".utf8),
            attributes: [.posixPermissions: 0o600]
        )
        #expect(created)

        // Act
        let certificate = try store.loadOrIssue(for: key, at: start)

        // Assert
        #expect(certificate.publicKey == Certificate.PublicKey(key.publicKey))
    }

    @Test("A certificate file others can change is refused, never trusted or replaced")
    func refusesUnprotectedFile() throws {
        // Arrange
        _ = try store.loadOrIssue(for: key, at: start)
        let path = temporary.path(IdentityCertificateStore.fileName)
        chmod(path, 0o666)

        // Act, Assert
        #expect(throws: OwnerOnlyFileError.notProtected) { try store.loadOrIssue(for: key, at: start) }
    }
}
