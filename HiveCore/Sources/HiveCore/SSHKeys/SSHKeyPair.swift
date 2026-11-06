import CryptoKit
import Foundation

/// Hive's Ed25519 key for one server. Only its 32-byte seed is stored, sealed (§7). The private key
/// file `ssh-add` reads is made from it in memory each time and never written to disk.
struct SSHKeyPair: Sendable {
    private static let keyType = "ssh-ed25519"
    /// OpenSSH pads the private section of an unencrypted key to this.
    private static let blockSize = 8
    private static let base64LineLength = 70

    let privateKey: Curve25519.Signing.PrivateKey

    init() {
        privateKey = Curve25519.Signing.PrivateKey()
    }

    init(seed: Data) throws {
        privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    }

    var seed: Data {
        privateKey.rawRepresentation
    }

    var publicKey: OpenSSHPublicKey {
        let blob = SSHWireFormat.string(Self.keyType) + SSHWireFormat.string(privateKey.publicKey.rawRepresentation)
        return OpenSSHPublicKey(keyType: Self.keyType, blob: blob)
    }

    /// The key in OpenSSH's own format, unencrypted
    /// (https://github.com/openssh/openssh-portable/blob/master/PROTOCOL.key).
    func privateKeyFile(comment: String) -> Data {
        let publicBytes = privateKey.publicKey.rawRepresentation
        let check = UInt32.random(in: .min ... .max)
        var privateSection = SSHWireFormat.uint32(check) + SSHWireFormat.uint32(check)
        privateSection += SSHWireFormat.string(Self.keyType)
        privateSection += SSHWireFormat.string(publicBytes)
        privateSection += SSHWireFormat.string(seed + publicBytes)
        privateSection += SSHWireFormat.string(comment)
        var padding: UInt8 = 1
        while privateSection.count % Self.blockSize != 0 {
            privateSection.append(padding)
            padding += 1
        }

        var body = Data("openssh-key-v1\0".utf8)
        body += SSHWireFormat.string("none")
        body += SSHWireFormat.string("none")
        body += SSHWireFormat.string(Data())
        body += SSHWireFormat.uint32(1)
        body += SSHWireFormat.string(publicKey.blob)
        body += SSHWireFormat.string(privateSection)

        let encoded = body.base64EncodedString()
        var lines: [Substring] = []
        var rest = encoded[...]
        while !rest.isEmpty {
            lines.append(rest.prefix(Self.base64LineLength))
            rest = rest.dropFirst(Self.base64LineLength)
        }
        let text = "-----BEGIN OPENSSH PRIVATE KEY-----\n" + lines.joined(separator: "\n") + "\n-----END OPENSSH PRIVATE KEY-----\n"
        return Data(text.utf8)
    }
}
