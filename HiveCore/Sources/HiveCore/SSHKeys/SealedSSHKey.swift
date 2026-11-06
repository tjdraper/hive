import Foundation

/// A new SSH key, sealed and ready to store.
struct SealedSSHKey {
    let sealedSeed: SealedSecret
    let publicKey: OpenSSHPublicKey

    init(_ key: SSHKeyPair, sealer: SecretSealer) throws {
        sealedSeed = try sealer.seal(key.seed)
        publicKey = key.publicKey
    }
}
