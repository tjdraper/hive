import CryptoKit
import Foundation
import Security
import X509

/// The key TLS identifies Hive with. Its public key's hash is what every paired device pins.
public protocol IdentitySigningKey: Sendable {
    var publicKey: P256.Signing.PublicKey { get }
    /// The same key, in the form swift-certificates signs Hive's certificate with.
    var certificateIssuer: Certificate.PrivateKey { get }

    func signature<D: DataProtocol>(for data: D) throws -> P256.Signing.ECDSASignature
}

extension SecureEnclave.P256.Signing.PrivateKey: IdentitySigningKey {
    public var certificateIssuer: Certificate.PrivateKey {
        Certificate.PrivateKey(self)
    }
}

/// A new key, with the saved form that recreates it.
public struct CreatedKey<Key: Sendable>: Sendable {
    public let key: Key
    public let savedForm: Data

    public init(key: Key, savedForm: Data) {
        self.key = key
        self.savedForm = savedForm
    }
}

public protocol HiveKeyFactory: Sendable {
    func makeIdentityKey() throws -> CreatedKey<any IdentitySigningKey>
    func identityKey(from savedForm: Data) throws -> any IdentitySigningKey
    func makeStorageKey() throws -> CreatedKey<any SecretStorageKey>
    func storageKey(from savedForm: Data) throws -> any SecretStorageKey
}

public enum SecureEnclaveKeyError: Error, Equatable {
    case unavailable
    case couldNotSetAccessControl
}

/// Keys whose saved form, CryptoKit's `dataRepresentation`, only this Mac's Secure Enclave can use.
public struct SecureEnclaveKeyFactory: HiveKeyFactory {
    public init() {}

    public func makeIdentityKey() throws -> CreatedKey<any IdentitySigningKey> {
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: try accessControl())
        return CreatedKey(key: key, savedForm: key.dataRepresentation)
    }

    public func identityKey(from savedForm: Data) throws -> any IdentitySigningKey {
        try checkAvailable()
        return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: savedForm)
    }

    public func makeStorageKey() throws -> CreatedKey<any SecretStorageKey> {
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: try accessControl())
        return CreatedKey(key: key, savedForm: key.dataRepresentation)
    }

    public func storageKey(from savedForm: Data) throws -> any SecretStorageKey {
        try checkAvailable()
        return try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: savedForm)
    }

    /// Hive starts at boot with nobody logged in, so its keys can't require an unlocked login session,
    /// and it uses them unattended, so they can't ask for a password or Touch ID.
    private func accessControl() throws -> SecAccessControl {
        try checkAvailable()
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            .privateKeyUsage,
            nil
        ) else {
            throw SecureEnclaveKeyError.couldNotSetAccessControl
        }
        return accessControl
    }

    private func checkAvailable() throws {
        guard SecureEnclave.isAvailable else { throw SecureEnclaveKeyError.unavailable }
    }
}
