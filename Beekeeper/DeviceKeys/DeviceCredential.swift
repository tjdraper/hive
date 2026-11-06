import CryptoKit
import Foundation
import Security

enum DeviceKeyError: Error {
    case secureEnclaveUnavailable
    case couldNotSetAccessControl
}

/// What this device keeps to sign in to one Hive: the ID Hive gave it, and its Secure Enclave key.
struct DeviceCredential: Codable {
    let hiveID: UUID
    let deviceID: UUID
    /// The key's saved form, which only this device's Secure Enclave can use.
    let keyData: Data

    func signingKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: keyData)
    }

    /// A key for one Hive. Each Hive gets its own, so two Hives can't tell they share a device.
    /// Beekeeper signs in without asking, so the key can't ask for a password or Touch ID.
    static func makeSigningKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard SecureEnclave.isAvailable else { throw DeviceKeyError.secureEnclaveUnavailable }
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            .privateKeyUsage,
            nil
        ) else { throw DeviceKeyError.couldNotSetAccessControl }
        return try SecureEnclave.P256.Signing.PrivateKey(accessControl: accessControl)
    }
}
