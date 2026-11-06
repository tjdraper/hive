import CryptoKit
import Foundation
import NIOCore
import NIOSSL
import os

enum IdentityTLSKeyError: Error {
    case unsupportedAlgorithm
    case decryptionUnsupported
}

/// Hands TLS signing to the identity key, so its private half never leaves the Secure Enclave.
struct IdentityTLSKey: NIOSSLCustomPrivateKey, Hashable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "TLSIdentity")

    let key: any IdentitySigningKey

    var signatureAlgorithms: [SignatureAlgorithm] {
        [.ecdsaSecp256R1Sha256]
    }

    func sign(channel: any Channel, algorithm: SignatureAlgorithm, data: ByteBuffer) -> EventLoopFuture<ByteBuffer> {
        channel.eventLoop.makeCompletedFuture {
            guard algorithm == .ecdsaSecp256R1Sha256 else { throw IdentityTLSKeyError.unsupportedAlgorithm }
            do {
                let signature = try key.signature(for: Data(data.readableBytesView))
                return ByteBuffer(bytes: signature.derRepresentation)
            } catch {
                Self.logger.error("The identity key couldn't sign a handshake: \(String(describing: error), privacy: .public)")
                throw error
            }
        }
    }

    /// Only RSA key exchange decrypts, and TLS 1.3 has none.
    func decrypt(channel: any Channel, data _: ByteBuffer) -> EventLoopFuture<ByteBuffer> {
        channel.eventLoop.makeFailedFuture(IdentityTLSKeyError.decryptionUnsupported)
    }

    static func == (lhs: IdentityTLSKey, rhs: IdentityTLSKey) -> Bool {
        lhs.key.publicKey.x963Representation == rhs.key.publicKey.x963Representation
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key.publicKey.x963Representation)
    }
}
