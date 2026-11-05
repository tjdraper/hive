import CryptoKit
import Foundation
@testable import HiveCore

extension P256.Signing.PrivateKey: IdentitySigningKey {}

/// Software keys in place of the Secure Enclave, which tests never use. The saved form is the raw private key.
struct SoftwareKeyFactory: HiveKeyFactory {
    struct Refused: Error {}

    var refusesToMake = false

    func makeIdentityKey() throws -> CreatedKey<any IdentitySigningKey> {
        guard !refusesToMake else { throw Refused() }
        let key = P256.Signing.PrivateKey()
        return CreatedKey(key: key, savedForm: key.rawRepresentation)
    }

    func identityKey(from savedForm: Data) throws -> any IdentitySigningKey {
        try P256.Signing.PrivateKey(rawRepresentation: savedForm)
    }

    func makeStorageKey() throws -> CreatedKey<any SecretStorageKey> {
        guard !refusesToMake else { throw Refused() }
        let key = P256.KeyAgreement.PrivateKey()
        return CreatedKey(key: key, savedForm: key.rawRepresentation)
    }

    func storageKey(from savedForm: Data) throws -> any SecretStorageKey {
        try P256.KeyAgreement.PrivateKey(rawRepresentation: savedForm)
    }
}
