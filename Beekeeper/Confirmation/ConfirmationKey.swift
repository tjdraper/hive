import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum ConfirmationKeyError: Error, Equatable {
    case secureEnclaveUnavailable
    case couldNotSetAccessControl
    /// The person cancelled the prompt.
    case cancelled
    /// The prompt failed for another reason, such as too many attempts.
    case notConfirmed
}

/// The second key this device keeps for each Hive, which asks for Face ID or Touch ID, or the passcode or
/// the account password on a device without them, every time it signs. Hive refuses anything that deletes backups, sends a secret
/// somewhere new or unpairs devices without its signature, so an open session alone can't do any of it (§6).
nonisolated enum ConfirmationKey {
    static func make() throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard SecureEnclave.isAvailable else { throw ConfirmationKeyError.secureEnclaveUnavailable }
        return try SecureEnclave.P256.Signing.PrivateKey(accessControl: accessControl())
    }

    /// Asks for Face ID, Touch ID or the password, saying `reason`, then signs `statement` with the key saved as
    /// `keyData`. Off the main actor, so the window keeps drawing while the prompt is up.
    @concurrent static func sign(_ statement: Data, keyData: Data, reason: String) async throws -> Data {
        let context = LAContext()
        do {
            _ = try await context.evaluateAccessControl(accessControl(), operation: .useKeySign, localizedReason: prompt(for: reason))
        } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
            throw ConfirmationKeyError.cancelled
        } catch is LAError {
            throw ConfirmationKeyError.notConfirmed
        }
        // The context has already asked, so signing with it doesn't ask again.
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: keyData, authenticationContext: context)
        return try key.signature(for: statement).rawRepresentation
    }

    /// macOS puts "Beekeeper is trying to" before the reason, and iOS shows it as it is.
    private static func prompt(for reason: String) -> String {
        #if os(macOS)
        reason
        #else
        "Allow Beekeeper to \(reason)."
        #endif
    }

    /// How this device asks, such as "Face ID or the passcode", for saying what wasn't accepted.
    static var askedWith: String {
        let context = LAContext()
        // Fills in `biometryType`, which is unknown until a policy has been checked.
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        #if os(macOS)
        let fallback = "the password"
        #else
        let fallback = "the passcode"
        #endif
        switch context.biometryType {
        case .faceID: return "Face ID or \(fallback)"
        case .touchID: return "Touch ID or \(fallback)"
        case .opticID: return "Optic ID or \(fallback)"
        case .none: return fallback
        @unknown default: return fallback
        }
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
