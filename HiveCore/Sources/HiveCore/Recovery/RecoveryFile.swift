import CryptoKit
import Foundation

public enum RecoveryFileError: Error, Equatable {
    case notARecoveryFile
    case unsupportedVersion(UInt8)
    /// Written for another recovery key, such as one replaced since.
    case otherKey
    /// Altered or cut short. Deliberately says nothing about which.
    case couldNotOpen
    case unsupportedContents(format: Int)
}

/// A recovery file (§14): `RecoveryContents` encrypted to the recovery key with HPKE (RFC 9180). Hive
/// holds only the key's public half, so it can write these files but never open one it wrote.
///
/// Laid out as a magic string, a version byte, the recovery key's public half, HPKE's encapsulated key,
/// then the ciphertext and tag. Everything before the ciphertext is authenticated with it. The public
/// half lets a restore tell a file written for another key from one that was altered.
enum RecoveryFile {
    static let fileExtension = "hiverecovery"
    static let magic = Data("Hive recovery file".utf8)
    static let version1: UInt8 = 1
    static let ciphersuite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly
    static let info = Data("Hive recovery file v1".utf8)
    static let keyLength = 32

    private static var headerLength: Int {
        magic.count + 1 + keyLength + keyLength
    }

    static func seal(_ contents: RecoveryContents, to recoveryKey: Curve25519.KeyAgreement.PublicKey) throws -> Data {
        var sender = try HPKE.Sender(recipientKey: recoveryKey, ciphersuite: ciphersuite, info: info)
        let header = magic + [version1] + recoveryKey.rawRepresentation + sender.encapsulatedKey
        return header + (try sender.seal(contents.encoded(), authenticating: header))
    }

    static func open(_ file: Data, with recoveryKey: Curve25519.KeyAgreement.PrivateKey) throws -> RecoveryContents {
        let bytes = Data(file)
        guard bytes.starts(with: magic), bytes.count > magic.count else { throw RecoveryFileError.notARecoveryFile }
        let version = bytes[magic.count]
        guard version == version1 else { throw RecoveryFileError.unsupportedVersion(version) }
        guard bytes.count > headerLength else { throw RecoveryFileError.couldNotOpen }

        let keyStart = magic.count + 1
        let writtenFor = bytes[keyStart ..< keyStart + keyLength]
        guard writtenFor == recoveryKey.publicKey.rawRepresentation else { throw RecoveryFileError.otherKey }
        let encapsulatedKey = bytes[keyStart + keyLength ..< headerLength]
        let header = bytes.prefix(headerLength)

        let plaintext: Data
        do {
            var recipient = try HPKE.Recipient(
                privateKey: recoveryKey,
                ciphersuite: ciphersuite,
                info: info,
                encapsulatedKey: Data(encapsulatedKey)
            )
            plaintext = try recipient.open(Data(bytes.dropFirst(headerLength)), authenticating: Data(header))
        } catch {
            throw RecoveryFileError.couldNotOpen
        }

        let format = try JSONDecoder().decode(FormatOnly.self, from: plaintext).format
        guard format == RecoveryContents.currentFormat else { throw RecoveryFileError.unsupportedContents(format: format) }
        return try RecoveryContents.decoded(from: plaintext)
    }

    private struct FormatOnly: Decodable {
        let format: Int
    }
}
