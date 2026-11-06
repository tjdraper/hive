import CryptoKit
import Foundation

/// What a device keeps of a Hive's identity: the SHA-256 hash of its identity key's X9.63 form. It names
/// the key, not the certificate, so Hive can reissue its certificate without unpairing anyone.
public struct PublicKeyPin: Hashable, Codable, Sendable {
    public let sha256: Data

    public init(sha256: Data) {
        self.sha256 = sha256
    }

    public init(publicKey: P256.Signing.PublicKey) {
        sha256 = Data(SHA256.hash(data: publicKey.x963Representation))
    }
}
