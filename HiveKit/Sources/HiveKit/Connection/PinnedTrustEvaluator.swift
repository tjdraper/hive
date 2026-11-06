import CryptoKit
import Foundation
import Security

/// Accepts a server whose certificate holds the pinned key, and ignores the chain, hostname and expiry.
/// The TLS handshake has already proved the server holds the private half of that key, so the key is
/// all that needs checking, and Hive is reached at addresses its self-signed certificate can't name.
struct PinnedTrustEvaluator: Sendable {
    let pin: PublicKeyPin

    func accepts(_ trust: SecTrust) -> Bool {
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
              let key = SecCertificateCopyKey(leaf),
              let x963 = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              let publicKey = try? P256.Signing.PublicKey(x963Representation: x963)
        else { return false }
        return PublicKeyPin(publicKey: publicKey) == pin
    }
}
