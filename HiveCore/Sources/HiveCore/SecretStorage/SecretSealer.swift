import CryptoKit
import Foundation

/// A secret as it's stored: unreadable without the storage key it was sealed for.
public struct SealedSecret: Equatable, Sendable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }
}

public enum SecretSealingError: Error, Equatable {
    case unsupportedVersion(UInt8)
    case malformed
    /// Altered, or sealed for another storage key. Deliberately says nothing about which.
    case couldNotOpen
}

/// Seals each secret on its own with HPKE (RFC 9180): a temporary key, ECDH with the storage key,
/// HKDF, then AES-GCM.
///
/// Stored as a version byte, the temporary public key, then the ciphertext and tag. The version
/// leaves room to change the scheme while secrets sealed under an older one still open.
public struct SecretSealer: Sendable {
    static let version1: UInt8 = 1
    static let ciphersuite = HPKE.Ciphersuite.P256_SHA256_AES_GCM_256
    static let info = Data("Hive secret v1".utf8)
    /// An uncompressed P-256 point.
    static let encapsulatedKeyLength = 65

    let key: any SecretStorageKey

    public init(key: any SecretStorageKey) {
        self.key = key
    }

    public func seal(_ secret: Data) throws -> SealedSecret {
        var sender = try HPKE.Sender(recipientKey: key.publicKey, ciphersuite: Self.ciphersuite, info: Self.info)
        let header = Data([Self.version1]) + sender.encapsulatedKey
        let ciphertext = try sender.seal(secret, authenticating: header)
        return SealedSecret(data: header + ciphertext)
    }

    public func open(_ sealed: SealedSecret) throws -> Data {
        let bytes = sealed.data
        guard let version = bytes.first else { throw SecretSealingError.malformed }
        guard version == Self.version1 else { throw SecretSealingError.unsupportedVersion(version) }

        let headerLength = 1 + Self.encapsulatedKeyLength
        guard bytes.count > headerLength else { throw SecretSealingError.malformed }
        let header = bytes.prefix(headerLength)
        let encapsulatedKey = header.dropFirst()
        let ciphertext = bytes.dropFirst(headerLength)

        do {
            var recipient = try key.recipient(
                ciphersuite: Self.ciphersuite,
                info: Self.info,
                encapsulatedKey: Data(encapsulatedKey)
            )
            return try recipient.open(Data(ciphertext), authenticating: Data(header))
        } catch {
            throw SecretSealingError.couldNotOpen
        }
    }
}
