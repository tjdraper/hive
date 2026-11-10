import CryptoKit
import Foundation
import HiveKit
import Security

enum DeviceKeyError: Error {
    case secureEnclaveUnavailable
    case couldNotSetAccessControl
}

/// What this device keeps to sign in to one Hive: the ID Hive gave it, its Secure Enclave key, and the
/// Hive's key pin. The pin is kept here with the key rather than in the list of Hives, which any program
/// running as the user could change to point Beekeeper at its own key and pass the sign-in on.
struct DeviceCredential: Codable {
    let hiveID: UUID
    let deviceID: UUID
    let pin: PublicKeyPin
    /// The key's saved form, which only this device's Secure Enclave can use.
    let keyData: Data
    /// The saved form of the `ConfirmationKey`, made the first time a change needs confirming.
    var confirmationKeyData: Data?

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
