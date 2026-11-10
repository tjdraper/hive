import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum ConfirmationKeyError: Error, Equatable {
    case secureEnclaveUnavailable
    case couldNotSetAccessControl
    /// The person cancelled Touch ID or the password prompt.
    case cancelled
    /// Touch ID or the password prompt failed for another reason, such as too many attempts.
    case notConfirmed
}

/// The second key this device keeps for each Hive, which asks for Touch ID or, on a Mac without it, the
/// account password, every time it signs. Hive refuses anything that deletes backups, sends a secret
/// somewhere new or unpairs devices without its signature, so an open session alone can't do any of it (§6).
nonisolated enum ConfirmationKey {
    static func make() throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard SecureEnclave.isAvailable else { throw ConfirmationKeyError.secureEnclaveUnavailable }
        return try SecureEnclave.P256.Signing.PrivateKey(accessControl: accessControl())
    }

    /// Asks for Touch ID or the password, saying `reason`, then signs `statement` with the key saved as
    /// `keyData`. Off the main actor, so the window keeps drawing while the prompt is up.
    @concurrent static func sign(_ statement: Data, keyData: Data, reason: String) async throws -> Data {
        let context = LAContext()
        do {
            _ = try await context.evaluateAccessControl(accessControl(), operation: .useKeySign, localizedReason: reason)
        } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
            throw ConfirmationKeyError.cancelled
        } catch is LAError {
            throw ConfirmationKeyError.notConfirmed
        }
        // The context has already asked, so signing with it doesn't ask again.
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: keyData, authenticationContext: context)
        return try key.signature(for: statement).rawRepresentation
    }

    /// Only while the device is unlocked, since a person has to be there to use it.
    private static func accessControl() throws -> SecAccessControl {
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .userPresence],
            nil
        ) else { throw ConfirmationKeyError.couldNotSetAccessControl }
        return accessControl
    }
}
