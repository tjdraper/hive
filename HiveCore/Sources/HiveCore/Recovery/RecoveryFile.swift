import CryptoKit
import Foundation
import HiveKit

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
/// Laid out as `RecoveryFileHeader` (a magic string, a version byte and the recovery key's public
/// half), HPKE's encapsulated key, then the ciphertext and tag. Everything before the ciphertext is
/// authenticated with it. The public half lets a restore tell a file written for another key from one
/// that was altered, and Beekeeper tell a copy made with an older key.
enum RecoveryFile {
    static let ciphersuite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly
    static let info = Data("Hive recovery file v1".utf8)

    private static let magic = RecoveryFileHeader.magic
    private static let keyLength = RecoveryFileHeader.keyLength

    private static var headerLength: Int {
        magic.count + 1 + keyLength + keyLength
    }

    static func seal(_ contents: RecoveryContents, to recoveryKey: Curve25519.KeyAgreement.PublicKey) throws -> Data {
        var sender = try HPKE.Sender(recipientKey: recoveryKey, ciphersuite: ciphersuite, info: info)
        let header = magic + [RecoveryFileHeader.version1] + recoveryKey.rawRepresentation + sender.encapsulatedKey
        return header + (try sender.seal(contents.encoded(), authenticating: header))
    }

    static func open(_ file: Data, with recoveryKey: Curve25519.KeyAgreement.PrivateKey) throws -> RecoveryContents {
        let bytes = Data(file)
        guard bytes.starts(with: magic), bytes.count > magic.count else { throw RecoveryFileError.notARecoveryFile }
        let version = bytes[magic.count]
        guard version == RecoveryFileHeader.version1 else { throw RecoveryFileError.unsupportedVersion(version) }
        guard bytes.count > headerLength, let writtenFor = RecoveryFileHeader.publicKey(of: bytes) else {
            throw RecoveryFileError.couldNotOpen
        }

        guard writtenFor == recoveryKey.publicKey.rawRepresentation else { throw RecoveryFileError.otherKey }
        let encapsulatedKey = bytes[magic.count + 1 + keyLength ..< headerLength]
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
