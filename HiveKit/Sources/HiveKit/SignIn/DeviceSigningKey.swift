import CryptoKit
import Foundation

/// The key a device signs in to one Hive with. Beekeeper's lives in the Secure Enclave.
public protocol DeviceSigningKey: Sendable {
    var publicKey: P256.Signing.PublicKey { get }

    func signature<D: DataProtocol>(for data: D) throws -> P256.Signing.ECDSASignature
}

extension SecureEnclave.P256.Signing.PrivateKey: DeviceSigningKey {}
