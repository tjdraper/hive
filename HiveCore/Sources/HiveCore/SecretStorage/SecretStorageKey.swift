import CryptoKit
import Foundation

/// The private half of the key secrets are sealed for. The daemon's is in the Secure Enclave, and tests use software keys.
public protocol SecretStorageKey: Sendable {
    var publicKey: P256.KeyAgreement.PublicKey { get }

    func recipient(ciphersuite: HPKE.Ciphersuite, info: Data, encapsulatedKey: Data) throws -> HPKE.Recipient
}

extension SecureEnclave.P256.KeyAgreement.PrivateKey: SecretStorageKey {
    public func recipient(ciphersuite: HPKE.Ciphersuite, info: Data, encapsulatedKey: Data) throws -> HPKE.Recipient {
        try HPKE.Recipient(privateKey: self, ciphersuite: ciphersuite, info: info, encapsulatedKey: encapsulatedKey)
    }
}

extension P256.KeyAgreement.PrivateKey: SecretStorageKey {
    public func recipient(ciphersuite: HPKE.Ciphersuite, info: Data, encapsulatedKey: Data) throws -> HPKE.Recipient {
        try HPKE.Recipient(privateKey: self, ciphersuite: ciphersuite, info: info, encapsulatedKey: encapsulatedKey)
    }
}
