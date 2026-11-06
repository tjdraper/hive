import CryptoKit
import Foundation
import HiveKit

/// A public key as OpenSSH writes it on one line: its type, then its blob in base64.
struct OpenSSHPublicKey: Hashable, Sendable {
    /// The kinds of host key Hive records, most preferred first.
    static let hostKeyTypes = ["ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521", "ssh-rsa"]

    let keyType: String
    let blob: Data

    init(keyType: String, blob: Data) {
        self.keyType = keyType
        self.blob = blob
    }

    /// Reads `<type> <base64>`, with or without a comment after it. Refuses a blob whose own type
    /// differs from the one written before it, which a tampered line could have.
    init?(line: String) {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2,
              let blob = Data(base64Encoded: String(fields[1])),
              SSHWireFormat.firstString(in: blob) == String(fields[0])
        else { return nil }
        keyType = String(fields[0])
        self.blob = blob
    }

    var line: String {
        "\(keyType) \(blob.base64EncodedString())"
    }

    /// As `ssh-keygen -l` and `ssh` show it.
    var fingerprint: String {
        let digest = Data(SHA256.hash(data: blob)).base64EncodedString()
        return "SHA256:" + digest.trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    var hostKeyFingerprint: HostKeyFingerprint {
        HostKeyFingerprint(keyType: keyType, fingerprint: fingerprint)
    }
}
